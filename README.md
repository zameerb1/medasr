# MedASR - Medical Speech-to-Text Transcription

A SwiftUI iPhone app with a Python backend for medical audio transcription.

## Project Structure

```
MedASR/
├── server/                    # Python backend
│   ├── main.py               # FastAPI server
│   ├── transcribe.py         # MedASR model wrapper
│   └── requirements.txt      # Python dependencies
├── MedASRApp/                 # iOS app source
│   ├── MedASRApp.swift       # App entry point
│   ├── ContentView.swift     # Main UI
│   ├── AudioRecorder.swift   # Audio recording logic
│   ├── TranscriptionService.swift  # API client
│   └── Info.plist            # App configuration
└── MedASRApp.xcodeproj/      # Xcode project
```

## Setup Instructions

### 1. Python Backend

```bash
# Navigate to server directory
cd MedASR/server

# Create virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Start the server
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

The server will be available at `http://localhost:8000`

### 2. Expose Server for iOS Testing

For testing on a real iPhone, you need to expose your local server:

**Option A: ngrok (Recommended)**
```bash
# Install ngrok
brew install ngrok

# Expose the server
ngrok http 8000
```
Copy the HTTPS URL (e.g., `https://abc123.ngrok.io`)

**Option B: Local network**
Find your Mac's IP address and use `http://<ip>:8000`

### 3. iOS App

1. Open `MedASRApp.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run on simulator or device
4. Tap the gear icon to configure the server URL
5. Enter your ngrok URL or local server address

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Health check |
| `/health` | GET | Detailed health status |
| `/transcribe` | POST | Transcribe audio file |
| `/transcribe/long` | POST | Transcribe long audio with chunking |

### Example curl Request

```bash
curl -X POST -F "file=@recording.m4a" http://localhost:8000/transcribe
```

### Response Format

```json
{
  "success": true,
  "text": "The patient presents with symptoms of...",
  "filename": "recording.m4a"
}
```

## Model Information

The backend uses OpenAI's Whisper large-v3 model via Hugging Face Transformers. This model provides excellent transcription quality for medical terminology.

For specialized medical ASR, consider:
- Fine-tuning Whisper on medical datasets
- Using NVIDIA's Parakeet model
- Training a custom model on medical transcription data

## iOS App Features

- **Record Button**: Tap to start/stop recording
- **Audio Level Meter**: Visual feedback during recording
- **Transcription Display**: Scrollable text view with results
- **Copy/Clear**: Quick actions for transcription text
- **Settings**: Configure server URL
- **Connection Test**: Verify server connectivity

## Requirements

### Backend
- Python 3.9+
- ~2GB disk space for model download
- CPU or GPU (CUDA/MPS supported)

### iOS App
- iOS 17.0+
- Xcode 15.0+
- Microphone permission

## Troubleshooting

**Server won't start**
- Check Python version: `python3 --version`
- Ensure all dependencies installed: `pip install -r requirements.txt`
- Check port 8000 is available

**iOS can't connect**
- Verify server is running
- Check URL in Settings (include http:// or https://)
- For local testing, ensure both devices on same network
- For ngrok, use the HTTPS URL

**Transcription fails**
- Check server logs for errors
- Ensure audio file is valid (WAV, M4A, MP3)
- First request may be slow (model loading)

## License

MIT License
