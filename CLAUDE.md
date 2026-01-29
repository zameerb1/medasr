# MedASR Project Documentation

## Overview

MedASR is a medical speech-to-text transcription system using Google's MedASR model. It consists of:
1. **Python Backend Server** - FastAPI server running on a Windows PC with RTX 4090
2. **SwiftUI iOS App** - iPhone app for recording and transcribing medical dictation

MedASR is a Conformer-based CTC model with 105M parameters, trained on ~5000 hours of physician dictations. It has 58% fewer errors than Whisper on medical dictation.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Tailscale VPN Network                        │
│                                                                      │
│  ┌──────────────┐      ┌─────────────────────────────────────────┐  │
│  │   Mac Mini   │      │     Windows PC (Basement Server)        │  │
│  │ 100.122.251.42│      │     100.126.157.48                      │  │
│  └──────────────┘      │                                         │  │
│         │              │  ┌─────────────────────────────────┐    │  │
│         │              │  │ MedASR Server (Port 8000)       │    │  │
│  ┌──────────────┐      │  │ - google/medasr model (105M)    │    │  │
│  │   iPhone     │◄────►│  │ - FastAPI backend               │    │  │
│  │ (MedASR App) │      │  │ - CUDA acceleration (RTX 4090)  │    │  │
│  └──────────────┘      │  │ - CTC-based decoding            │    │  │
│         │              │  └─────────────────────────────────┘    │  │
│         │              │                                         │  │
│  ┌──────────────┐      │  Hardware:                              │  │
│  │  Xcode Dev   │      │  - NVIDIA RTX 4090 (24GB VRAM)          │  │
│  │   Machine    │      │  - Windows 11                           │  │
│  └──────────────┘      └─────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## Server Details

### Windows Server Access

- **Tailscale IP**: 100.126.157.48
- **Hostname**: ukpc
- **SSH User**: drsam
- **SSH Command**: `ssh drsam@100.126.157.48`

### MedASR Server (Port 8000)

- **URL**: http://100.126.157.48:8000
- **Model**: google/medasr (105M parameter CTC model)
- **Python Environment**: C:\MedASR\server\venv_win

#### Directory Structure on Windows
```
C:\MedASR\
├── server\
│   ├── main.py           # FastAPI server (Windows-compatible)
│   ├── transcribe.py     # MedASR model wrapper with CTC decoding
│   ├── requirements.txt  # Python dependencies
│   └── venv_win\         # Python virtual environment
└── start_server.bat      # Startup script
```

#### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Health check |
| `/health` | GET | Detailed health status (model loaded, device) |
| `/transcribe` | POST | Transcribe audio file (WAV, M4A, MP3) |
| `/transcribe/long` | POST | Transcribe longer audio with chunking |

#### Example API Usage

```bash
# Transcribe audio file
curl -X POST "http://100.126.157.48:8000/transcribe" \
  -F "file=@recording.m4a"

# Response
{
  "success": true,
  "text": "The patient presents with symptoms of...",
  "filename": "recording.m4a"
}
```

## iOS App

### Project Structure
```
MedASR/
├── MedASRApp/
│   ├── MedASRApp.swift          # App entry point
│   ├── ContentView.swift         # Main UI with record button
│   ├── AudioRecorder.swift       # AVAudioRecorder wrapper
│   ├── TranscriptionService.swift # API client
│   └── Info.plist                # Microphone permission
└── MedASRApp.xcodeproj/
```

### Features
- **Record Button** - Tap to start/stop recording
- **Audio Level Meter** - Visual feedback during recording
- **Transcription Display** - Scrollable text view with results
- **Settings** - Configure server URL
- **Copy/Clear** - Quick actions for transcription text

### Building the iOS App
1. Open `MedASRApp.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Update server URL in Settings to `http://100.126.157.48:8000`
4. Build and run on device (Simulator can't record real audio)

## Hugging Face Authentication

MedASR is a **gated** model and requires:
1. A Hugging Face account
2. Accepting the model terms at: https://huggingface.co/google/medasr
3. HF token configured on the server

**Token Location**: `C:\Users\drsam\.cache\huggingface\token`

## Starting the Server

### Via SSH from Mac

```bash
# Start MedASR (port 8000)
ssh -f drsam@100.126.157.48 'set HF_TOKEN=<your_huggingface_token> && set PATH=C:\ffmpeg-8.0.1-essentials_build\bin;%PATH% && cd C:\MedASR\server && C:\MedASR\server\venv_win\Scripts\pythonw.exe -m uvicorn main:app --host 0.0.0.0 --port 8000'
```

### Check Server Status

```bash
curl -s http://100.126.157.48:8000/health
```

### Stop Server

```bash
ssh drsam@100.126.157.48 'taskkill /F /IM pythonw.exe'
```

## Dependencies on Windows

### Python 3.11
- Location: `C:\Program Files\Python311\`

### FFmpeg (for audio conversion)
- Location: `C:\ffmpeg-8.0.1-essentials_build\bin\`
- Required for converting M4A to WAV

### PyTorch with CUDA 12.1
- Installed in venv
- Uses RTX 4090 GPU

## CTC Decoding Implementation

MedASR is a CTC (Connectionist Temporal Classification) model, not a sequence-to-sequence model like Whisper. Key implementation details:

```python
# CTC decoding: collapse repeated tokens and remove blanks
blank_id = self.processor.tokenizer.pad_token_id or 0

collapsed_ids = []
prev_id = None
for token_id in predicted_ids[0].tolist():
    if token_id != blank_id and token_id != prev_id:
        collapsed_ids.append(token_id)
    prev_id = token_id

text = self.processor.tokenizer.decode(collapsed_ids, skip_special_tokens=True)
```

This manual CTC collapse fixes the stuttering/duplication issue where output would show "I I I amm goinging" instead of "I am going".

## Known Issues & Solutions

### 1. CTC Token Duplication
Without proper CTC decoding, output shows repeated tokens. The `transcribe.py` includes manual token collapse to fix this.

### 2. Windows File Locking
Windows can lock temp files during processing. The server uses `shutil.rmtree(ignore_errors=True)` to handle this.

### 3. iOS Simulator Cannot Record
The iOS Simulator records silent audio files. Test on a real iPhone device.

### 4. First Request Latency
- First request: ~30 seconds (downloads and loads model)
- Subsequent requests: Fast

### 5. Audio Format Conversion
iOS records M4A by default. The server uses FFmpeg + pydub to convert to 16kHz WAV as required by MedASR.

## Related Projects

- **MedGemma**: Medical image analysis (Port 8001 on same server)
- **MedGemma Web**: https://zameerb1.github.io/medgemma-web/

## Commands Reference

```bash
# SSH to Windows
ssh drsam@100.126.157.48

# Check GPU
ssh drsam@100.126.157.48 'nvidia-smi'

# List running Python processes
ssh drsam@100.126.157.48 'tasklist | findstr python'

# Kill all Python processes
ssh drsam@100.126.157.48 'taskkill /F /IM pythonw.exe'

# Check Tailscale status (Mac)
/Applications/Tailscale.app/Contents/MacOS/Tailscale status
```

## Model Information

| Property | Value |
|----------|-------|
| Model ID | google/medasr |
| Architecture | Conformer-based CTC |
| Parameters | 105M |
| Training Data | ~5000 hours physician dictations |
| Sample Rate | 16kHz mono |
| Improvement | 58% fewer errors than Whisper on medical dictation |
