"""Concat helpers: stream-copy with chapters, or re-encode h264/flac."""

from os import close as close_file_descriptor
from os import getcwd
from os import makedirs
from os import remove
from os import rename
from os.path import basename
from subprocess import CalledProcessError
from tempfile import mkstemp as make_temp_file

from .probe import append_chapter_list_to_metadata
from .probe import get_chapter_list
from .probe import get_file_duration
from .probe import get_file_raw_metadata
from .probe import offset_chapter_list
from .process import run_process


def _temp_name():
    descriptor, path = make_temp_file(dir=getcwd())
    close_file_descriptor(descriptor)
    return basename(path)


def _write_concat_list(input_filenames):
    list_name = _temp_name()
    with open(list_name, "w", encoding="utf8") as list_file:
        for input_file in input_filenames:
            print(f"file '{input_file}'", file=list_file, flush=True)
    return list_name


def video_append(input_filenames, output_filename):
    temp_file_list_name = _temp_name()
    temp_metadata_name = _temp_name()
    try:
        print(f"Merging: {input_filenames} into {output_filename}")
        metadata = None
        previous_total_duration = 0
        previous_final_chapter = 0

        with open(temp_file_list_name, "w", encoding="utf8") as list_file:
            for input_file in input_filenames:
                print(f"file '{input_file}'", file=list_file, flush=True)
                current_chapter_list = get_chapter_list(input_file)
                current_file_duration = get_file_duration(input_file)
                if previous_total_duration == 0:
                    metadata = get_file_raw_metadata(input_file)
                previous_final_chapter = offset_chapter_list(
                    current_chapter_list,
                    previous_total_duration,
                    previous_final_chapter,
                )
                previous_total_duration += current_file_duration
                append_chapter_list_to_metadata(metadata, current_chapter_list)

        with open(temp_metadata_name, "w", encoding="utf8") as metadata_file:
            for line in metadata:
                print(line, file=metadata_file, flush=True)

        run_process(
            [
                "ffmpeg",
                "-v",
                "quiet",
                "-f",
                "concat",
                "-safe",
                "0",
                "-i",
                temp_file_list_name,
                "-i",
                temp_metadata_name,
                "-map_metadata",
                "1",
                "-map",
                "0",
                "-c",
                "copy",
                output_filename,
            ],
            debug=True,
        )

        print(f"Moving Files: {input_filenames}")
        makedirs("original", exist_ok=True)
        for input_file in input_filenames:
            rename(input_file, f"original/{input_file}")
        return (False, f"Finished Processing {output_filename}")
    except (CalledProcessError, OSError, KeyError, TypeError, ValueError) as exc:
        print(f"{output_filename} generated an exception: {exc}")
        return (False, f"Failed Processing {output_filename}")
    finally:
        for name in (temp_file_list_name, temp_metadata_name):
            try:
                remove(name)
            except OSError:
                pass


def concatenate_videos(output_stem, input_filenames):
    if not input_filenames:
        raise ValueError("concatenate needs at least one input file")
    output_filename = output_stem
    if not output_filename.endswith(".mkv"):
        output_filename = f"{output_stem}.mkv"
    list_name = _write_concat_list(input_filenames)
    try:
        print(f"Concatenating {input_filenames} -> {output_filename}")
        run_process(
            [
                "ffmpeg",
                "-f",
                "concat",
                "-safe",
                "0",
                "-i",
                list_name,
                "-map_metadata",
                "0",
                "-map_chapters",
                "0",
                "-acodec",
                "flac",
                "-vcodec",
                "h264",
                "-scodec",
                "copy",
                output_filename,
            ]
        )
        return output_filename
    finally:
        try:
            remove(list_name)
        except OSError:
            pass


def merge_split_chapters(base_file, chapters_per_episode, total_chapters):
    chapters_per_episode = int(chapters_per_episode)
    total_chapters = int(total_chapters)
    if chapters_per_episode < 1:
        raise ValueError("chapters_per_episode must be >= 1")
    total_episodes = total_chapters // chapters_per_episode
    chapter = 1
    written = []
    for episode in range(1, total_episodes + 1):
        inputs = []
        for _ in range(chapters_per_episode):
            inputs.append(f"{base_file}_split_{chapter:03d}.mkv")
            chapter += 1
        output_stem = f"{base_file}_e{episode:03d}"
        print(f"Episode {episode}: {inputs} -> {output_stem}.mkv")
        written.append(concatenate_videos(output_stem, inputs))
    return written
