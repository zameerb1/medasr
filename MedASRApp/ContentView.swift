//
//  ContentView.swift
//  MedASRApp
//
//  Main UI for medical transcription
//

import SwiftUI

struct ContentView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var transcriptionService = TranscriptionService()

    @State private var transcriptionText = ""
    @State private var statusMessage = "Ready to record"
    @State private var showSettings = false
    @State private var serverURL = ""
    @State private var hasPermission = false

    enum AppState {
        case idle
        case recording
        case processing
    }

    @State private var appState: AppState = .idle

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Status Section
                statusSection

                // Transcription Display
                transcriptionSection

                Spacer()

                // Record Button
                recordButton

                // Recording Time
                if appState == .recording {
                    Text(formatTime(audioRecorder.recordingTime))
                        .font(.title2)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .navigationTitle("MedASR")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        serverURL = transcriptionService.serverURL
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                settingsSheet
            }
            .onAppear {
                checkPermission()
            }
            .alert("Error", isPresented: .constant(audioRecorder.errorMessage != nil)) {
                Button("OK") {
                    audioRecorder.errorMessage = nil
                }
            } message: {
                Text(audioRecorder.errorMessage ?? "")
            }
        }
    }

    // MARK: - View Components

    private var statusSection: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)

            Text(statusMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal)
    }

    private var statusColor: Color {
        switch appState {
        case .idle:
            return .green
        case .recording:
            return .red
        case .processing:
            return .orange
        }
    }

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcription")
                .font(.headline)
                .foregroundColor(.secondary)

            ScrollView {
                Text(transcriptionText.isEmpty ? "Your transcription will appear here..." : transcriptionText)
                    .font(.body)
                    .foregroundColor(transcriptionText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(maxHeight: 300)
            .background(Color(.systemGray6))
            .cornerRadius(12)

            if !transcriptionText.isEmpty {
                HStack {
                    Button {
                        UIPasteboard.general.string = transcriptionText
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        transcriptionText = ""
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
    }

    private var recordButton: some View {
        Button {
            handleRecordButton()
        } label: {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(appState == .recording ? Color.red : Color.blue, lineWidth: 4)
                    .frame(width: 80, height: 80)

                // Audio level indicator (when recording)
                if appState == .recording {
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 80 * CGFloat(0.5 + audioRecorder.audioLevel * 0.5),
                               height: 80 * CGFloat(0.5 + audioRecorder.audioLevel * 0.5))
                        .animation(.easeOut(duration: 0.05), value: audioRecorder.audioLevel)
                }

                // Inner button
                if appState == .recording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red)
                        .frame(width: 30, height: 30)
                } else if appState == .processing {
                    ProgressView()
                        .scaleEffect(1.5)
                } else {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 60, height: 60)
                }
            }
        }
        .disabled(appState == .processing || !hasPermission)
        .animation(.easeInOut(duration: 0.2), value: appState)
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Server Configuration") {
                    TextField("Server URL", text: $serverURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()

                    Button("Test Connection") {
                        testConnection()
                    }
                }

                Section("Presets") {
                    Button("Local (localhost:8000)") {
                        serverURL = "http://localhost:8000"
                    }

                    Button("ngrok Example") {
                        serverURL = "https://your-ngrok-url.ngrok.io"
                    }
                }

                Section("About") {
                    Text("MedASR uses speech recognition to transcribe medical audio recordings.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        transcriptionService.serverURL = serverURL
                        showSettings = false
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func checkPermission() {
        audioRecorder.requestPermission { granted in
            hasPermission = granted
            if !granted {
                statusMessage = "Microphone access required"
            }
        }
    }

    private func handleRecordButton() {
        switch appState {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .processing:
            break
        }
    }

    private func startRecording() {
        audioRecorder.startRecording()
        appState = .recording
        statusMessage = "Recording..."
    }

    private func stopRecording() {
        guard let audioURL = audioRecorder.stopRecording() else {
            statusMessage = "Recording failed"
            appState = .idle
            return
        }

        appState = .processing
        statusMessage = "Transcribing..."

        Task {
            do {
                let text = try await transcriptionService.transcribe(fileURL: audioURL)

                await MainActor.run {
                    transcriptionText = text
                    statusMessage = "Transcription complete"
                    appState = .idle
                }

                // Clean up audio file
                audioRecorder.deleteRecording(at: audioURL)

            } catch {
                await MainActor.run {
                    statusMessage = "Error: \(error.localizedDescription)"
                    appState = .idle
                }
            }
        }
    }

    private func testConnection() {
        Task {
            transcriptionService.serverURL = serverURL
            let isHealthy = await transcriptionService.checkServerHealth()

            await MainActor.run {
                if isHealthy {
                    statusMessage = "Server connected!"
                } else {
                    statusMessage = "Cannot connect to server"
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let tenths = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

#Preview {
    ContentView()
}
