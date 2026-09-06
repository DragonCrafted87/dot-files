#!/usr/bin/env python3

"""
Dictation script using pywhispercpp for real-time speech-to-text.
"""

import argparse
import datetime
import os
import queue
import subprocess
import sys
import time

import numpy as np
import speech_recognition as sr
from pywhispercpp.model import Model


def pad_audio(audio_np, min_samples=32000):
    """
    Pad the audio with silence if it's shorter than min_samples.
    """
    if len(audio_np) < min_samples:
        padding = np.zeros(min_samples - len(audio_np), dtype=np.float32)
        audio_np = np.concatenate((audio_np, padding))
    return audio_np


def check_ollama_running():
    """
    Check if any Ollama models are running by parsing 'ollama ps' output.
    """
    try:
        output = subprocess.check_output(
            ["ollama", "ps"], stderr=subprocess.STDOUT
        ).decode("utf-8")
        lines = output.strip().splitlines()
        if len(lines) > 1:
            print("Warning: Ollama models are currently running:")
            print(output)
            print(
                "This may cause GPU memory conflicts. Try stopping them with "
                "'ollama stop <model>' before proceeding."
            )
            input("Press Enter to continue anyway, or Ctrl+C to abort...")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print(
            "Ollama not found or 'ollama ps' failed. Skipping Ollama running "
            "models check."
        )


