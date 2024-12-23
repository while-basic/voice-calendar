//
//  ContentView.swift
//  voice-calendar
//
//  Created by Christopher Celaya on 12/23/24.
//

import SwiftUI
import AVFoundation
import UserNotifications

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Models
struct Event: Identifiable, Codable {
    var id = UUID()
    var title: String
    var date: Date
    var notes: String?
    var recordingFileName: String?
    var notificationId: String?
    var reminderDate: Date
}

// MARK: - Audio Management
class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingLevel: Float = 0.0
    private var audioRecorder: AVAudioRecorder?
    
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
        #endif
    }
    
    func startRecording() {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        let fileName = "\(UUID().uuidString).m4a"
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            isRecording = true
            
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard let self = self, self.isRecording else {
                    timer.invalidate()
                    return
                }
                self.audioRecorder?.updateMeters()
                self.recordingLevel = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
            }
        } catch {
            print("Could not start recording: \(error)")
        }
    }
    
    func stopRecording() -> String? {
        defer {
            audioRecorder = nil
            isRecording = false
            recordingLevel = 0.0
        }
        
        audioRecorder?.stop()
        return audioRecorder?.url.lastPathComponent
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording failed")
        }
    }
}

class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var audioPlayer: AVAudioPlayer?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    private var progressTimer: Timer?
    
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
        #endif
    }
    
    func startPlayback(fileName: String) {
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            audioPlayer?.play()
            isPlaying = true
            
            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.currentTime = self?.audioPlayer?.currentTime ?? 0
            }
        } catch {
            print("Failed to play recording: \(error)")
        }
    }
    
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.stopPlayback()
        }
    }
}

// MARK: - Notification Management
class NotificationManager {
    static let shared = NotificationManager()
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Error requesting notification permission: \(error)")
            }
        }
    }
    
    func scheduleNotification(for event: Event) {
        guard let notificationId = event.notificationId else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Memory Reminder"
        content.body = "Listen to your recording: \(event.title)"
        content.sound = .default
        
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: event.reminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            }
        }
    }
}

// MARK: - Calendar Views
struct CalendarView: View {
    @Binding var selectedDate: Date
    private let calendar = Calendar.current
    private let daysInWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    
    var body: some View {
        VStack {
            MonthHeaderView(selectedDate: $selectedDate)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(daysInWeek, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                ForEach(days, id: \.self) { date in
                    DayView(date: date, selectedDate: $selectedDate)
                }
            }
        }
    }
    
    private var days: [Date] {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
        let range = calendar.range(of: .day, in: .month, for: start)!
        
        return range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: start)
        }
    }
}

struct MonthHeaderView: View {
    @Binding var selectedDate: Date
    private let calendar = Calendar.current
    
    var body: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .foregroundStyle(.primary)
            }
            
            Spacer()
            
            Text(monthYearString)
                .font(.title2.weight(.semibold))
            
            Spacer()
            
            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal)
    }
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedDate)
    }
    
    private func previousMonth() {
        withAnimation {
            if let newDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) {
                selectedDate = newDate
            }
        }
    }
    
    private func nextMonth() {
        withAnimation {
            if let newDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) {
                selectedDate = newDate
            }
        }
    }
}

struct EventListView: View {
    let events: [Event]
    let selectedDate: Date
    private let calendar = Calendar.current
    
    var filteredEvents: [Event] {
        events.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }
    
    var body: some View {
        List {
            if filteredEvents.isEmpty {
                Text("No memories for this day")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(filteredEvents) { event in
                    MemoryCell(event: event)
                }
            }
        }
        .listStyle(.plain)
    }
}

struct ContentView: View {
    @State private var selectedDate = Date()
    @State private var events: [Event] = []
    @State private var showingAddEvent = false
    @State private var selectedTab = 0
    
    private let calendar = Calendar.current
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                VStack(spacing: 0) {
                    CalendarView(selectedDate: $selectedDate)
                        .padding(.horizontal)
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    EventListView(events: events, selectedDate: selectedDate)
                }
                .navigationTitle("Memories")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showingAddEvent = true }) {
                            Label("Add Memory", systemImage: "plus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .tabItem {
                Label("Calendar", systemImage: "calendar")
            }
            .tag(0)
            
            NavigationView {
                AllMemoriesView(events: events)
                    .navigationTitle("All Memories")
            }
            .tabItem {
                Label("Memories", systemImage: "waveform")
            }
            .tag(1)
        }
        .sheet(isPresented: $showingAddEvent) {
            AddEventView(isPresented: $showingAddEvent, events: $events)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .tint(.blue)
    }
}

struct AllMemoriesView: View {
    let events: [Event]
    
    var body: some View {
        List {
            ForEach(groupedEvents.keys.sorted().reversed(), id: \.self) { date in
                Section(header: Text(formatDate(date))) {
                    ForEach(groupedEvents[date] ?? []) { event in
                        MemoryCell(event: event)
                    }
                }
            }
        }
    }
    
    private var groupedEvents: [Date: [Event]] {
        Dictionary(grouping: events) { event in
            Calendar.current.startOfDay(for: event.date)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }
}

struct MemoryCell: View {
    let event: Event
    @StateObject private var audioPlayer = AudioPlayer()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.headline)
                    
