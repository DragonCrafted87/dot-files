"""Split a video by timestamps or by chapter end times."""

from os.path import basename

from .pool import encoding_executor
from .pool import wait_jobs
from .probe import get_chapter_list
from .probe import get_file_duration
from .process import run_process

SPLIT_WORKERS = 3


def _stem(path):
    name = basename(path)
    if "." in name:
        return name.rsplit(".", 1)[0]
    return name


def split_segment(input_filename, output_filename, start_time, end_time):
    print(f"{start_time} {end_time} {output_filename}")
    run_process(
        [
            "ffmpeg",
            "-y",
            "-i",
            input_filename,
            "-ss",
            str(start_time),
            "-to",
            str(end_time),
            "-map",
            "0:v",
            "-vcodec",
            "copy",
            "-map",
            "0:a",
            "-acodec",
            "copy",
            "-map",
            "0:s?",
            "-scodec",
            "copy",
            output_filename,
        ]
    )
    return output_filename


def split_by_timestamps(input_filename, timestamps):
    if not input_filename:
        raise ValueError("missing input file")
    marks = [str(item) for item in timestamps]
    if not marks:
        raise ValueError("need at least one timestamp")

    duration = str(get_file_duration(input_filename))
    if len(marks) == 1:
        bounds = [marks[0], duration]
    else:
        bounds = marks[:]

    stem = _stem(input_filename)
    pairs = list(zip(bounds, bounds[1:]))
    pad = max(3, len(str(len(pairs))))
    executor = encoding_executor()
    futures = []
    for index, (start, end) in enumerate(pairs, start=1):
        output_filename = f"{stem}_split_{index:0{pad}d}.mkv"
        futures.append(
            executor.submit(split_segment, input_filename, output_filename, start, end)
        )
        if index % SPLIT_WORKERS == 0:
            wait_jobs(futures[-SPLIT_WORKERS:], label="split")
    leftover = len(pairs) % SPLIT_WORKERS
    if leftover:
        wait_jobs(futures[-leftover:], label="split")
    return [f"{stem}_split_{index:0{pad}d}.mkv" for index in range(1, len(pairs) + 1)]


def split_by_chapters(input_filename):
    chapters = get_chapter_list(input_filename)
    if not chapters:
        raise ValueError(f"no chapters in {input_filename}")
    timestamps = ["0.0"] + [str(chapter["end"]) for chapter in chapters]
    print(f"chapter bounds: {timestamps}")
    return split_by_timestamps(input_filename, timestamps)
