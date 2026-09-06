# ffmpeg.py refactor notes

Working notes on `scripts/ffmpeg.py`. Not finished. Branch `ffmpeg-refactor`.

## What the file actually is

One module, four jobs, plus a CLI:

| Command                                    | What it does                                  | External binaries                   |
| ------------------------------------------ | --------------------------------------------- | ----------------------------------- |
| `video-crop-encode`                        | cropdetect + re-encode to h264/flac mkv       | ffmpeg, ffprobe                     |
| `video-append` / `video-merge-crop-encode` | concat demuxer + rebuilt chapter metadata     | ffmpeg, ffprobe                     |
| `audio-split-encode`                       | Audible AAX + scrape narrator + Windows path  | ffmpeg, ffprobe, requests           |
| `make-dvd`                                 | chapter-split to ntsc-dvd, dvdauthor, mkisofs | ffmpeg, ffprobe, dvdauthor, mkisofs |

`bashrc.d/ffmpeg.bashrc` still shells out to the CLI for concat/split and only calls the Python file for crop, dvd, and audio.

## Proposed package layout

Keep `scripts/ffmpeg.py` as a thin `__main__` so existing wrappers keep working.

```text
scripts/
  ffmpeg.py                 # argparse + dispatch only
  ffmpeg_tools/
    __init__.py
    probe.py                # duration, streams, chapters, tags
    process.py              # run() wrapper, later PyAV where it fits
    video_crop.py
    video_concat.py
    audio_audible.py        # unfinished; Windows S:\ path
    dvd.py                  # encode chapters, dvdauthor xml, mkisofs
    pool.py                 # ThreadPoolExecutor helpers
```

Split lines, not new features. `audio_split_encode` is half-written (never encodes tracks) and hard-codes `S:\Media\\Books\\Audiobooks`. Treat it as its own module so the video path does not carry that.

## Library vs subprocess

Options:

- **ffmpeg-python / python-ffmpeg** — still `Popen` the CLI. Cleaner argv builder, same binaries, same cropdetect/concat/ntsc-dvd flags. Low risk.
- **PyAV (`av`)** — real libav bindings. Good for probe (replace most `ffprobe -print_format json`). Encoding filters like `cropdetect` and the concat demuxer are awkward or missing. DVD target and dvdauthor are out of scope.
- **Stay on CLI** for encode/concat/dvd. That is what those tools are.

Recommendation: PyAV (or keep ffprobe JSON) for **read-only probe**. Keep the ffmpeg/dvdauthor/mkisofs CLIs for **write** paths. Do not wrap encode in PyAV on the first pass.

`import-error` on `requests` goes away once workstation pip-installs it (already in `install-python-dev`) and pylint runs in that env, or we vendor a typed optional import.

## Pylint overrides to drop

| Current disable        | Why it fires                                  | How to drop it                                                     |
| ---------------------- | --------------------------------------------- | ------------------------------------------------------------------ |
| `too-many-locals`      | crop/concat/audio each do probe + IO + encode | split functions                                                    |
| `too-many-statements`  | same                                          | split functions                                                    |
| `too-many-branches`    | `main()` command switch                       | `dict` of handlers                                                 |
| `broad-except`         | bare `except Exception` in every worker       | catch `CalledProcessError` / `OSError` / `KeyError`                |
| `unspecified-encoding` | `open(...)` without encoding in audio         | `encoding="utf-8"`                                                 |
| `invalid-name`         | `f` as file handle                            | `metadata_file`                                                    |
| `import-error`         | `requests` not in pylint env                  | keep requests; document; optional `--disable` only in CI if needed |

`.pylintrc` already disables several complexity checks globally. Prefer fixing the functions over adding more file-level disables.

## Workstation packages

Already present: `ffmpeg` in `install-desktop-packages` (workstation includes that). Missing for this script:

- `ffprobe` (same ffmpeg package on OpenMandriva, verify)
- `dvdauthor`
- `genisoimage` or `mkisofs` (script calls `mkisofs`)
- `python3` + user `requests` (python-dev)

`install-ffmpeg-tools.sh` on this branch adds those and a `mkisofs` symlink if only `genisoimage` exists.

## Known bugs to not lose

- `video-merge-crop-encode` uses `input_file` after the loop; that name is undefined.
- `audio_split_encode` never returns success; always "Failed Processing".
- concat `file` lines are unquoted; spaces in names break concat.
- `video_append` closes temp handles in `finally` that may not exist if `open` failed.
- bash wrappers pass `--input_filename=` (singular); argparse expects `--input_filenames`.