                    if let notes = event.notes {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(event.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if let fileName = event.recordingFileName {
                    Button(action: {
                        if audioPlayer.isPlaying {
                            audioPlayer.stopPlayback()
                        } else {
                            audioPlayer.startPlayback(fileName: fileName)
                        }
                    }) {
                        Image(systemName: audioPlayer.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.blue)
                    }
                    .overlay {
                        if audioPlayer.isPlaying {
                            Circle()
                                .stroke(.blue.opacity(0.2), lineWidth: 2)
                                .frame(width: 44, height: 44)
                        }
                    }
                }
            }
            
            if audioPlayer.isPlaying {
                // Audio progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(.secondary.opacity(0.2))
                            .frame(height: 4)
                        
                        Rectangle()
                            .fill(.blue)
                            .frame(width: geometry.size.width * CGFloat(audioPlayer.currentTime / audioPlayer.duration), height: 4)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 4)
                .padding(.top, 4)
            }
            
            if event.reminderDate > Date() {
                HStack {
                    Image(systemName: "bell.fill")
                        .font(.caption)
                    Text("Reminder: \(event.reminderDate.formatted(.dateTime.day().month().hour().minute()))")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DayView: View {
    let date: Date
    @Binding var selectedDate: Date
    private let calendar = Calendar.current
    
    private var isSelected: Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }
    
    private var isToday: Bool {
        calendar.isDateInToday(date)
    }
    
    var body: some View {
        Text("\(calendar.component(.day, from: date))")
            .font(.system(.body, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background {
                if isSelected {
                    Circle()
                        .fill(.blue)
                        .opacity(0.2)
                } else if isToday {
                    Circle()
                        .strokeBorder(.blue, lineWidth: 1)
                }
            }
            .foregroundStyle(isSelected ? .blue : .primary)
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) {
                    selectedDate = date
                }
            }
    }
}

struct AddEventView: View {
    @Binding var isPresented: Bool
    @Binding var events: [Event]
    @State private var eventTitle = ""
    @State private var eventDate = Date()
    @State private var eventNotes = ""
    @State private var reminderDate = Date()
    @State private var showReminderPicker = true
    @StateObject private var audioRecorder = AudioRecorder()
    @State private var recordingFileName: String?
    @State private var isShowingRecordingPermissionAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Title", text: $eventTitle)
                    DatePicker("Date & Time", selection: $eventDate)
                    TextField("Notes", text: $eventNotes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Memory Details")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        if audioRecorder.isRecording {
                            HStack {
                                Image(systemName: "waveform")
                                    .symbolEffect(.bounce.byLayer, options: .repeating)
                                    .foregroundStyle(.red)
                                Text("Recording...")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(action: stopRecording) {
                                    Label("Stop Recording", systemImage: "stop.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.red)
                                }
                            }
                        } else {
                            if let _ = recordingFileName {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Recording saved")
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Button(action: requestRecordingPermission) {
                                    Label("Start Recording", systemImage: "mic.circle.fill")
                                        .font(.headline)
                                }
                                .foregroundStyle(.blue)
                            }
                        }
                    }
                } header: {
                    Text("Voice Recording")
                }
                
                Section {
                    Toggle("Set Reminder", isOn: $showReminderPicker)
                    
                    if showReminderPicker {
                        DatePicker("Remind me at", selection: $reminderDate, in: eventDate..., displayedComponents: [.date, .hourAndMinute])
                    }
                } header: {
                    Text("Reminder")
                } footer: {
                    if showReminderPicker {
                        Text("You'll receive a notification at the specified time.")
                    }
                }
            }
            .navigationTitle("New Memory")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        addEvent()
                    }
                    .disabled(eventTitle.isEmpty)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .alert("Microphone Access Required", isPresented: $isShowingRecordingPermissionAlert) {
            Button("Cancel", role: .cancel) { }
            #if canImport(UIKit)
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            #endif
        } message: {
            Text("Please allow microphone access in Settings to record voice memories.")
        }
        .onAppear {
            NotificationManager.shared.requestAuthorization()
            reminderDate = Calendar.current.date(byAdding: .hour, value: 1, to: eventDate) ?? eventDate
        }
    }
    
    private func requestRecordingPermission() {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        startRecording()
                    } else {
                        isShowingRecordingPermissionAlert = true
                    }
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        startRecording()
                    } else {
                        isShowingRecordingPermissionAlert = true
                    }
                }
            }
        }
        #else
        startRecording()
        #endif
    }
    
    private func startRecording() {
        audioRecorder.startRecording()
    }
    
    private func stopRecording() {
        recordingFileName = audioRecorder.stopRecording()
    }
    
    private func addEvent() {
        let notificationId = UUID().uuidString
        let newEvent = Event(
            title: eventTitle,
            date: eventDate,
            notes: eventNotes.isEmpty ? nil : eventNotes,
            recordingFileName: recordingFileName,
            notificationId: notificationId,
            reminderDate: showReminderPicker ? reminderDate : eventDate
        )
        events.append(newEvent)
        if showReminderPicker {
            NotificationManager.shared.scheduleNotification(for: newEvent)
        }
        isPresented = false
    }
}

#Preview {
    ContentView()
}
