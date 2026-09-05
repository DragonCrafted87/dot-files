# -*- coding: utf-8 -*-

import io
from argparse import ArgumentParser
from glob import glob
from json import loads as json_loads
from operator import itemgetter
from os import makedirs
from os import remove as delete_file
from os.path import dirname
from pathlib import PurePath
from pprint import pprint
from re import search
from sys import exit as sys_exit
from urllib.parse import quote
from zipfile import ZipFile

from dateutil.parser import parse as parse_date  # pylint: disable=import-error
from requests import get as http_get  # pylint: disable=import-error

DEBUG = True


def file_download(url, minecraft_folder):
    path, url = url
    file_stream = http_get(url, stream=True)
    mods_folder = f"{minecraft_folder}/mods"

    mod_name = path[0 : search(r"\d", path).start() - 1]
    old_mod_prefix = str(PurePath(mods_folder, mod_name))
    mod_full_path = str(PurePath(mods_folder, path))

    if DEBUG:
        pprint(f"Removing old version of: {old_mod_prefix}")
    old_mod_files = glob(f"{old_mod_prefix}*")
    for old_file in old_mod_files:
        try:
            delete_file(old_file)
        except OSError:
            pass

    if DEBUG:
        pprint(f"Saving updated mod: {mod_full_path}")
    with open(mod_full_path, "wb") as new_file:
        new_file.write(file_stream.content)


def mr_pack_download(url, minecraft_folder):
    path, url = url
    file_stream = http_get(url, stream=True)

    with ZipFile(io.BytesIO(file_stream.content)) as thezip:
        for zipinfo in thezip.infolist():
            if zipinfo.filename == "modrinth.index.json":
                with thezip.open(zipinfo) as thefile:
                    mod_list = json_loads(thefile.read())
                    for mod_data in mod_list["files"]:
                        path = mod_data["path"]
                        if path.startswith("mods/"):
                            file_download(
                                (path.removeprefix("mods/"), mod_data["downloads"][0]),
                                minecraft_folder,
                            )
            elif not zipinfo.is_dir() and zipinfo.filename.startswith("overrides/"):
                if DEBUG:
                    pprint(zipinfo.filename)

                save_path = str(
                    PurePath(
                        minecraft_folder, zipinfo.filename.removeprefix("overrides/")
                    )
                )
                makedirs(dirname(save_path), exist_ok=True)

                with thezip.open(zipinfo.filename) as extracted_file:
                    with open(save_path, "wb") as new_file:
                        new_file.write(extracted_file.read())
        for zipinfo in thezip.infolist():
            if not zipinfo.is_dir() and zipinfo.filename.startswith(
                "client-overrides/"
            ):
                if DEBUG:
                    pprint(zipinfo.filename)

                save_path = str(
                    PurePath(
                        minecraft_folder,
                        zipinfo.filename.removeprefix("client-overrides/"),
                    )
                )
                makedirs(dirname(save_path), exist_ok=True)

                with thezip.open(zipinfo.filename) as extracted_file:
                    with open(save_path, "wb") as new_file:
                        new_file.write(extracted_file.read())


def curseforge_parse(api_data, minecraft_version):
    if (
        minecraft_version in api_data["download"]["versions"]
        and "Fabric" in api_data["download"]["versions"]
    ):
        base_id = api_data["download"]["url"][
            api_data["download"]["url"].rfind("/") + 1 :
        ]
        url = (
            "https://media.forgecdn.net/files/"
            + str(int(base_id[0:4]))
            + "/"
            + str(int(base_id[4:7]))
            + "/"
            + quote(api_data["download"]["name"])
        )
        return (api_data["download"]["name"], url)

    selected_item = None
    mod_upload = parse_date("2000-01-01T00:00:00.000Z")

    for item in api_data["files"]:
        new_mod_upload = parse_date(item["uploaded_at"])

        if (
            minecraft_version in item["versions"]
            and "Fabric" in item["versions"]
            and mod_upload < new_mod_upload
        ):
            mod_upload = new_mod_upload
            selected_item = item

    if selected_item:
        base_id = selected_item["url"][selected_item["url"].rfind("/") + 1 :]
        url = (
            "https://media.forgecdn.net/files/"
            + str(int(base_id[0:4]))
            + "/"
            + str(int(base_id[4:7]))
            + "/"
            + quote(selected_item["name"])
        )
        return (selected_item["name"], url)
    return None


