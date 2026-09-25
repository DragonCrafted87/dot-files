# pylint: disable=invalid-name
"""Fetch astronomy stills and assign one per enabled Hyprland monitor."""

from __future__ import annotations

import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date
from datetime import datetime
from datetime import timezone
from pathlib import Path
from typing import Any

USER_AGENT = (
    "DragonCrafted87-dot-files/astro-wallpaper "
    "(+https://github.com/DragonCrafted87/dot-files)"
)
CACHE_DIR = (
    Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    / "hypr"
    / "astro-wallpapers"
)
STATE_DIR = (
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state")) / "hypr"
)
STATE_FILE = STATE_DIR / "astro-wallpaper.json"
HYPRPAPER_CONF = STATE_DIR / "hyprpaper.conf"
HYPRPAPER_LOG = STATE_DIR / "hyprpaper.log"
KEEP_DAYS = int(os.environ.get("ASTRO_WALLPAPER_KEEP_DAYS", "21"))
MIN_WIDTH = int(os.environ.get("ASTRO_WALLPAPER_MIN_WIDTH", "1600"))
CATEGORIES = [
    "Category:Nebulae",
    "Category:Emission nebulae",
    "Category:Planetary nebulae",
    "Category:Galaxies",
    "Category:Spiral galaxies",
    "Category:Planets of the Solar System",
    "Category:Comets",
    "Category:Open clusters",
    "Category:Globular clusters",
    "Category:Supernova remnants",
    "Category:Hubble Space Telescope images",
    "Category:James Webb Space Telescope images",
]


def _http_json(url: str, timeout: int = 30) -> dict[str, Any]:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
    return json.loads(raw.decode("utf-8"))


def _download(url: str, dest: Path, timeout: int = 60) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = resp.read()
    tmp = dest.with_suffix(dest.suffix + ".part")
    tmp.write_bytes(data)
    tmp.replace(dest)


def image_kind(path: Path) -> str | None:
    """Return jpeg/png/webp from magic bytes. hyprpaper dies on GIF named .jpg."""
    try:
        header = path.read_bytes()[:16]
    except OSError:
        return None
    if header.startswith(b"\xff\xd8\xff"):
        return "jpeg"
    if header.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if header.startswith(b"RIFF") and header[8:12] == b"WEBP":
        return "webp"
    return None


def image_is_supported(path: Path) -> bool:
    return image_kind(path) is not None


def _enabled_monitors() -> list[str]:
    try:
        raw = subprocess.check_output(["hyprctl", "monitors", "-j"], text=True)
        data = json.loads(raw)
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
        return []
    names: list[str] = []
    for mon in data:
        if mon.get("disabled") is True:
            continue
        if int(mon.get("width") or 0) <= 0:
            continue
        name = str(mon.get("name") or "")
        if name:
            names.append(name)
    return names


def _wait_enabled_monitors(timeout: float = 5.0) -> list[str]:
    """Wait until hyprctl reports a stable non-empty enabled set."""
    deadline = time.monotonic() + timeout
    last: list[str] = []
    stable = 0
    names: list[str] = []
    while time.monotonic() < deadline:
        names = _enabled_monitors()
        if names and names == last:
            stable += 1
            if stable >= 2:
                return names
        else:
            stable = 0
            last = names
        time.sleep(0.25)
    return names or _enabled_monitors()


def _commons_candidates(category: str, limit: int = 40) -> list[dict[str, str]]:
    query = urllib.parse.urlencode(
        {
            "action": "query",
            "format": "json",
            "generator": "categorymembers",
            "gcmtitle": category,
            "gcmtype": "file",
            "gcmlimit": str(limit),
            "gcmnamespace": "6",
            "prop": "imageinfo",
            "iiprop": "url|size|mime",
            "iiurlwidth": "3840",
        }
    )
    url = f"https://commons.wikimedia.org/w/api.php?{query}"
    try:
        payload = _http_json(url)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
        return []
    pages = (payload.get("query") or {}).get("pages") or {}
    out: list[dict[str, str]] = []
    for page in pages.values():
        infos = page.get("imageinfo") or []
        if not infos:
            continue
        info = infos[0]
        mime = str(info.get("mime") or "")
        if mime not in {"image/jpeg", "image/png", "image/webp"}:
            continue
        width = int(info.get("thumbwidth") or info.get("width") or 0)
        if width < MIN_WIDTH:
            continue
        file_url = str(info.get("thumburl") or info.get("url") or "")
        if not file_url:
            continue
        title = str(page.get("title") or file_url)
        out.append({"url": file_url, "title": title, "source": category})
    return out


