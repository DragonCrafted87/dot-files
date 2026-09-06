"""Run ffmpeg-family CLIs."""

from subprocess import CalledProcessError
from subprocess import run


def run_process(args, debug=False):
    process = run(args, capture_output=True, text=True, check=False)
    if debug:
        print(process.stderr)
        print(process.stdout)
    process.check_returncode()
    return process


def run_or_log(args, label, debug=False):
    try:
        return run_process(args, debug=debug)
    except CalledProcessError as exc:
        print(f"{label}: {exc}")
        raise
