//
//  TranscriptionService.swift
//  MedASRApp
//
//  API client for the MedASR transcription server
//

import Foundation

/// Represents the transcription response from the server
struct TranscriptionResponse: Codable {
    let success: Bool
    let text: String
    let filename: String?
}

/// Represents an error response from the server
struct ErrorResponse: Codable {
    let detail: String
}

/// Service for communicating with the MedASR backend
class TranscriptionService: ObservableObject {

    // MARK: - Published Properties

    @Published var isProcessing = false
    @Published var lastError: String?

    // MARK: - Configuration

    /// Base URL for the transcription server
    /// Update this to your server URL (e.g., ngrok URL for local testing)
    var serverURL: String {
        get { UserDefaults.standard.string(forKey: "serverURL") ?? "http://localhost:8000" }
        set { UserDefaults.standard.set(newValue, forKey: "serverURL") }
    }

    // MARK: - Public Methods

    /// Transcribe an audio file
    /// - Parameters:
    ///   - fileURL: URL to the audio file
    ///   - useLongEndpoint: Use chunked processing for longer audio
    /// - Returns: Transcribed text
    func transcribe(fileURL: URL, useLongEndpoint: Bool = false) async throws -> String {
        await MainActor.run {
            isProcessing = true
            lastError = nil
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        let endpoint = useLongEndpoint ? "/transcribe/long" : "/transcribe"
        guard let url = URL(string: serverURL + endpoint) else {
            throw TranscriptionError.invalidURL
        }

        // Create multipart form request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120 // 2 minute timeout for transcription

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body
        let httpBody = try createMultipartBody(fileURL: fileURL, boundary: boundary)
        request.httpBody = httpBody

        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            // Try to parse error message
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw TranscriptionError.serverError(errorResponse.detail)
            }
            throw TranscriptionError.httpError(httpResponse.statusCode)
        }

        // Parse response
        let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)

        if !transcriptionResponse.success {
            throw TranscriptionError.transcriptionFailed
        }

        return transcriptionResponse.text
    }

    /// Check if the server is reachable
    func checkServerHealth() async -> Bool {
        guard let url = URL(string: serverURL + "/health") else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            print("Health check failed: \(error)")
        }

        return false
    }

    // MARK: - Private Methods

    private func createMultipartBody(fileURL: URL, boundary: String) throws -> Data {
        var body = Data()

        let filename = fileURL.lastPathComponent
        let mimeType = getMimeType(for: fileURL)

        // File data
        let fileData = try Data(contentsOf: fileURL)

        // Multipart form field for file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }

    private func getMimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "wav":
            return "audio/wav"
        case "m4a":
            return "audio/m4a"
        case "mp3":
            return "audio/mpeg"
        case "mp4":
            return "audio/mp4"
        case "aac":
            return "audio/aac"
        case "ogg":
            return "audio/ogg"
        case "flac":
            return "audio/flac"
        default:
            return "application/octet-stream"
        }
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case serverError(String)
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "Server error (HTTP \(code))"
        case .serverError(let message):
            return message
        case .transcriptionFailed:
            return "Transcription failed"
        }
    }
}