def github_parse(api_data, minecraft_version):
    for releases in api_data:
        if not bool(
            releases.get("prerelease", True)
        ) and minecraft_version in releases.get("name").split(" "):
            for assets in releases["assets"]:
                link = assets.get("browser_download_url")
                if (
                    link is not None
                    and link.endswith("jar")
                    and minecraft_version in link
                ):
                    return (link[link.rfind("/") + 1 :], link)

    for releases in api_data:
        if not bool(releases.get("prerelease", True)):
            for assets in releases["assets"]:
                link = assets.get("browser_download_url")
                if (
                    link is not None
                    and link.endswith("jar")
                    and minecraft_version in link
                ):
                    return (link[link.rfind("/") + 1 :], link)

    return None


# https://docs.modrinth.com/api-spec/
def modrinth_parse(url, minecraft_version, secondary_version):
    query_parameters = {}
    query_parameters["loaders"] = '["fabric"]'
    query_parameters["game_versions"] = f'["{minecraft_version}"]'

    api_data = http_get(url, params=query_parameters)
    if api_data.status_code == 200:
        version_list = api_data.json()

        if len(version_list) == 0:
            query_parameters["game_versions"] = f'["{secondary_version}"]'
            api_data = http_get(url, params=query_parameters)

            if api_data.status_code != 200:
                return None

        if len(version_list) != 0:
            version = sorted(
                version_list, key=itemgetter("date_published"), reverse=True
            )[0]

            if DEBUG:
                pprint(version)

            files = version["files"]
            for file in files:
                if file["primary"]:
                    return (file["filename"], file["url"])

            return (files[0]["filename"], files[0]["url"])
    return None


def parse_mod_list(mod_list, minecraft_version, secondary_version):
    pprint("Parsing Mod List")
    download_list = []
    for url in mod_list:
        if "modrinth" in url:
            download_link = modrinth_parse(url, minecraft_version, secondary_version)
        else:
            for _ in range(5):
                api_data = http_get(url)
                if api_data.status_code == 200:
                    break

            if api_data.status_code != 200:
                pprint(f"Failed to get data for {url}")
                continue

            if DEBUG:
                pprint(f"Getting data for {url}")
            if "github" in url:
                parse_function = github_parse
            elif "cfwidget" in url:
                parse_function = curseforge_parse
            else:
                continue

            download_link = parse_function(api_data.json(), minecraft_version)
            if download_link is None and secondary_version is not None:
                download_link = parse_function(api_data.json(), secondary_version)

        if download_link is not None:
            download_list.append(download_link)

    return download_list


def main():
    argument_parser = ArgumentParser()
    argument_parser.add_argument("mod_list_path")
    argument_parser.add_argument("minecraft_folder")
    argument_parser.add_argument("mc_version")

    args = argument_parser.parse_args()

    if args.mod_list_path is None:
        pprint("Mod List Not Found")
        sys_exit()

    if args.mc_version is None:
        pprint("Minecraft Version Not Found")
        sys_exit()

    with open(f"{args.mod_list_path}", "r", encoding="utf8") as mod_list_file:
        mod_list = [line.strip() for line in mod_list_file.readlines()]

    mod_list = list(filter(lambda x: x, mod_list))
    mod_list = list(filter(lambda x: not x.startswith("#"), mod_list))

    minecraft_version = args.mc_version
    secondary_version = None

    if minecraft_version.count(".") == 2:
        secondary_version = minecraft_version[: minecraft_version.rfind(".")]

    pprint(f"Getting Mods for MineCraft Version {minecraft_version}")

    download_list = parse_mod_list(mod_list, minecraft_version, secondary_version)

    mods_folder = f"{args.minecraft_folder}/mods"
    makedirs(mods_folder, exist_ok=True)

    pprint("Downloading Mods")
    for download_link in download_list:
        if download_link[0].endswith("mrpack"):
            mr_pack_download(download_link, args.minecraft_folder)
        else:
            file_download(download_link, args.minecraft_folder)

    pprint("All Installed Mods")
    pprint(sorted(glob(f"{str(PurePath(mods_folder, '*'))}")))


if __name__ == "__main__":
    main()