def main():
    """
    Main function to handle argument parsing, microphone setup, model loading,
    and the transcription loop.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--model",
        default="medium",
        help="Model to use",
        choices=["tiny", "base", "small", "medium", "large"],
    )
    parser.add_argument(
        "--non_english", action="store_true", help="Don't use the english model."
    )
    parser.add_argument(
        "--models_dir",
        default=os.path.expanduser("~/ai/whisper-cpp/models"),
        help="Directory to store and load models from.",
    )
    parser.add_argument(
        "--energy_threshold",
        default=1000,
        help="Energy level for mic to detect.",
        type=int,
    )
    parser.add_argument(
        "--record_timeout",
        default=5,
        help="How real time the recording is in seconds.",
        type=float,
    )
    parser.add_argument(
        "--phrase_timeout",
        default=3,
        help="How much empty space between recordings before we "
        "consider it a new line in the transcription.",
        type=float,
    )
    parser.add_argument(
        "--threads",
        default=16,
        help="Number of threads for Whisper model processing.",
        type=int,
    )
    parser.add_argument(
        "--strategy",
        default="greedy",
        help="Decoding strategy: greedy or beam_search.",
        choices=["greedy", "beam_search"],
    )
    parser.add_argument(
        "--beam_size",
        default=5,
        help="Beam size for beam_search (higher accuracy, lower speed).",
        type=int,
    )
    parser.add_argument(
        "--best_of",
        default=3,
        help="Best of for greedy strategy (higher accuracy, lower speed).",
        type=int,
    )
    parser.add_argument(
        "--patience",
        default=1.0,
        help="Patience for beam_search (-1.0 disables; higher is slower).",
        type=float,
    )
    if "linux" in sys.platform:
        parser.add_argument(
            "--default_microphone",
            default="pulse",
            help="Default microphone name for SpeechRecognition. "
            "Run this with 'list' to view available Microphones.",
            type=str,
        )
    args = parser.parse_args()

    if not os.path.exists(args.models_dir):
        os.makedirs(args.models_dir)

    if sys.maxsize < 2**32:
        print(
            "Warning: Running on 32-bit Python. Large models may fail to load due "
            "to memory limits. Consider using 64-bit Python or a smaller model."
        )

    # Check for running Ollama models before loading Whisper
    check_ollama_running()

    # The last time a recording was retrieved from the queue.
    phrase_time = None
    # Thread safe Queue for passing data from the threaded recording callback.
    data_queue = queue.Queue()
    # Bytes object which holds audio data for the current phrase
    phrase_bytes = bytes()
    # SpeechRecognizer can detect when speech ends.
    recorder = sr.Recognizer()
    recorder.energy_threshold = args.energy_threshold
    recorder.dynamic_energy_threshold = False

    # Important for linux users.
    # Prevents hang/crash by using the wrong Microphone
    if "linux" in sys.platform:
        mic_name = args.default_microphone
        if not mic_name or mic_name == "list":
            print("Available microphone devices are: ")
            for index, name in enumerate(sr.Microphone.list_microphone_names()):
                print(f'Microphone with name "{name}" found')
            return
        for index, name in enumerate(sr.Microphone.list_microphone_names()):
            if mic_name in name:
                source = sr.Microphone(sample_rate=16000, device_index=index)
                break
        else:
            print(f'Microphone with name containing "{mic_name}" not found')
            return
    else:
        source = sr.Microphone(sample_rate=16000)

    # Load / Download model
    model_name = args.model
    if args.model != "large" and not args.non_english:
        model_name += ".en"
    audio_model = Model(model_name, models_dir=args.models_dir, n_threads=args.threads)

    # Test model load with a small silent audio
    try:
        test_audio = np.zeros(32000, dtype=np.float32)
        test_audio = pad_audio(test_audio)
        audio_model.transcribe(test_audio, language="en")
    except Exception as e:  # pylint: disable=broad-exception-caught
        print(f"Failed to load or test model: {e}")
        print(
            "This may be due to insufficient memory. Try a smaller model, close "
            "other applications, or check your system configuration."
        )
        return

    record_timeout = args.record_timeout
    phrase_timeout = args.phrase_timeout

    transcription = [""]

    with source:
        recorder.adjust_for_ambient_noise(source)

    def record_callback(_, audio: sr.AudioData) -> None:
        """
        Threaded callback function to receive audio data when recordings finish.
        audio: An AudioData containing the recorded bytes.
        """
        data = audio.get_raw_data()
        data_queue.put(data)

    # Create a background thread that will pass us raw audio bytes.
    recorder.listen_in_background(
        source, record_callback, phrase_time_limit=record_timeout
    )

    # Cue the user that we're ready to go.
    print("Model loaded.\n")

    while True:
        try:
            now = datetime.datetime.utcnow()
            # Pull raw recorded audio from the queue.
            if not data_queue.empty():
                # Enough idle time means the phrase is complete.
                if phrase_time and now - phrase_time > datetime.timedelta(
                    seconds=phrase_timeout
                ):
                    if len(phrase_bytes) > 0:
                        # Convert in-ram buffer to something the model can use.
                        audio_np = (
                            np.frombuffer(phrase_bytes, dtype=np.int16).astype(
                                np.float32
                            )
                            / 32768.0
                        )
                        audio_np = pad_audio(audio_np)

                        # Read the transcription.
                        language = "en" if not args.non_english else None
                        params = {}
                        if args.strategy == "greedy":
                            params["greedy"] = {"best_of": args.best_of}
                        elif args.strategy == "beam_search":
                            params["beam_search"] = {
                                "beam_size": args.beam_size,
                                "patience": args.patience,
                            }
                        result = audio_model.transcribe(
                            audio_np, language=language, **params
                        )
                        text = " ".join(
                            segment.text.strip() for segment in result
                        ).strip()

                        # Append the completed phrase
                        transcription.append(text)

                        # Clear the console to reprint the updated transcription.
                        os.system("cls" if os.name == "nt" else "clear")
                        for line in transcription:
                            print(line)
                        print("", end="", flush=True)

                    phrase_bytes = bytes()

                # This is the last time we received new audio data from the queue.
                phrase_time = now

                # Combine audio data from queue
                audio_data_list = []
                while not data_queue.empty():
                    audio_data_list.append(data_queue.get())
                audio_data = b"".join(audio_data_list)

                # Add the new audio data to the accumulated data for this phrase
                phrase_bytes += audio_data
            else:
                time.sleep(0.25)
        except KeyboardInterrupt:
            break

    print("\n\nTranscription:")
    for line in transcription:
        print(line)


if __name__ == "__main__":
    main()
