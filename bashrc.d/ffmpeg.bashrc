#!/usr/bin/env bash
# Thin wrappers around scripts/ffmpeg.py. Implementations live in
# scripts/ffmpeg_tools/. Each function prints usage if called wrong.

_ffmpeg_py() {
    python -I "${DOTFILES_ROOT:-$HOME/dot-files}/scripts/ffmpeg.py" "$@"
}

_ffmpeg_usage() {
    printf '%s\n' "$1" >&2
    return 2
}

# Concatenate inputs into STEM.mkv (h264 + flac + copied subs).
#   ffmpeg-concatenate-videos episode01 part_a.mkv part_b.mkv part_c.mkv
#   # writes episode01.mkv
function ffmpeg-concatenate-videos ()
{
    if [[ $# -lt 2 ]]; then
        _ffmpeg_usage "usage: ffmpeg-concatenate-videos STEM file1.mkv [file2.mkv ...]"
        return
    fi
    local stem="$1"
    shift
    _ffmpeg_py video-concatenate --output_filename "$stem" --input_filenames "$@"
}

# Stream-copy slices. One mark = that time through EOF. Several marks =
# consecutive [mark_n, mark_n+1) segments. Writes NAME_split_001.mkv ...
#   ffmpeg-video-split-by-timestamps show.mkv 600
#   ffmpeg-video-split-by-timestamps show.mkv 0 600 1200 1800
function ffmpeg-video-split-by-timestamps ()
{
    if [[ $# -lt 2 ]]; then
        _ffmpeg_usage "usage: ffmpeg-video-split-by-timestamps FILE START [NEXT ...]"
        return
    fi
    local file="$1"
    shift
    _ffmpeg_py video-split-by-timestamps --input_filenames "$file" --timestamps "$@"
}

# Same as split-by-timestamps, bounds taken from chapter end_time values.
#   ffmpeg-video-split-by-chapters show.mkv
function ffmpeg-video-split-by-chapters ()
{
    if [[ $# -ne 1 ]]; then
        _ffmpeg_usage "usage: ffmpeg-video-split-by-chapters FILE"
        return
    fi
    _ffmpeg_py video-split-by-chapters --input_filenames "$1"
}

# Group already-split files BASE_split_001.mkv ... into episode files.
# 20 splits / 5 per episode -> BASE_e001.mkv .. BASE_e004.mkv
#   ffmpeg-video-merge-chapters show 5 20
function ffmpeg-video-merge-chapters ()
{
    if [[ $# -ne 3 ]]; then
        _ffmpeg_usage "usage: ffmpeg-video-merge-chapters BASE CHAPTERS_PER_EPISODE TOTAL_CHAPTERS"
        return
    fi
    _ffmpeg_py video-merge-chapters \
        --base "$1" \
        --chapters-per-episode "$2" \
        --total-chapters "$3"
}

# Cropdetect + re-encode every mkv/mp4/avi/webm in cwd, or one file.
# Writes cropped/NAME.mkv and moves the source to original/.
#   ffmpeg-video-crop-encode
#   ffmpeg-video-crop-encode show.mkv
function ffmpeg-video-crop-encode ()
{
    if [[ -z "${1:-}" ]]; then
        _ffmpeg_py video-crop-encode
    else
        _ffmpeg_py video-crop-encode --input_filenames "$@"
    fi
}

# Build an NTSC DVD ISO from one mkv (or every mkv in cwd).
#   ffmpeg-video-make-dvd
#   ffmpeg-video-make-dvd show.mkv
function ffmpeg-video-make-dvd ()
{
    if [[ -z "${1:-}" ]]; then
        _ffmpeg_py make-dvd
    else
        _ffmpeg_py make-dvd --input_filenames "$@"
    fi
}

# Unfinished Audible AAX scrape. Encode path is not implemented yet.
#   ffmpeg-audio-split-encode
#   ffmpeg-audio-split-encode book_B002V0Q3T4.aax
function ffmpeg-audio-split-encode ()
{
    if [[ -z "${1:-}" ]]; then
        _ffmpeg_py audio-split-encode
    else
        _ffmpeg_py audio-split-encode --input_filenames "$@"
    fi
}

# Convert mp3/wav/aac/m4a/ogg under DIR (default .) to flac, archive sources.
#   ffmpeg-audio-convert
#   ffmpeg-audio-convert ./incoming
function ffmpeg-audio-convert ()
{
    _ffmpeg_py audio-convert --search-dir "${1:-.}"
}
