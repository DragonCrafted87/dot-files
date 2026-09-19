#!/usr/bin/env python3
# pylint: disable=invalid-name
"""Strip installed rpms toward the ISO baseline minus iso-strip.list."""

from __future__ import annotations

import fnmatch
import os
import shutil
import subprocess
import sys
from pathlib import Path

SETUP_DIR = Path(__file__).resolve().parent.parent
FILES = SETUP_DIR / "files"
PACKAGES = FILES / "packages"

ALWAYS_KEEP_PREFIXES = (
    "kernel",
    "grub2",
    "systemd",
    "glibc",
    "dnf",
    "rpm-",
    "basesystem",
)
ALWAYS_KEEP_NAMES = {"filesystem", "setup", "bash", "sudo", "rpm"}


def log(msg: str) -> None:
    print(f"==> {msg}")


def warn(msg: str) -> None:
    print(f"warning: {msg}", file=sys.stderr)


def die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


def read_names(path: Path) -> list[str]:
    names: list[str] = []
    if not path.is_file():
        return names
    text = path.read_text(encoding="utf-8", errors="replace")
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip().strip("\ufeff")
        if line:
            names.append(line)
    return names


def first_existing(*candidates: Path) -> Path | None:
    for path in candidates:
        if path.is_file():
            return path
    return None


def matches_any(name: str, patterns: list[str]) -> bool:
    for pat in patterns:
        if not pat or pat == "*":
            continue
        if fnmatch.fnmatchcase(name, pat):
            return True
    return False


def run_out(cmd: list[str]) -> str:
    result = subprocess.run(
        cmd, check=False, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True
    )
    return result.stdout


def installed_rpms() -> list[str]:
    text = run_out(["rpm", "-qa", "--qf", "%{name}\n"])
    return sorted({line.strip() for line in text.splitlines() if line.strip()})


def installed_flatpaks() -> list[str]:
    if not shutil.which("flatpak"):
        return []
    text = run_out(["flatpak", "list", "--app", "--columns=application"])
    names = []
    for line in text.splitlines():
        name = line.strip()
        if name and name != "Application":
            names.append(name)
    return sorted(set(names))


def require_reset_session() -> None:
    if os.environ.get("SSH_CONNECTION") or os.environ.get("SSH_TTY"):
        log("reset session: ssh")
        return
    tty = Path("/proc/self/fd/0").resolve().name
    try:
        tty_name = os.ttyname(0)
    except OSError:
        tty_name = tty
    if tty_name.startswith("/dev/tty") and tty_name[8:].isdigit():
        log(f"reset session: {tty_name}")
        return
    reasons = []
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        reasons.append("HYPRLAND_INSTANCE_SIGNATURE is set")
    if os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY"):
        reasons.append("graphical display is set")
    session = os.environ.get("XDG_SESSION_TYPE", "")
    if session in {"wayland", "x11"}:
        reasons.append(f"XDG_SESSION_TYPE={session}")
    extra = f" ({', '.join(reasons)})" if reasons else ""
    die(
        "reset must run from a real VT (Ctrl+Alt+F3) or SSH, "
        f"not under Ly/Hyprland/Plasma{extra}"
    )


def main() -> int:
    dry = os.environ.get("DOTFILES_DRY_RUN", "0") == "1"
    force = os.environ.get("RESET_CONFIRM", "") == "yes"

    require_reset_session()

    iso_file = first_existing(
        PACKAGES / "iso-installed.txt",
        PACKAGES / "iso-installed.list",
        FILES / "iso-installed.txt",
    )
    strip_file = first_existing(PACKAGES / "iso-strip.list")
    never_file = first_existing(PACKAGES / "never-remove.list")

    if iso_file is None:
        die(
            "missing ISO package list; looked in "
            f"{PACKAGES / 'iso-installed.txt'} and {FILES / 'iso-installed.txt'}\n"
            "harvest one with setup/utility/harvest-iso-packages.sh --iso FILE "
            f"-o {PACKAGES / 'iso-installed.txt'}"
        )

    iso_names = read_names(iso_file)
    strip_patterns = read_names(strip_file) if strip_file else []
    never = read_names(never_file) if never_file else []

    stripped = [name for name in iso_names if matches_any(name, strip_patterns)]
    kept_iso = [name for name in iso_names if name not in stripped]
    keep = set(kept_iso) | set(never) | set(ALWAYS_KEEP_NAMES)

    log(f"ISO list {iso_file} ({len(iso_names)} names)")
    log(
        f"lists: iso={len(iso_names)} strip={len(strip_patterns)} "
        f"never-remove={len(never)}"
    )
    log(
        f"baseline: {len(keep)} names "
        f"(kept {len(kept_iso)} from ISO, stripped {len(stripped)}, plus never-remove)"
    )
    if len(keep) < 50:
        die(
            f"baseline is too small ({len(keep)}); "
            f"check {iso_file} and {never_file}"
        )

    to_remove: list[str] = []
    for pkg in installed_rpms():
        if pkg in keep:
            continue
        if any(pkg.startswith(prefix) for prefix in ALWAYS_KEEP_PREFIXES):
            continue
        to_remove.append(pkg)

    if not to_remove:
        log("already at baseline; nothing to remove")
    else:
        log(f"remove extras ({len(to_remove)}):")
        for pkg in to_remove:
            print(f"    {pkg}")
        if dry:
            print("dry-run: sudo dnf remove -y " + " ".join(to_remove))
        elif force:
            cmd = ["sudo", "dnf", "remove", "-y", *to_remove]
            log("dnf remove")
            raise SystemExit(subprocess.call(cmd))
        else:
            warn("not removing; re-run with --reset --force from a VT or SSH")

    fps = installed_flatpaks()
    if fps:
        log(f"remove all flatpaks ({len(fps)}); next role run reinstalls")
        for app in fps:
            print(f"    {app}")
        if dry:
            print("dry-run: flatpak uninstall -y --all")
        elif force:
            subprocess.call(["sudo", "flatpak", "uninstall", "-y", "--all"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
