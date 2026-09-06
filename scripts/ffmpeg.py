#!/usr/bin/env python3
# Thin CLI. Implementation lives in scripts/ffmpeg_tools/.

from argparse import ArgumentParser
from argparse import RawDescriptionHelpFormatter

from ffmpeg_tools.audio_audible import audio_split_encode
from ffmpeg_tools.audio_audible import encode_all_audio_files
from ffmpeg_tools.audio_convert import convert_audio_tree
from ffmpeg_tools.dvd import create_all_dvds
from ffmpeg_tools.dvd import create_dvd
from ffmpeg_tools.jellyfin import DEFAULT_JOB_NAME
from ffmpeg_tools.jellyfin import confirm_and_apply
from ffmpeg_tools.jellyfin import load_job
from ffmpeg_tools.jellyfin import planned_moves
from ffmpeg_tools.jellyfin import write_template
from ffmpeg_tools.video_concat import concatenate_videos
from ffmpeg_tools.video_concat import merge_split_chapters
from ffmpeg_tools.video_concat import video_append
from ffmpeg_tools.video_crop import encode_all_video_files
from ffmpeg_tools.video_crop import video_crop_encode
from ffmpeg_tools.video_split import split_by_chapters
from ffmpeg_tools.video_split import split_by_timestamps

EXAMPLES = """
examples:
  %(prog)s video-crop-encode
  %(prog)s video-crop-encode -i show.mkv
  %(prog)s video-concatenate -o episode01 -i part_a.mkv part_b.mkv
  %(prog)s video-split-by-timestamps -i show.mkv --timestamps 0 600 1200
  %(prog)s video-split-by-chapters -i show.mkv
  %(prog)s video-merge-chapters --base show --chapters-per-episode 5 --total-chapters 20
  %(prog)s make-dvd -i show.mkv
  %(prog)s audio-convert --search-dir .
  %(prog)s audio-split-encode -i book_B002V0Q3T4.aax
  %(prog)s jellyfin-init --kind tv
  %(prog)s jellyfin-sort --job jellyfin.job
"""


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


def cmd_video_concatenate(args):
    names = _as_list(args.input_filenames)
    if not args.output_filename or not names:
        raise SystemExit("video-concatenate needs -o STEMSOURCE and -i files")
    concatenate_videos(args.output_filename, names)


def cmd_video_split_by_timestamps(args):
    names = _as_list(args.input_filenames)
    if len(names) != 1:
        raise SystemExit("video-split-by-timestamps needs exactly one -i file")
    timestamps = _as_list(args.timestamps)
    split_by_timestamps(names[0], timestamps)


def cmd_video_split_by_chapters(args):
    names = _as_list(args.input_filenames)
    if len(names) != 1:
        raise SystemExit("video-split-by-chapters needs exactly one -i file")
    split_by_chapters(names[0])


def cmd_video_merge_chapters(args):
    if (
        not args.base
        or args.chapters_per_episode is None
        or args.total_chapters is None
    ):
        raise SystemExit(
            "video-merge-chapters needs --base, --chapters-per-episode, --total-chapters"
        )
    merge_split_chapters(args.base, args.chapters_per_episode, args.total_chapters)


def cmd_audio_convert(args):
    convert_audio_tree(args.search_dir or ".")


def cmd_jellyfin_init(args):
    write_template(
        args.kind or "tv",
        search_dir=args.search_dir,
        job_path=args.job or DEFAULT_JOB_NAME,
        title=args.title or "",
    )


def cmd_jellyfin_sort(args):
    job = load_job(args.job or DEFAULT_JOB_NAME)
    confirm_and_apply(planned_moves(job, args.search_dir))


COMMANDS = {
    "video-crop-encode": cmd_video_crop_encode,
    "audio-split-encode": cmd_audio_split_encode,
    "video-merge-crop-encode": cmd_video_merge_crop_encode,
    "make-dvd": cmd_make_dvd,
    "video-concatenate": cmd_video_concatenate,
    "video-split-by-timestamps": cmd_video_split_by_timestamps,
    "video-split-by-chapters": cmd_video_split_by_chapters,
    "video-merge-chapters": cmd_video_merge_chapters,
    "audio-convert": cmd_audio_convert,
    "jellyfin-init": cmd_jellyfin_init,
    "jellyfin-sort": cmd_jellyfin_sort,
    "jellyfin-plan": cmd_jellyfin_sort,
    "jellyfin-apply": cmd_jellyfin_sort,
}


def main():
    parser = ArgumentParser(
        description="ffmpeg helpers",
        formatter_class=RawDescriptionHelpFormatter,
        epilog=EXAMPLES,
    )
    parser.add_argument("command", choices=sorted(COMMANDS), help="What Are We Doin?")
    parser.add_argument(
        "-i",
        "--input_filenames",
        "--input_filename",
        dest="input_filenames",
        help="Input filename(s)",
        nargs="*",
    )
    parser.add_argument("-o", "--output_filename", help="Output filename or stem")
    parser.add_argument("--timestamps", nargs="*", help="Split start/end marks")
    parser.add_argument("--base", help="Split-file prefix for merge-chapters")
    parser.add_argument(
        "--chapters-per-episode", type=int, help="How many split files per episode"
    )
    parser.add_argument("--total-chapters", type=int, help="How many split files exist")
    parser.add_argument(
        "--search-dir", default=".", help="Root for audio-convert / jellyfin sources"
    )
    parser.add_argument("--job", default=DEFAULT_JOB_NAME, help="Jellyfin job file")
    parser.add_argument(
        "--kind", choices=("tv", "movie"), help="jellyfin-init library kind"
    )
    parser.add_argument("--title", help="jellyfin-init title / show tag")
    args = parser.parse_args()
    print(args)
    COMMANDS[args.command](args)


if __name__ == "__main__":
    main()
