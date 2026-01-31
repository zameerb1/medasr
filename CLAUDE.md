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
│  ┌──────────────┐      │  ┌─────────────────────────────────┐    │  │
│  │ Synology NAS │      │  │ MedGemma Server (Port 8001)     │    │  │
│  │ 100.94.125.84│      │  │ - google/medgemma-1.5-4b-it     │    │  │
│  │ (DS1522+)    │      │  │ - Medical image analysis        │    │  │
│  └──────────────┘      │  └─────────────────────────────────┘    │  │
│                        │                                         │  │
│                        │  Hardware:                              │  │
│                        │  - NVIDIA RTX 4090 (24GB VRAM)          │  │
│                        │  - Windows 11                           │  │
│                        └─────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## Devices on Tailscale

| Device | Tailscale IP | Type | Notes |
|--------|--------------|------|-------|
| Mac Mini | 100.122.251.42 | macOS | Development machine |
| Windows PC (ukpc) | 100.126.157.48 | Windows | GPU server, RTX 4090 |
| Synology NAS (ds1522plus) | 100.94.125.84 | Linux | DS1522+, DSM 7.2 |
| iPhone | 100.95.208.110 | iOS | MedASR app testing |

## Windows Server (ukpc)

### SSH Access
```bash
ssh drsam@100.126.157.48
```
- **Password**: 0786
- **Auto-login**: Configured
- **Startup script**: Servers auto-start on boot

### MedGemma Server (Port 8001)
- **URL**: http://100.126.157.48:8001
- **Model**: google/medgemma-1.5-4b-it
- **Web UI**: https://zameerb1.github.io/medgemma-web/

### MedASR Server (Port 8000)
- **URL**: http://100.126.157.48:8000
- **Model**: google/medasr

### Start Servers Manually
```bash
ssh -f drsam@100.126.157.48 'cd C:\MedGemma\server && C:\MedGemma\server\venv\Scripts\pythonw.exe -m uvicorn main:app --host 0.0.0.0 --port 8001'
ssh -f drsam@100.126.157.48 'cd C:\MedASR\server && C:\MedASR\server\venv_win\Scripts\pythonw.exe -m uvicorn main:app --host 0.0.0.0 --port 8000'
```

## Synology NAS (DS1522+)

### Access
- **Local IP**: 10.0.7.149
- **Tailscale IP**: 100.94.125.84
- **DSM Web**: http://10.0.7.149:5000
- **SSH Port**: 22 (enabled)

### Users
| Username | Password | 2FA | Notes |
|----------|----------|-----|-------|
| CloudDrive | .NDTEguiFyPpgk9WCC4! | Yes (OTP) | Admin group, needs terminal access enabled |
| synologyinfuse1 | 8YOYBbm80ipAlvLTqTAl | No | Normal user |

### PENDING TASK: Enable SSH for CloudDrive
The CloudDrive user is in admin group but doesn't have Terminal/SSH application permission.

**To fix (in DSM web interface):**
1. Control Panel → User & Group
2. Click CloudDrive → Edit
3. Applications tab
4. Enable "Terminal & SNMP" → Allow
5. Save

**Then SSH will work:**
```bash
sshpass -p '.NDTEguiFyPpgk9WCC4!' ssh CloudDrive@100.94.125.84
```

### Synology API Login (requires 2FA OTP)
```bash
# Step 1: Get OTP prompt
curl -s "http://10.0.7.149:5000/webapi/auth.cgi?api=SYNO.API.Auth&version=3&method=login&account=CloudDrive&passwd=.NDTEguiFyPpgk9WCC4!&format=sid"

# Step 2: Login with OTP code
curl -s "http://10.0.7.149:5000/webapi/auth.cgi?api=SYNO.API.Auth&version=3&method=login&account=CloudDrive&passwd=.NDTEguiFyPpgk9WCC4!&format=sid&otp_code=XXXXXX"
```

## Hugging Face Token
- **Location on Windows**: C:\Users\drsam\.cache\huggingface\token
- Both MedGemma and MedASR are gated models requiring HF authentication

## MCP Servers Configured
- **Playwright**: Browser automation (just added, requires Claude Code restart)

## GitHub Repos
- MedGemma: https://github.com/zameerb1/medgemma
- MedASR: https://github.com/zameerb1/medasr
- MedGemma Web: https://github.com/zameerb1/medgemma-web
