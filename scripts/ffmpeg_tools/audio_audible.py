"""Unfinished Audible AAX helper. Parked until the encode path exists."""

from glob import glob
from json import load as read_json_file
from os.path import dirname
from pathlib import Path
from pprint import pprint
from subprocess import CalledProcessError

from .pool import encoding_executor
from .pool import wait_jobs
from .probe import probe_media
from .process import run_process

try:
    from requests import get as http_get
except ImportError:
    http_get = None


def audio_split_encode(input_filename):
    """Probe + scrape metadata only. Does not yet split or encode tracks."""
    try:
        if http_get is None:
            raise RuntimeError("requests is not installed")

        probe_data = probe_media(input_filename)
        pprint(probe_data)

        tags = probe_data["format"]["tags"]
        author = tags["artist"]
        summary = tags["comment"]
        title = tags["title"].replace(":", " -")
        print(author)
        print(summary)
        print(title)

        file_stream = http_get(
            f"https://www.audible.com/pd/{input_filename.split('_')[1]}",
            stream=True,
            timeout=30,
        )
        audible_page = file_stream.content.decode("utf-8").split("\n")
        first_filter_pass = [line for line in audible_page if "Narrator" in line]
        second_filter_pass = [line for line in first_filter_pass if "search" in line]
        narrator = second_filter_pass[0].split(">")[1].split("<")[0]
        print(narrator)

        file_list = glob(
            f"{dirname(input_filename)}/*{input_filename.split('_')[1]}*.json"
        )
        pprint(file_list)
        metadata_path = [path for path in file_list if "content_metadata" in path][0]
        with open(metadata_path, "r", encoding="utf-8") as metadata_file:
            content_metadata = read_json_file(metadata_file)["content_metadata"]
        pprint(content_metadata)

        product_path = [
            path
            for path in file_list
            if "content_metadata" not in path and "series_titles" not in path
        ][0]
        with open(product_path, "r", encoding="utf-8") as product_file:
            product_metadata = read_json_file(product_file)["product"]
        pprint(product_metadata)

        output_path = Path("S:\\Media\\Books\\Audiobooks")
        if "series" in product_metadata:
            print(product_metadata["series"][0]["sequence"])
            print(product_metadata["series"][0]["title"])
            output_path = output_path.joinpath(product_metadata["series"][0]["title"])
            output_path.mkdir(parents=True, exist_ok=True)
            output_path = output_path.joinpath(
                f"{product_metadata['series'][0]['sequence']} - {title}"
            )
        else:
            output_path = output_path.joinpath(f"{title}")

        pprint(output_path)
        output_path.mkdir(parents=True, exist_ok=True)

        cover_path = output_path.joinpath("cover.png")
        run_process(
            [
                "ffmpeg",
                "-i",
                input_filename,
                "-map",
                "0:v?",
                "-map",
                "0:V?",
                "-pix_fmt",
                "rgba64be",
                f"{cover_path}",
                "-y",
            ]
        )
        return f"Scraped metadata for {input_filename} (encode not implemented)"
    except (
        CalledProcessError,
        OSError,
        KeyError,
        IndexError,
        RuntimeError,
        ValueError,
    ) as exc:
        print(f"{input_filename} generated an exception: {exc}")
        return f"Failed Processing {input_filename}"


def encode_all_audio_files():
    file_list = glob("*.aax")
    executor = encoding_executor()
    futures = [
        executor.submit(audio_split_encode, file_name) for file_name in file_list
    ]
    print("Encoding", len(futures), "files.")
    wait_jobs(futures, label="Finished Job")
