"""Plan and apply Jellyfin library moves from a small job file."""

from os import environ
from os.path import exists
from pathlib import Path
from shutil import move

DEFAULT_MEDIA_ROOT = environ.get(
    "JELLYFIN_MEDIA_ROOT", "/home/dragon/Network/Storage/Media"
)
DEFAULT_JOB_NAME = "jellyfin.job"
VIDEO_SUFFIXES = {".mkv", ".mp4", ".avi", ".webm", ".m4v"}


def _source_dir(search_dir):
    if search_dir not in (None, "", "."):
        return Path(search_dir)
    cropped = Path("cropped")
    if cropped.is_dir():
        return cropped
    return Path(".")


def list_videos(search_dir=None):
    root = _source_dir(search_dir)
    files = [
        path
        for path in sorted(root.iterdir())
        if path.is_file() and path.suffix.lower() in VIDEO_SUFFIXES
    ]
    return root, files


def _with_suffix(name):
    path = Path(name)
    if path.suffix.lower() in VIDEO_SUFFIXES:
        return path.name
    return f"{path.name}.mkv"


def _parse_mapping(line):
    if "|" not in line:
        return _with_suffix(line.strip()), ""
    source, title = line.split("|", 1)
    return _with_suffix(source.strip()), title.strip()


def parse_job(text):
    job = {
        "kind": "",
        "root": "",
        "title": "",
        "collection": "",
        "feature": "",
        "feature_as": "",
        "extras": [],
        "seasons": {},
    }
    section = "meta"
    season = None
    episode = 1
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        lower = line.lower()
        if lower.startswith("kind:"):
            job["kind"] = line.split(":", 1)[1].strip().lower()
            section = "meta"
            continue
        if lower.startswith("root:"):
            job["root"] = line.split(":", 1)[1].strip()
            continue
        if lower.startswith("title:") or lower.startswith("show:"):
            job["title"] = line.split(":", 1)[1].strip()
            continue
        if lower.startswith("collection:"):
            job["collection"] = line.split(":", 1)[1].strip()
            continue
        if lower.startswith("feature:"):
            job["feature"] = _with_suffix(line.split(":", 1)[1].strip())
            section = "meta"
            continue
        if lower.startswith("feature-as:"):
            job["feature_as"] = line.split(":", 1)[1].strip()
            continue
        if lower == "extras:" or lower.startswith("extras:"):
            section = "extras"
            rest = line.split(":", 1)[1].strip()
            if rest:
                source, title = _parse_mapping(rest)
                job["extras"].append((source, title or Path(source).stem))
            continue
        if lower.startswith("season:"):
            season = int(line.split(":", 1)[1].strip())
            episode = 1
            job["seasons"].setdefault(season, [])
            section = "season"
            continue
        if lower.startswith("episode:"):
            episode = int(line.split(":", 1)[1].strip())
            continue
        if section == "extras":
            source, title = _parse_mapping(line)
            job["extras"].append((source, title or Path(source).stem))
            continue
        if section == "season":
            if season is None:
                raise ValueError("episode line before season:")
            source, title = _parse_mapping(line)
            job["seasons"][season].append((episode, source, title))
            episode += 1
            continue
        raise ValueError(f"unrecognized job line: {raw}")
    return job


def load_job(path):
    return parse_job(Path(path).read_text(encoding="utf-8"))


def folder_tag(job):
    title = job["title"]
    if not title:
        raise ValueError("job needs title: or show:")
    return title


def library_root(job):
    if job["root"]:
        return Path(job["root"])
    media = Path(DEFAULT_MEDIA_ROOT)
    if job["kind"] == "movie":
        return media / "movies"
    if job["kind"] == "tv":
        return media / "tv"
    raise ValueError("job kind must be movie or tv")


def planned_moves(job, search_dir=None):
    source_root = _source_dir(search_dir)
    dest_root = library_root(job)
    tag = folder_tag(job)
    moves = []
    if job["kind"] == "movie":
        if job["collection"]:
            movie_dir = dest_root / job["collection"] / tag
        else:
            movie_dir = dest_root / tag
        feature_name = job["feature_as"] or tag
        if job["feature"]:
            moves.append(
                (
                    source_root / job["feature"],
                    movie_dir / f"{feature_name}.mkv",
                )
            )
        for source, title in job["extras"]:
            extra_name = title if title.lower().endswith(".mkv") else f"{title}.mkv"
            moves.append((source_root / source, movie_dir / "extras" / extra_name))
        return moves
    if job["kind"] == "tv":
        show_dir = dest_root / tag
        for season, episodes in sorted(job["seasons"].items()):
            season_dir = show_dir / f"Season {season:02d}"
            for number, source, title in episodes:
                if not title:
                    raise ValueError(f"{source} is missing an episode title")
                dest_name = f"{tag} - s{season:02d}e{number:02d} - {title}.mkv"
                moves.append((source_root / source, season_dir / dest_name))
        return moves
    raise ValueError("job kind must be movie or tv")


def print_plan(moves):
    if not moves:
        print("no moves planned")
        return False
    missing = False
    for source, dest in moves:
        if source.exists():
            print(f"{source} -> {dest}")
        else:
            missing = True
            print(f"{source} -> {dest}  MISSING SOURCE")
    return not missing


def apply_moves(moves):
    for source, dest in moves:
        if not source.exists():
            raise FileNotFoundError(source)
        dest.parent.mkdir(parents=True, exist_ok=True)
        print(f"mv {source} -> {dest}")
        move(str(source), str(dest))


def confirm_and_apply(moves):
    ok = print_plan(moves)
    if not moves:
        return
    if not ok:
        print("abort: missing source files")
        return
    answer = input("Move these files? [y/N] ").strip().lower()
    if answer not in ("y", "yes"):
        print("cancelled")
        return
    apply_moves(moves)


def write_template(kind, search_dir=None, job_path=DEFAULT_JOB_NAME, title=""):
    source_root, files = list_videos(search_dir)
    if exists(job_path):
        raise FileExistsError(job_path)
    kind = kind.lower()
    media = Path(DEFAULT_MEDIA_ROOT)
    folder = "movies" if kind == "movie" else "tv"
    placeholder = "TITLE (YEAR) {imdb-tt... or tvdb-...}"
    lines = [
        f"kind: {kind}",
        f"root: {media / folder}",
        f"title: {title or placeholder}",
        "",
        f"# sources listed from {source_root.resolve()}",
    ]
    if kind == "movie":
        lines.append("# collection: Optional Franchise Folder")
        if files:
            lines.append(f"feature: {files[0].name}")
        else:
            lines.append("feature: FEATURE.mkv")
        lines.append("# feature-as: TITLE (YEAR) {imdb-tt...} - Extended Cut")
        lines.append("extras:")
        for path in files[1:]:
            lines.append(f"{path.stem} | ")
    else:
        lines.append("season: 1")
        lines.append("# episode: 1")
        if files:
            for path in files:
                lines.append(f"{path.stem} | ")
        else:
            lines.append("SOURCE | Episode Title")
    Path(job_path).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {job_path} ({len(files)} source files from {source_root})")
    return job_path
