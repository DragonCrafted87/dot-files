"""Prefer the Jabra analog profile so the Speak 710 buttons change audible volume."""

import json
import subprocess
import sys


def pactl_json(command):
    try:
        raw = subprocess.check_output(["pactl", "--format=json", command], text=True)
        data = json.loads(raw)
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
        return []
    return data if isinstance(data, list) else []


def pick_profile(profiles):
    names = list(profiles)
    preferred = [
        "output:analog-stereo+input:mono-fallback",
        "output:analog-stereo+input:analog-stereo",
        "output:analog-stereo",
        "analog-stereo",
    ]
    for name in preferred:
        if name in profiles:
            return name
    for name in names:
        if "analog" in name and "output" in name:
            return name
    return None


def main():
    cards = pactl_json("list")
    if not cards:
        cards = pactl_json("list cards")
    changed = 0
    for card in cards:
        name = str(card.get("name", ""))
        desc = str(card.get("description") or card.get("properties", {}).get("device.description", ""))
        blob = f"{name} {desc}".lower()
        if "jabra" not in blob and "0b0e" not in blob:
            continue
        profiles = card.get("profiles") or {}
        if isinstance(profiles, dict):
            profile_names = profiles
        else:
            profile_names = {}
        target = pick_profile(profile_names)
        active = card.get("active_profile") or card.get("activeProfile")
        print(f"jabra_card={name} active={active} target={target}")
        if target and target != active:
            subprocess.check_call(["pactl", "set-card-profile", name, target])
            print(f"set-card-profile {name} {target}")
            changed += 1
    if not changed:
        print("jabra profile already analog or card missing")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
