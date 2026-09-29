#!/usr/bin/env python3
"""Jellyfin job names and skipped episodes."""

import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path

from ffmpeg_tools.jellyfin import folder_tag
from ffmpeg_tools.jellyfin import parse_job
from ffmpeg_tools.jellyfin import planned_moves
from ffmpeg_tools.jellyfin import print_plan


class JellyfinJobTests(unittest.TestCase):
    def test_year_and_id_compose_the_episode_filename(self):
        job = parse_job(
            "\n".join(
                [
                    "kind: tv",
                    "root: /library/tv",
                    "title: The Future is Wild",
                    "year: 2002",
                    "id: tvdb-79010",
                    "season: 1",
                    "wild-disc-1-01 | Welcome to the Future",
                ]
            )
        )
        tag = "The Future is Wild (2002) {tvdb-79010}"
        self.assertEqual(folder_tag(job), tag)
        moves = planned_moves(job, search_dir="cropped")
        self.assertEqual(
            moves,
            [
                (
                    Path("cropped/wild-disc-1-01.mkv"),
                    Path(f"/library/tv/{tag}")
                    / "Season 01"
                    / f"{tag} - s01e01 - Welcome to the Future.mkv",
                )
            ],
        )

    def test_full_title_line_is_the_tag(self):
        job = parse_job(
            "\n".join(
                [
                    "kind: tv",
                    "title: ReBoot (1994) {tvdb-73025}",
                    "season: 1",
                    "REBOOT | The Tearing",
                ]
            )
        )
        self.assertEqual(folder_tag(job), "ReBoot (1994) {tvdb-73025}")

    def test_bare_title_is_rejected(self):
        job = parse_job(
            "\n".join(
                [
                    "kind: tv",
                    "title: The Future is Wild",
                    "season: 1",
                    "wild | Welcome",
                ]
            )
        )
        with self.assertRaises(ValueError):
            folder_tag(job)

    def test_blank_source_skips_the_episode_and_keeps_the_number(self):
        job = parse_job(
            "\n".join(
                [
                    "kind: tv",
                    "root: /library/tv",
                    "title: The Future is Wild",
                    "year: 2002",
                    "id: {tvdb-79010}",
                    "season: 1",
                    "wild-disc-1-05 | The Vanished Sea",
                    " | Prairies of Amazonia",
                    "wild-disc-1-09 | Cold Kansas Desert",
                ]
            )
        )
        tag = "The Future is Wild (2002) {tvdb-79010}"
        show = Path(f"/library/tv/{tag}/Season 01")
        moves = planned_moves(job, search_dir="cropped")
        self.assertEqual(
            [dest.name for _source, dest in moves],
            [
                f"{tag} - s01e01 - The Vanished Sea.mkv",
                f"{tag} - s01e02 - Prairies of Amazonia.mkv",
                f"{tag} - s01e03 - Cold Kansas Desert.mkv",
            ],
        )
        self.assertIsNone(moves[1][0])
        self.assertEqual(moves[0][1].parent, show)
        self.assertEqual(moves[2][0], Path("cropped/wild-disc-1-09.mkv"))

    def test_plan_prints_a_skip_without_calling_it_missing(self):
        job = parse_job(
            "\n".join(
                [
                    "kind: tv",
                    "root: /library/tv",
                    "title: Show (2002) {tvdb-1}",
                    "season: 1",
                    " | Missing Episode",
                    "have | Present",
                ]
            )
        )
        moves = planned_moves(job, search_dir="rips")
        buffer = StringIO()
        with redirect_stdout(buffer):
            ok = print_plan(moves)
        text = buffer.getvalue()
        self.assertIn("skip", text)
        self.assertIn("s01e01", text)
        self.assertIn("MISSING SOURCE", text)
        self.assertFalse(ok)


if __name__ == "__main__":
    unittest.main()
