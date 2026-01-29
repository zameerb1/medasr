"""
MedASR Model Wrapper for Medical Speech-to-Text Transcription
Uses Google's MedASR model from Hugging Face
"""

import torch
import librosa
import numpy as np
from transformers import AutoModelForCTC, AutoProcessor
from typing import Optional
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class MedASRTranscriber:
    """Wrapper for medical speech recognition using Google's MedASR model."""

    def __init__(self, model_id: str = "google/medasr", device: Optional[str] = None):
        """
        Initialize the transcriber with Google's MedASR model.

        MedASR is a Conformer-based medical ASR model with 105M parameters,
        trained on ~5000 hours of physician dictations across specialties.
        It has 58% fewer errors than Whisper on medical dictation.

        Args:
            model_id: HuggingFace model identifier
            device: Device to run on ('cuda', 'mps', 'cpu', or None for auto)
        """
        self.model_id = model_id
        self.device = self._get_device(device)
        self.processor = None
        self.model = None
        self._loaded = False

    def _get_device(self, device: Optional[str]) -> str:
        """Determine the best available device."""
        if device:
            return device
        if torch.cuda.is_available():
            return "cuda"
        if torch.backends.mps.is_available():
            return "mps"
        return "cpu"

    def load_model(self):
        """Load the model and processor. Call this before transcribing."""
        if self._loaded:
            return

        logger.info(f"Loading MedASR model {self.model_id} on {self.device}...")

        self.processor = AutoProcessor.from_pretrained(self.model_id)
        self.model = AutoModelForCTC.from_pretrained(self.model_id)
        self.model.to(self.device)
        self.model.eval()

        self._loaded = True
        logger.info("MedASR model loaded successfully")

    def transcribe(self, audio_path: str) -> str:
        """
        Transcribe an audio file to text using MedASR.

        Args:
            audio_path: Path to the audio file (WAV, M4A, MP3, etc.)

        Returns:
            Transcribed text string
        """
        if not self._loaded:
            self.load_model()

        logger.info(f"Transcribing: {audio_path}")

        # Load and resample audio to 16kHz (required by MedASR)
        audio, sr = librosa.load(audio_path, sr=16000, mono=True)

        # Ensure audio is float32 numpy array
        audio = audio.astype(np.float32)

        # Check for empty or too short audio
        duration = len(audio) / sr
        logger.info(f"Audio duration: {duration:.2f}s, samples: {len(audio)}")

        if len(audio) == 0:
            raise ValueError("Audio file is empty. Please record some audio before transcribing.")

        if duration < 0.1:
            raise ValueError(f"Audio too short ({duration:.2f}s). Please record at least 0.5 seconds of audio.")

        # Check if audio is silent
        max_amplitude = np.max(np.abs(audio))
        logger.info(f"Max amplitude: {max_amplitude}")

        if max_amplitude < 0.001:
            raise ValueError("Audio appears to be silent.")

        # Process audio with MedASR processor
        inputs = self.processor(
            audio,
            sampling_rate=16000,
            return_tensors="pt",
            padding=True
        )

        # Move inputs to device
        inputs = {k: v.to(self.device) for k, v in inputs.items()}

        # Run forward pass to get logits (CTC model)
        with torch.no_grad():
            logits = self.model(**inputs).logits

        # Get predicted token IDs using argmax
        predicted_ids = torch.argmax(logits, dim=-1)

        # CTC decoding: collapse repeated tokens and remove blanks
        # Get the blank token ID (usually 0 for CTC models)
        blank_id = self.processor.tokenizer.pad_token_id or 0

        # Manual CTC collapse: remove consecutive duplicates and blanks
        collapsed_ids = []
        prev_id = None
        for token_id in predicted_ids[0].tolist():
            if token_id != blank_id and token_id != prev_id:
                collapsed_ids.append(token_id)
            prev_id = token_id

        # Decode the collapsed tokens
        text = self.processor.tokenizer.decode(collapsed_ids, skip_special_tokens=True)
        text = text.strip()

        # Clean up any remaining artifacts
        import re
        text = re.sub(r'<[^>]+>', '', text)  # Remove any XML-like tags
        text = re.sub(r'\s+', ' ', text)  # Collapse multiple spaces
        text = text.strip()

        logger.info(f"Transcription complete: {len(text)} characters")

        return text

    def transcribe_chunks(self, audio_path: str, chunk_length_s: int = 20, stride_length_s: int = 2) -> str:
        """
        Transcribe longer audio files in chunks.

        Args:
            audio_path: Path to the audio file
            chunk_length_s: Length of each chunk in seconds
            stride_length_s: Overlap between chunks in seconds

        Returns:
            Full transcribed text
        """
        if not self._loaded:
            self.load_model()

        logger.info(f"Transcribing in chunks: {audio_path}")

        # For chunked transcription, use the pipeline
        from transformers import pipeline

        pipe = pipeline(
            "automatic-speech-recognition",
            model=self.model,
            tokenizer=self.processor,
            feature_extractor=self.processor.feature_extractor,
            device=self.device if self.device != "mps" else "cpu",
        )

        # Load audio
        audio, sr = librosa.load(audio_path, sr=16000, mono=True)

        result = pipe(
            audio,
            chunk_length_s=chunk_length_s,
            stride_length_s=stride_length_s
        )

        text = result.get("text", "").strip()
        logger.info(f"Chunked transcription complete: {len(text)} characters")

        return text


# Global transcriber instance (lazy loaded)
_transcriber: Optional[MedASRTranscriber] = None


def get_transcriber() -> MedASRTranscriber:
    """Get or create the global transcriber instance."""
    global _transcriber
    if _transcriber is None:
        _transcriber = MedASRTranscriber()
    return _transcriber


def transcribe_audio(audio_path: str) -> str:
    """
    Convenience function to transcribe an audio file.

    Args:
        audio_path: Path to the audio file

    Returns:
        Transcribed text
    """
    transcriber = get_transcriber()
    return transcriber.transcribe(audio_path)
