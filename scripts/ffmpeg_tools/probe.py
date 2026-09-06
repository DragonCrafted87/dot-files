"""Read-only ffprobe helpers."""

from json import loads as read_json

from .process import run_process


def probe(input_filename, *extra_flags):
    process = run_process(
        [
            "ffprobe",
            "-v",
            "quiet",
            "-print_format",
            "json",
            *extra_flags,
            input_filename,
        ]
    )
    return read_json(process.stdout)


def probe_media(input_filename):
    return probe(
        input_filename,
        "-show_format",
        "-show_streams",
        "-show_programs",
        "-show_chapters",
    )


def get_chapter_list(input_filename):
    probe_data = probe(input_filename, "-show_chapters")
    return [
        {
            "index": chapter["id"],
            "start": float(chapter["start_time"]),
            "end": float(chapter["end_time"]),
        }
        for chapter in probe_data.get("chapters", [])
    ]


def get_file_duration(input_filename):
    probe_data = probe(input_filename, "-show_entries", "format=duration")
    return float(probe_data["format"]["duration"])


def get_file_raw_metadata(input_filename):
    process = run_process(["ffmpeg", "-i", input_filename, "-f", "ffmetadata", "-"])
    return_value = [";FFMETADATA1"]
    for line in process.stdout.splitlines():
        if line.startswith("[CHAPTER]"):
            break
        if line.startswith("encoder"):
            return_value.append(line)
    return return_value


def offset_chapter_list(chapter_list, time_offset, chapter_offset):
    for chapter in chapter_list:
        chapter["start"] = chapter["start"] + time_offset
        chapter["end"] = chapter["end"] + time_offset
        chapter_offset += 1
        chapter["title"] = f"Chapter {chapter_offset}"
    return chapter_offset


def append_chapter_list_to_metadata(metadata, chapter_list):
    for chapter in chapter_list:
        metadata.append("[CHAPTER]")
        metadata.append("TIMEBASE=1/1000")
        metadata.append(f"START={int(chapter['start'] * 1000)}")
        metadata.append(f"END={int(chapter['end'] * 1000)}")
        metadata.append(f"title={chapter['title']}")


def stream_types(probe_data):
    return [stream["codec_type"] for stream in probe_data.get("streams", [])]
