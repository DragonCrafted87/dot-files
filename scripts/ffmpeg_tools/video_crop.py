"""Cropdetect + re-encode to h264/flac mkv."""

from glob import glob
from os import makedirs
from os import rename
from subprocess import CalledProcessError

from .pool import encoding_executor
from .pool import wait_jobs
from .probe import probe_media
from .probe import stream_types
from .process import run_process


def detect_crop(input_filename):
    process = run_process(
        ["ffmpeg", "-i", input_filename, "-vf", "cropdetect", "-f", "null", "-"]
    )
    crop_data = [
        line.split("crop=")[1]
        for line in process.stderr.splitlines()[-32:]
        if "cropdetect" in line and "crop=" in line
    ]
    if not crop_data:
        raise RuntimeError(f"no cropdetect output for {input_filename}")
    return crop_data[-1]


def video_crop_encode(input_filename, output_filename):
    print(f"Scanning: {input_filename}")
    try:
        types = stream_types(probe_media(input_filename))
        crop_value = detect_crop(input_filename)

        makedirs("cropped", exist_ok=True)
        makedirs("original", exist_ok=True)

        print(f"Encoding: {input_filename}")
        args = ["ffmpeg", "-v", "quiet", "-i", input_filename]
        args.extend(["-filter:v:0", f"crop={crop_value}"])

        if "video" in types:
            types.remove("video")
            args.extend(["-map", "0:v:0", "-vcodec", "h264"])

        if "audio" in types:
            while "audio" in types:
                types.remove("audio")
            args.extend(["-map", "0:a", "-acodec", "flac"])

        if "subtitle" in types:
            while "subtitle" in types:
                types.remove("subtitle")
            args.extend(["-map", "0:s", "-scodec", "copy"])

        if "video" in types:
            types.remove("video")
            args.extend(["-map", "0:v:1"])

        if "data" in types:
            types.remove("data")

        if types:
            raise RuntimeError(f"unhandled streams: {types}")

        args.extend([f"cropped/{output_filename}", "-y"])
        run_process(args)

        print(f"Finalizing: {input_filename}")
        rename(input_filename, f"original/{input_filename}")
        return output_filename
    except (CalledProcessError, OSError, RuntimeError, KeyError, ValueError) as exc:
        print(f"{input_filename} generated an exception: {exc}")
        return f"Failed Processing {input_filename}"


def encode_all_video_files():
    file_list = glob("*.mkv") + glob("*.mp4") + glob("*.avi") + glob("*.webm")
    print(f"Encoding {len(file_list)} files.")
    executor = encoding_executor()
    futures = []
    for file_name in file_list:
        output_filename = file_name.rsplit(".", 1)[0] + ".mkv"
        futures.append(executor.submit(video_crop_encode, file_name, output_filename))
    wait_jobs(futures)
