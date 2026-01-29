//
//  AudioRecorder.swift
//  MedASRApp
//
//  Handles audio recording using AVAudioRecorder
//

import Foundation
import AVFoundation

/// Manages audio recording for the transcription app
class AudioRecorder: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var levelTimer: Timer?
    private var recordingURL: URL?

    // MARK: - Recording Settings

    private let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    // MARK: - Public Methods

    /// Request microphone permission
    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if !granted {
                    self.errorMessage = "Microphone permission denied. Please enable in Settings."
                }
                completion(granted)
            }
        }
    }

    /// Start recording audio
    func startRecording() {
        // Reset state
        errorMessage = nil
        recordingTime = 0

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            errorMessage = "Failed to configure audio session: \(error.localizedDescription)"
            return
        }

        // Create recording URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = Date().timeIntervalSince1970
        recordingURL = documentsPath.appendingPathComponent("recording_\(Int(timestamp)).m4a")

        guard let url = recordingURL else {
            errorMessage = "Failed to create recording URL"
            return
        }

        // Create and start recorder
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: recordingSettings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.delegate = self
            audioRecorder?.record()

            isRecording = true
            startTimers()

        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    /// Stop recording and return the audio file URL
    func stopRecording() -> URL? {
        stopTimers()

        audioRecorder?.stop()
        isRecording = false

        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }

        return recordingURL
    }

    /// Cancel recording and delete the file
    func cancelRecording() {
        stopTimers()

        audioRecorder?.stop()
        isRecording = false

        // Delete the recording file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil

        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }

    /// Delete a recording file
    func deleteRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private Methods

    private func startTimers() {
        // Recording duration timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder else { return }
            self.recordingTime = recorder.currentTime
        }

        // Audio level meter timer
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder else { return }
            recorder.updateMeters()
            let level = recorder.averagePower(forChannel: 0)
            // Convert dB to 0-1 range
            let normalizedLevel = max(0, (level + 60) / 60)
            self.audioLevel = normalizedLevel
        }
    }

    private func stopTimers() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        audioLevel = 0
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            errorMessage = "Recording finished unsuccessfully"
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            errorMessage = "Recording error: \(error.localizedDescription)"
        }
    }
}
