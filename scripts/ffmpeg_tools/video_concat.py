"""Concat demuxer + rebuilt chapter metadata."""

from os import close as close_file_descriptor
from os import getcwd
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
