#!/usr/bin/env python3
# Thin CLI. Implementation lives in scripts/ffmpeg_tools/.

from argparse import ArgumentParser

from ffmpeg_tools.audio_audible import audio_split_encode
from ffmpeg_tools.audio_audible import encode_all_audio_files
from ffmpeg_tools.dvd import create_all_dvds
from ffmpeg_tools.dvd import create_dvd
from ffmpeg_tools.video_concat import video_append
from ffmpeg_tools.video_crop import encode_all_video_files
from ffmpeg_tools.video_crop import video_crop_encode


def _as_list(value):
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return list(value)
    return [value]


def cmd_video_crop_encode(args):
    names = _as_list(args.input_filenames)
    if not names:
        encode_all_video_files()
        return
    for input_file in names:
        output_filename = input_file.rsplit(".", 1)[0] + ".mkv"
        video_crop_encode(input_file, output_filename)


def cmd_audio_split_encode(args):
    names = _as_list(args.input_filenames)
    if not names:
        encode_all_audio_files()
        return
    for input_file in names:
        audio_split_encode(input_file)


def cmd_video_merge_crop_encode(args):
    names = _as_list(args.input_filenames)
    continue_processing, _ = video_append(names, args.output_filename)
    if continue_processing:
        output_filename = args.output_filename.rsplit(".", 1)[0] + ".mkv"
        video_crop_encode(args.output_filename, output_filename)


def cmd_make_dvd(args):
    names = _as_list(args.input_filenames)
    if not names:
        create_all_dvds()
        return
    for input_file in names:
        create_dvd(input_file)


COMMANDS = {
    "video-crop-encode": cmd_video_crop_encode,
    "audio-split-encode": cmd_audio_split_encode,
    "video-merge-crop-encode": cmd_video_merge_crop_encode,
    "make-dvd": cmd_make_dvd,
}


def main():
    parser = ArgumentParser(description="ffmpeg helpers")
    parser.add_argument("command", choices=sorted(COMMANDS), help="What Are We Doin?")
    parser.add_argument(
        "-i",
        "--input_filenames",
        "--input_filename",
        dest="input_filenames",
        help="Input filename",
        nargs="*",
    )
    parser.add_argument("-o", "--output_filename", help="Output filename")
    args = parser.parse_args()
    print(args)
    COMMANDS[args.command](args)


if __name__ == "__main__":
    main()