def _apod_candidates(count: int = 8) -> list[dict[str, str]]:
    key = os.environ.get("NASA_API_KEY", "DEMO_KEY")
    query = urllib.parse.urlencode({"api_key": key, "count": str(count)})
    url = f"https://api.nasa.gov/planetary/apod?{query}"
    try:
        payload = _http_json(url)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
        return []
    if isinstance(payload, dict):
        items = [payload]
    else:
        items = list(payload)
    out: list[dict[str, str]] = []
    for item in items:
        if item.get("media_type") != "image":
            continue
        file_url = str(item.get("hdurl") or item.get("url") or "")
        title = str(item.get("title") or "APOD")
        if file_url:
            out.append({"url": file_url, "title": title, "source": "apod"})
    return out


def _safe_name(text: str) -> str:
    keep = []
    for char in text.lower():
        if char.isalnum():
            keep.append(char)
        elif char in {"-", "_"}:
            keep.append(char)
        else:
            keep.append("-")
    name = re.sub(r"-+", "-", "".join(keep)).strip("-")
    name = re.sub(r"-(?:jpg|jpeg|png|webp)$", "", name)
    name = re.sub(r"^file-", "", name)
    return name[:80] or "astro"


def _ext_for(url: str) -> str:
    path = urllib.parse.urlparse(url).path.lower()
    for ext in (".jpg", ".jpeg", ".png", ".webp"):
        if path.endswith(ext):
            return ".jpg" if ext == ".jpeg" else ext
    return ".jpg"


def fetch_pool(needed: int) -> list[Path]:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    pool: list[dict[str, str]] = []
    cats = CATEGORIES[:]
    random.shuffle(cats)
    for category in cats:
        pool.extend(_commons_candidates(category))
        if len(pool) >= needed * 6:
            break
    pool.extend(_apod_candidates())
    random.shuffle(pool)
    saved: list[Path] = []
    seen: set[str] = set()
    stamp = date.today().isoformat()
    for item in pool:
        if len(saved) >= max(needed, 3):
            break
        url = item["url"]
        if url in seen:
            continue
        seen.add(url)
        dest = CACHE_DIR / f"{stamp}-{_safe_name(item['title'])}{_ext_for(url)}"
        if dest.exists() and dest.stat().st_size > 0:
            if image_is_supported(dest):
                saved.append(dest)
                continue
            dest.unlink(missing_ok=True)
        try:
            _download(url, dest)
        except (urllib.error.URLError, TimeoutError, OSError):
            if dest.exists():
                dest.unlink()
            continue
        if dest.exists() and dest.stat().st_size > 0 and image_is_supported(dest):
            saved.append(dest)
            continue
        if dest.exists():
            dest.unlink()
    return saved


def cached_images() -> list[Path]:
    if not CACHE_DIR.is_dir():
        return []
    files = [
        path
        for path in CACHE_DIR.iterdir()
        if path.is_file()
        and path.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}
        and image_is_supported(path)
    ]
    files.sort(key=lambda path: path.stat().st_mtime, reverse=True)
    return files


def prune_cache() -> None:
    cutoff = datetime.now(timezone.utc).timestamp() - KEEP_DAYS * 86400
    if not CACHE_DIR.is_dir():
        return
    for path in list(CACHE_DIR.iterdir()):
        if not path.is_file():
            continue
        if path.suffix.lower() not in {".jpg", ".jpeg", ".png", ".webp"}:
            continue
        if not image_is_supported(path) or path.stat().st_mtime < cutoff:
            path.unlink(missing_ok=True)


