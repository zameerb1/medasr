"""
MedASR Backend Server
FastAPI server for medical speech-to-text transcription
"""

import os
import tempfile
import logging
from pathlib import Path

from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydub import AudioSegment

from transcribe import get_transcriber, transcribe_audio

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="MedASR Medical Transcription API",
    description="API for transcribing medical audio using speech recognition",
    version="1.0.0"
)

# Configure CORS for iOS app access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for development
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Supported audio formats
SUPPORTED_FORMATS = {".wav", ".m4a", ".mp3", ".mp4", ".aac", ".ogg", ".flac"}


def convert_to_wav(input_path: str, output_path: str) -> str:
    """
    Convert audio file to WAV format at 16kHz mono.

    Args:
        input_path: Path to input audio file
        output_path: Path for output WAV file

    Returns:
        Path to the converted WAV file
    """
    logger.info(f"Converting {input_path} to WAV format")

    # Load audio with pydub
    audio = AudioSegment.from_file(input_path)

    # Convert to mono and set sample rate to 16kHz
    audio = audio.set_channels(1)
    audio = audio.set_frame_rate(16000)

    # Export as WAV
    audio.export(output_path, format="wav")

    logger.info(f"Converted to: {output_path}")
    return output_path


@app.on_event("startup")
async def startup_event():
    """Pre-load the model on server startup."""
    logger.info("Starting MedASR server...")
    # Optionally pre-load model (uncomment to load at startup)
    # This increases startup time but reduces first request latency
    # get_transcriber().load_model()
    logger.info("Server started successfully")


@app.get("/")
async def root():
    """Health check endpoint."""
    return {"status": "ok", "service": "MedASR Medical Transcription API"}


@app.get("/health")
async def health_check():
    """Detailed health check."""
    return {
        "status": "healthy",
        "model_loaded": get_transcriber()._loaded,
        "device": get_transcriber().device
    }


@app.post("/transcribe")
async def transcribe_endpoint(file: UploadFile = File(...)):
    """
    Transcribe an audio file to text.

    Args:
        file: Audio file (WAV, M4A, MP3, etc.)

    Returns:
        JSON with transcribed text
    """
    # Validate file
    if not file.filename:
        raise HTTPException(status_code=400, detail="No filename provided")

    file_ext = Path(file.filename).suffix.lower()
    if file_ext not in SUPPORTED_FORMATS:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported format: {file_ext}. Supported: {', '.join(SUPPORTED_FORMATS)}"
        )

    logger.info(f"Received file: {file.filename} ({file.content_type})")

    try:
        # Create temp directory for processing
        with tempfile.TemporaryDirectory() as temp_dir:
            # Save uploaded file
            input_path = os.path.join(temp_dir, f"input{file_ext}")
            with open(input_path, "wb") as f:
                content = await file.read()
                f.write(content)

            logger.info(f"Saved upload to: {input_path} ({len(content)} bytes)")

            # Convert to WAV if needed
            if file_ext != ".wav":
                wav_path = os.path.join(temp_dir, "audio.wav")
                convert_to_wav(input_path, wav_path)
                audio_path = wav_path
            else:
                audio_path = input_path

            # Transcribe
            text = transcribe_audio(audio_path)

            return JSONResponse(content={
                "success": True,
                "text": text,
                "filename": file.filename
            })

    except Exception as e:
        logger.error(f"Transcription error: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Transcription failed: {str(e)}"
        )


@app.post("/transcribe/long")
async def transcribe_long_endpoint(file: UploadFile = File(...)):
    """
    Transcribe a longer audio file using chunked processing.
    Use this for audio files longer than 30 seconds.

    Args:
        file: Audio file (WAV, M4A, MP3, etc.)

    Returns:
        JSON with transcribed text
    """
    # Validate file
    if not file.filename:
        raise HTTPException(status_code=400, detail="No filename provided")

    file_ext = Path(file.filename).suffix.lower()
    if file_ext not in SUPPORTED_FORMATS:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported format: {file_ext}. Supported: {', '.join(SUPPORTED_FORMATS)}"
        )

    logger.info(f"Received long audio file: {file.filename}")

    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            # Save uploaded file
            input_path = os.path.join(temp_dir, f"input{file_ext}")
            with open(input_path, "wb") as f:
                content = await file.read()
                f.write(content)

            # Convert to WAV if needed
            if file_ext != ".wav":
                wav_path = os.path.join(temp_dir, "audio.wav")
                convert_to_wav(input_path, wav_path)
                audio_path = wav_path
            else:
                audio_path = input_path

            # Transcribe with chunking
            transcriber = get_transcriber()
            text = transcriber.transcribe_chunks(audio_path)

            return JSONResponse(content={
                "success": True,
                "text": text,
                "filename": file.filename
            })

    except Exception as e:
        logger.error(f"Long transcription error: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Transcription failed: {str(e)}"
        )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
