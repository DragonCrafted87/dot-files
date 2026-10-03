# pylint: disable=invalid-name
"""Fetch astronomy stills and assign one per enabled Hyprland monitor.

Stills whose border is near white are dropped.
"""

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
HYPRPAPER_UNIT = "hyprpaper.service"
KEEP_DAYS = int(os.environ.get("ASTRO_WALLPAPER_KEEP_DAYS", "21"))
MIN_WIDTH = int(os.environ.get("ASTRO_WALLPAPER_MIN_WIDTH", "1600"))
MAX_BORDER_LUMA = int(os.environ.get("ASTRO_WALLPAPER_MAX_BORDER", "200"))
_SAMPLE_WIDTH = 80
_SAMPLE_HEIGHT = 45
_BRIGHTNESS_CACHE = "brightness.json"
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


def border_band(width: int, height: int) -> int:
    """Width of the frame treated as the field behind the subject."""
    return max(1, min(width, height) // 12)


def border_median_luma(rgb: bytes, width: int, height: int) -> float | None:
    """Median Rec.709 luminance of the border, or None when the buffer is short."""
    if width < 1 or height < 1 or len(rgb) < width * height * 3:
        return None
    band = border_band(width, height)
    values: list[float] = []
    for y_pos in range(height):
        row = y_pos * width
        for x_pos in range(width):
            if band <= x_pos < width - band and band <= y_pos < height - band:
                continue
            offset = (row + x_pos) * 3
            red = rgb[offset]
            green = rgb[offset + 1]
            blue = rgb[offset + 2]
            values.append((0.2126 * red) + (0.7152 * green) + (0.0722 * blue))
    if not values:
        return None
    values.sort()
    mid = len(values) // 2
    if len(values) % 2 == 1:
        return values[mid]
    return (values[mid - 1] + values[mid]) / 2.0


def background_too_bright(median: float | None, limit: float | None = None) -> bool:
    """True when the typical border pixel is near white.

    A bright subject on a dark field stays. Charts and paper scans go.
    """
    if median is None:
        return False
    if limit is None:
        limit = MAX_BORDER_LUMA
    return median >= limit


def _brightness_cache_path() -> Path:
    return CACHE_DIR / _BRIGHTNESS_CACHE


def _load_brightness_cache() -> dict[str, Any]:
    path = _brightness_cache_path()
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    if not isinstance(data, dict):
        return {}
    return data


def _save_brightness_cache(data: dict[str, Any]) -> None:
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        path = _brightness_cache_path()
        tmp = path.with_suffix(".part")
        tmp.write_text(json.dumps(data) + "\n", encoding="utf-8")
        tmp.replace(path)
    except OSError:
        pass


def _cache_entry_matches(entry: object, size: int, mtime_ns: int) -> bool:
    if not isinstance(entry, dict):
        return False
    median = entry.get("median")
    if isinstance(median, bool) or not isinstance(median, (int, float)):
        return False
    return entry.get("size") == size and entry.get("mtime_ns") == mtime_ns


def _cached_median(path: Path) -> float | None:
    if path.parent.resolve() != CACHE_DIR.resolve():
        return None
    try:
        stat = path.stat()
    except OSError:
        return None
    entry = _load_brightness_cache().get(path.name)
    if not isinstance(entry, dict):
        return None
    if not _cache_entry_matches(entry, stat.st_size, stat.st_mtime_ns):
        return None
    return float(entry["median"])


def _store_median(path: Path, median: float) -> None:
    if path.parent.resolve() != CACHE_DIR.resolve():
        return
    try:
        stat = path.stat()
    except OSError:
        return
    data = _load_brightness_cache()
    data[path.name] = {
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
        "median": median,
    }
    _save_brightness_cache(data)


def _forget_missing_brightness() -> None:
    data = _load_brightness_cache()
    if not data:
        return
    kept: dict[str, Any] = {}
    for name, entry in data.items():
        path = CACHE_DIR / name
        if not path.is_file():
            continue
        try:
            stat = path.stat()
        except OSError:
            continue
        if _cache_entry_matches(entry, stat.st_size, stat.st_mtime_ns):
            kept[name] = entry
    if len(kept) != len(data):
        _save_brightness_cache(kept)


def _sample_rgb(path: Path) -> tuple[bytes, int, int] | None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return None
    proc = subprocess.run(
        [
            ffmpeg,
            "-v",
            "error",
            "-i",
            str(path),
            "-vf",
            f"scale={_SAMPLE_WIDTH}:{_SAMPLE_HEIGHT}",
            "-frames:v",
            "1",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-",
        ],
        check=False,
        capture_output=True,
    )
    expected = _SAMPLE_WIDTH * _SAMPLE_HEIGHT * 3
    if proc.returncode != 0 or len(proc.stdout) < expected:
        return None
    return proc.stdout[:expected], _SAMPLE_WIDTH, _SAMPLE_HEIGHT


def image_border_median(path: Path) -> float | None:
    cached = _cached_median(path)
    if cached is not None:
        return cached
    sample = _sample_rgb(path)
    if sample is None:
        return None
    rgb, width, height = sample
    median = border_median_luma(rgb, width, height)
    if median is None:
        return None
    _store_median(path, median)
    return median


def background_is_too_bright(path: Path) -> bool:
    return background_too_bright(image_border_median(path))


def _reject_bright(path: Path) -> bool:
    """Delete a near-white field. Return True when the file was removed."""
    if not background_is_too_bright(path):
        return False
    print(f"astro-wallpaper: drop bright background: {path.name}", file=sys.stderr)
    path.unlink(missing_ok=True)
    return True


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
        if dest.exists() and dest.stat().st_size > 0 and image_is_supported(dest):
            if _reject_bright(dest):
                continue
            saved.append(dest)
            continue
        if dest.exists():
            dest.unlink(missing_ok=True)
        try:
            _download(url, dest)
        except (urllib.error.URLError, TimeoutError, OSError):
            if dest.exists():
                dest.unlink()
            continue
        if not (dest.exists() and dest.stat().st_size > 0 and image_is_supported(dest)):
            if dest.exists():
                dest.unlink()
            continue
        if _reject_bright(dest):
            continue
        saved.append(dest)
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
        and not background_is_too_bright(path)
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
            continue
        _reject_bright(path)
    _forget_missing_brightness()


def _version_uses_blocks(text: str) -> bool | None:
    """0.8+ wants wallpaper { } blocks. 0.7 rejects them and wants preload lines."""
    match = re.search(r"(\d+)\.(\d+)", text)
    if match is None:
        return None
    return (int(match.group(1)), int(match.group(2))) >= (0, 8)


def _hyprpaper_uses_blocks() -> bool:
    path = shutil.which("hyprpaper") or ""
    if not path:
        return False
    result = subprocess.run(
        [path, "--version"],
        check=False,
        capture_output=True,
        text=True,
    )
    decision = _version_uses_blocks(f"{result.stdout}\n{result.stderr}")
    if decision is not None:
        return decision
    return path.startswith(("/opt/hyprland/", "/usr/local/"))


def write_hyprpaper_conf(mapping: dict[str, str]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    lines = ["splash = false", "ipc = on"]
    if _hyprpaper_uses_blocks():
        for monitor, image in mapping.items():
            lines.extend(
                [
                    "wallpaper {",
                    f"    monitor = {monitor}",
                    f"    path = {image}",
                    "    fit_mode = cover",
                    "}",
                ]
            )
    else:
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


def start_hyprpaper() -> bool:
    """Restart hyprpaper.service so the daemon runs in its own cgroup."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    if not HYPRPAPER_CONF.is_file():
        HYPRPAPER_CONF.write_text("splash = false\nipc = on\n", encoding="utf-8")
    result = subprocess.run(
        ["systemctl", "--user", "restart", HYPRPAPER_UNIT],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        print(
            f"astro-wallpaper: systemctl restart {HYPRPAPER_UNIT} failed: {detail}",
            file=sys.stderr,
        )
        return False
    for _ in range(30):
        if _hyprpaper_running():
            return True
        time.sleep(0.1)
    print(
        f"astro-wallpaper: {HYPRPAPER_UNIT} did not stay up",
        file=sys.stderr,
    )
    return False


def apply_images(images: list[Path], monitors: list[str]) -> dict[str, str]:
    if not images or not monitors:
        return {}
    mapping: dict[str, str] = {}
    for index, monitor in enumerate(monitors):
        mapping[monitor] = str(images[index % len(images)])
    previous = ""
    if HYPRPAPER_CONF.is_file():
        previous = HYPRPAPER_CONF.read_text(encoding="utf-8")
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
    # Same conf and a live daemon: leave it. Idle wake calls apply after
    # the 06:30 refresh may have omitted a disabled output.
    current = HYPRPAPER_CONF.read_text(encoding="utf-8")
    if current == previous and _hyprpaper_running():
        return mapping
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
    state = subprocess.run(
        ["systemctl", "--user", "is-active", HYPRPAPER_UNIT],
        check=False,
        capture_output=True,
        text=True,
    )
    print(f"hyprpaper unit: {(state.stdout or state.stderr).strip() or 'unknown'}")
    if STATE_FILE.is_file():
        print(STATE_FILE.read_text(encoding="utf-8").rstrip())
    else:
        print("state: none")
    monitors = _enabled_monitors()
    print("monitors: " + (", ".join(monitors) if monitors else "none"))
    print(f"cached files: {len(cached_images())}")
    return 0


def _rgb_frame(
    width: int,
    height: int,
    center: tuple[int, int, int],
    border: tuple[int, int, int] | None = None,
) -> bytes:
    band = border_band(width, height)
    out = bytearray(width * height * 3)
    for y_pos in range(height):
        for x_pos in range(width):
            pixel = center
            if border is not None and (
                x_pos < band
                or x_pos >= width - band
                or y_pos < band
                or y_pos >= height - band
            ):
                pixel = border
            offset = ((y_pos * width) + x_pos) * 3
            out[offset] = pixel[0]
            out[offset + 1] = pixel[1]
            out[offset + 2] = pixel[2]
    return bytes(out)


def _selftest_border_rule() -> str | None:
    failures: list[str] = []
    dark_field = border_median_luma(_rgb_frame(8, 8, (255, 255, 255), (0, 0, 0)), 8, 8)
    if dark_field is None or background_too_bright(dark_field):
        failures.append("selftest: bright center on a dark border was rejected")
    paper = border_median_luma(_rgb_frame(8, 8, (0, 0, 0), (255, 255, 255)), 8, 8)
    if not background_too_bright(paper):
        failures.append("selftest: white border around a dark center was kept")
    if background_too_bright(None):
        failures.append("selftest: unreadable frame was rejected")
    if not background_too_bright(200):
        failures.append("selftest: border median 200 was kept")
    if background_too_bright(199):
        failures.append("selftest: border median 199 was rejected")
    if not background_too_bright(199, limit=199):
        failures.append("selftest: limit 199 should reject median 199")
    if background_too_bright(200, limit=201):
        failures.append("selftest: limit 201 should keep median 200")
    if border_median_luma(b"", 4, 4) is not None:
        failures.append("selftest: short buffer produced a median")
    if failures:
        return "\n".join(failures)
    return None


def _lavfi_still(dest: Path, color: str) -> bool:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return False
    result = subprocess.run(
        [
            ffmpeg,
            "-v",
            "error",
            "-y",
            "-f",
            "lavfi",
            "-i",
            f"color=c={color}:s=64x64",
            "-frames:v",
            "1",
            str(dest),
        ],
        check=False,
        capture_output=True,
    )
    return result.returncode == 0 and dest.is_file() and dest.stat().st_size > 0


def _selftest_magic(tmp: Path) -> str | None:
    gif = tmp / "virgo.jpg"
    gif.write_bytes(b"GIF87a" + b"\x00" * 16)
    jpeg = tmp / "ok.jpg"
    jpeg.write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 16)
    png = tmp / "ok.png"
    png.write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00" * 8)
    if image_kind(gif) is not None:
        return "selftest: GIF named .jpg was accepted"
    if image_kind(jpeg) != "jpeg" or image_kind(png) != "png":
        return "selftest: jpeg/png magic failed"
    if _version_uses_blocks("hyprpaper v0.8.4") is not True:
        return "selftest: 0.8 should use blocks"
    if _version_uses_blocks("hyprpaper 0.7.4") is not False:
        return "selftest: 0.7 should use preload lines"
    if _version_uses_blocks("no version here") is not None:
        return "selftest: missing version should be unknown"
    return None


def _selftest_decoded(white: Path, black: Path) -> str | None:
    if not background_is_too_bright(white):
        return "selftest: white png border was kept"
    if background_is_too_bright(black):
        return "selftest: black jpeg border was rejected"
    return None


def _selftest_brightness_cache(white: Path) -> str | None:
    cache_path = _brightness_cache_path()
    if not cache_path.is_file():
        return "selftest: brightness cache was not written"
    data = json.loads(cache_path.read_text(encoding="utf-8"))
    data["white.png"]["median"] = 0
    cache_path.write_text(json.dumps(data), encoding="utf-8")
    if background_is_too_bright(white):
        return "selftest: cached median was ignored"
    data["white.png"]["mtime_ns"] = 0
    cache_path.write_text(json.dumps(data), encoding="utf-8")
    if not background_is_too_bright(white):
        return "selftest: stale brightness cache was reused"
    return None


def _selftest_ffmpeg_sample() -> str | None:
    if shutil.which("ffmpeg") is None:
        print("selftest: ffmpeg border sample skipped")
        return None
    white = CACHE_DIR / "white.png"
    black = CACHE_DIR / "black.jpg"
    if not _lavfi_still(white, "white") or not _lavfi_still(black, "black"):
        return "selftest: ffmpeg could not write sample stills"
    decoded = _selftest_decoded(white, black)
    if decoded:
        return decoded
    return _selftest_brightness_cache(white)


def _selftest_in_cache(tmp: Path) -> str | None:
    # pylint: disable=global-statement
    global CACHE_DIR
    original_cache = CACHE_DIR
    try:
        CACHE_DIR = tmp / "cache"
        CACHE_DIR.mkdir()
        return _selftest_ffmpeg_sample()
    finally:
        CACHE_DIR = original_cache


def cmd_selftest() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="astro-wallpaper-selftest-"))
    try:
        error = (
            _selftest_magic(tmp) or _selftest_border_rule() or _selftest_in_cache(tmp)
        )
        if error:
            print(error, file=sys.stderr)
            return 1
        print("selftest ok")
        return 0
    finally:
        for path in sorted(tmp.rglob("*"), reverse=True):
            if path.is_dir():
                path.rmdir()
            else:
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