def write_hyprpaper_conf(mapping: dict[str, str]) -> None:
    """Classic hyprpaper keywords. OM's build rejects wallpaper { } blocks."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    lines = ["splash = false", "ipc = on"]
    seen: set[str] = set()
    for image in mapping.values():
        if image in seen:
            continue
        lines.append(f"preload = {image}")
        seen.add(image)
    for monitor, image in mapping.items():
        lines.append(f"wallpaper = {monitor},{image}")
    HYPRPAPER_CONF.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _hyprpaper_running() -> bool:
    result = subprocess.run(
        ["pgrep", "-x", "hyprpaper"], check=False, capture_output=True
    )
    return result.returncode == 0


def stop_hyprpaper() -> None:
    subprocess.run(["pkill", "-x", "hyprpaper"], check=False)
    for _ in range(20):
        if not _hyprpaper_running():
            return
        time.sleep(0.05)


def start_hyprpaper() -> bool:
    if shutil.which("hyprpaper") is None:
        print("astro-wallpaper: hyprpaper is not installed", file=sys.stderr)
        return False
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    if not HYPRPAPER_CONF.is_file():
        HYPRPAPER_CONF.write_text("splash = false\nipc = on\n", encoding="utf-8")
    with HYPRPAPER_LOG.open("ab") as log:
        log.write(b"\n--- start ---\n")
        subprocess.Popen(  # noqa: S603 pylint: disable=consider-using-with
            ["hyprpaper", "-c", str(HYPRPAPER_CONF)],
            stdout=log,
            stderr=log,
            start_new_session=True,
        )
    for _ in range(30):
        if _hyprpaper_running():
            time.sleep(0.2)
            return _hyprpaper_running()
        time.sleep(0.1)
    print(
        f"astro-wallpaper: hyprpaper failed to start; see {HYPRPAPER_LOG}",
        file=sys.stderr,
    )
    return False


def apply_images(images: list[Path], monitors: list[str]) -> dict[str, str]:
    if not images or not monitors:
        return {}
    mapping: dict[str, str] = {}
    for index, monitor in enumerate(monitors):
        mapping[monitor] = str(images[index % len(images)])
    write_hyprpaper_conf(mapping)
    STATE_FILE.write_text(
        json.dumps(
            {
                "date": date.today().isoformat(),
                "monitors": mapping,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    # Config already has preload + wallpaper. Restarting applies it.
    # hyprctl against the socket races the new process and is noise.
    stop_hyprpaper()
    start_hyprpaper()
    return mapping


def cmd_fetch() -> list[Path]:
    monitors = _enabled_monitors() or ["DP-2", "DP-3", "HDMI-A-1"]
    images = fetch_pool(len(monitors))
    prune_cache()
    if not images:
        images = cached_images()
    return images


def cmd_apply(force_fetch: bool) -> int:
    prune_cache()
    monitors = _wait_enabled_monitors()
    today = date.today().isoformat()
    state: dict[str, Any] = {}
    if STATE_FILE.is_file():
        try:
            state = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            state = {}
    images = cached_images()
    if force_fetch or not images or state.get("date") != today:
        images = cmd_fetch() or images
    if not images:
        print("astro-wallpaper: no images in cache", file=sys.stderr)
        return 1
    if not monitors:
        print("astro-wallpaper: no enabled monitors (cached only)")
        return 0
    mapping = apply_images(images, monitors)
    for monitor, image in mapping.items():
        print(f"{monitor}: {image}")
    return 0


def cmd_status() -> int:
    print(f"cache: {CACHE_DIR}")
    print(f"conf:  {HYPRPAPER_CONF}")
    print(f"hyprpaper: {'running' if _hyprpaper_running() else 'not running'}")
    print(f"hyprpaper bin: {shutil.which('hyprpaper') or 'missing'}")
    if STATE_FILE.is_file():
        print(STATE_FILE.read_text(encoding="utf-8").rstrip())
    else:
        print("state: none")
    monitors = _enabled_monitors()
    print("monitors: " + (", ".join(monitors) if monitors else "none"))
    print(f"cached files: {len(cached_images())}")
    return 0


def cmd_selftest() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="astro-wallpaper-selftest-"))
    try:
        gif = tmp / "virgo.jpg"
        gif.write_bytes(b"GIF87a" + b"\x00" * 16)
        jpeg = tmp / "ok.jpg"
        jpeg.write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 16)
        png = tmp / "ok.png"
        png.write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00" * 8)
        if image_kind(gif) is not None:
            print("selftest: GIF named .jpg was accepted", file=sys.stderr)
            return 1
        if image_kind(jpeg) != "jpeg" or image_kind(png) != "png":
            print("selftest: jpeg/png magic failed", file=sys.stderr)
            return 1
        print("selftest ok")
        return 0
    finally:
        for path in tmp.iterdir():
            path.unlink()
        tmp.rmdir()


def usage() -> None:
    print("Usage: astro-wallpaper.py [apply|refresh|status|help]")


def main() -> int:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "apply"
    if cmd in {"apply"}:
        return cmd_apply(force_fetch=False)
    if cmd in {"refresh", "fetch", "next"}:
        return cmd_apply(force_fetch=True)
    if cmd == "status":
        return cmd_status()
    if cmd == "selftest":
        return cmd_selftest()
    if cmd in {"-h", "--help", "help"}:
        usage()
        return 0
    usage()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
