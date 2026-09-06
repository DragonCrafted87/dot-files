"""Convert common audio files to FLAC and archive the originals."""

from os import utime
from os.path import dirname
from os.path import getmtime
from os.path import relpath
from pathlib import Path
from subprocess import CalledProcessError

from .process import run_process

AUDIO_SUFFIXES = {".mp3", ".wav", ".aac", ".m4a", ".ogg"}


def convert_file_to_flac(source_path):
    source = Path(source_path)
    dest = source.with_suffix(".flac")
    run_process(
        [
            "ffmpeg",
            "-i",
            str(source),
            "-c:a",
            "flac",
            "-compression_level",
            "12",
            "-map_metadata",
            "0",
            str(dest),
        ]
    )
    utime(dest, (getmtime(source), getmtime(source)))
    archive_dir = Path("archives") / Path(relpath(dirname(source) or "."))
    archive_dir.mkdir(parents=True, exist_ok=True)
    source.rename(archive_dir / source.name)
    print(f"Converted {source} to {dest}")
    print(f"Moved original file to {archive_dir}")
    return str(dest)


def convert_audio_tree(search_dir="."):
    root = Path(search_dir)
    written = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if path.suffix.lower() not in AUDIO_SUFFIXES:
            continue
        if "archives" in path.parts:
            continue
        try:
            written.append(convert_file_to_flac(path))
        except (CalledProcessError, OSError) as exc:
            print(f"Failed to convert {path}: {exc}")
    return written
