"""Chapter-split to ntsc-dvd, author, and wrap an ISO."""

from concurrent.futures import ThreadPoolExecutor
from glob import glob
from os import makedirs
from shutil import rmtree as rmdir

from . import MAIN_WORKERS
from .pool import encoding_executor
from .pool import wait_jobs
from .process import run_process


def dvd_encode(input_filename, output_filename, folder_name, start_time, end_time):
    run_process(
        [
            "ffmpeg",
            "-i",
            input_filename,
            "-ss",
            start_time,
            "-to",
            end_time,
            "-target",
            "ntsc-dvd",
            f"{folder_name}/{output_filename}",
            "-y",
        ]
    )
    return output_filename


def dvd_get_chapter_timestamps(input_filename):
    process = run_process(
        [
            "ffprobe",
            "-i",
            input_filename,
            "-show_chapters",
            "-loglevel",
            "error",
        ]
    )
    chapter_breakpoints = [
        line.split("=")[1]
        for line in process.stdout.splitlines()
        if line.startswith("end_time")
    ]
    chapter_breakpoints.insert(0, "0.0")
    return chapter_breakpoints


def dvd_split_encode(input_filename, base_filename, folder_name):
    chapter_breakpoints = dvd_get_chapter_timestamps(input_filename)
    output_filename_list = []
    executor = encoding_executor()
    futures = []
    pad_count = len(str(len(chapter_breakpoints) - 1))
    for index in range(len(chapter_breakpoints) - 1):
        output_filename = f"{base_filename}_{str(index).rjust(pad_count, '0')}.mpg"
        output_filename_list.append(output_filename)
        futures.append(
            executor.submit(
                dvd_encode,
                input_filename,
                output_filename,
                folder_name,
                chapter_breakpoints[index],
                chapter_breakpoints[index + 1],
            )
        )
    print("Encoding", len(futures), "files.")
    wait_jobs(futures, label="Processed job")
    return output_filename_list


def dvd_author_disk(folder_name, filename_list):
    with open(f"{folder_name}/dvd.xml", "w", encoding="utf8") as dvd_author_commands:
        dvd_author_commands.write("<dvdauthor>")
        dvd_author_commands.write("   <vmgm>")
        dvd_author_commands.write('      <menus lang="en">')
        dvd_author_commands.write('         <video format="ntsc" />')
        dvd_author_commands.write("      </menus>")
        dvd_author_commands.write("   </vmgm>")
        dvd_author_commands.write("    <titleset>")
        dvd_author_commands.write("        <titles>")
        dvd_author_commands.write("            <pgc>")
        for file_name in filename_list:
            dvd_author_commands.write(
                f'                <vob file="{folder_name}/{file_name}" />'
            )
        dvd_author_commands.write("            </pgc>")
        dvd_author_commands.write("        </titles>")
        dvd_author_commands.write("    </titleset>")
        dvd_author_commands.write("</dvdauthor>")

    run_process(
        ["dvdauthor", "-x", f"{folder_name}/dvd.xml", "-o", f"{folder_name}/dvd"]
    )


def dvd_make_iso(base_filename, folder_name):
    iso_name = f"{base_filename}.iso"
    run_process(
        [
            "mkisofs",
            "-dvd-video",
            "-volid",
            base_filename,
            "-o",
            iso_name,
            f"{folder_name}/dvd",
        ]
    )
    return iso_name


def create_dvd(input_filename):
    base_filename = input_filename.rsplit(".", 1)[0]
    folder_name = base_filename + ".iso.temp"
    makedirs(f"{folder_name}/dvd", exist_ok=True)
    file_name_list = dvd_split_encode(input_filename, base_filename, folder_name)
    dvd_author_disk(folder_name, file_name_list)
    iso_name = dvd_make_iso(base_filename, folder_name)
    rmdir(folder_name)
    return iso_name


def create_all_dvds():
    file_list = glob("*.mkv")
    with ThreadPoolExecutor(max_workers=MAIN_WORKERS) as executor:
        futures = [executor.submit(create_dvd, file_name) for file_name in file_list]
        print("Creating", len(futures), "dvds.")
        wait_jobs(futures, label="Processed job")
