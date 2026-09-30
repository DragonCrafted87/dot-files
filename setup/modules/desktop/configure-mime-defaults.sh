#!/usr/bin/env bash
# Give Dolphin / xdg-open a MIME map after plasma-workspace is removed.
# Hyprland env (XDG_CURRENT_DESKTOP=Hyprland:KDE) is the other half.
# That KDE tag also flips Dolphin 25.04 to single-click and binds
# double-click to "nothing", so this module pins SingleClick=false.
# Loose config/kdeglobals is applied here; link-user-config ignores files.
# Text and source files default to VS Code, not Kate.
# mimeapps.list names code.desktop; this module rewrites that to the
# desktop file that is actually installed (the distro package ships
# com.microsoft.VSCode.desktop). An unmanaged mimeapps.list keeps
# handlers whose desktop file exists. Missing handlers are added, and
# handlers that point at a desktop file that is gone are replaced.

set -euo pipefail
# shellcheck disable=SC1091
. "${REPO_ROOT:-$DOTFILES_ROOT}/setup/lib/lib.sh"

require_user

src="${SETUP_FILES_DIR}/mime/mimeapps.list"
dest="${CONFIG_TARGET_DIR}/mimeapps.list"
menu_src="${SETUP_FILES_DIR}/mime/applications.menu"
menu_dest="${CONFIG_TARGET_DIR}/menus/applications.menu"
svc_src="${SETUP_FILES_DIR}/mime/servicemenus"
svc_kf6="${DOTFILES_HOME}/.local/share/kio/servicemenus"
svc_kf5="${DOTFILES_HOME}/.local/share/kservices5/ServiceMenus"
mime_xml_src="${SETUP_FILES_DIR}/mime/code-workspace.xml"
mime_xml_dest="${DOTFILES_HOME}/.local/share/mime/packages/code-workspace.xml"
theme_src="${CONFIG_SOURCE_DIR}/kdeglobals"
theme_dest="${CONFIG_TARGET_DIR}/kdeglobals"

if [[ ! -f "$src" ]]; then
    die "missing ${src}"
fi

ensure_dir "${CONFIG_TARGET_DIR}"
ensure_dir "${CONFIG_TARGET_DIR}/menus"
ensure_dir "$svc_kf6"
ensure_dir "$svc_kf5"
ensure_dir "$(dirname "$mime_xml_dest")"

# Rewrite code.desktop, then install or merge.
# Prints "<action>\t<desktop-id>\t<found|missing>".
mime_result="$(
    DOTFILES_DRY_RUN="${DOTFILES_DRY_RUN:-0}" python3 - "$src" "$dest" "$DOTFILES_HOME" <<'PY'
import os
import sys
from pathlib import Path

src_path, dest_path, home = sys.argv[1:4]
dry_run = os.environ.get("DOTFILES_DRY_RUN") == "1"
token = "code.desktop"
candidates = (
    "com.microsoft.VSCode.desktop",
    "code.desktop",
    "code-oss.desktop",
    "vscodium.desktop",
    "codium.desktop",
)


def data_dirs():
    dirs = [Path(home) / ".local/share"]
    xdg = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    seen = set()
    ordered = []
    for part in [str(dirs[0]), *xdg.split(":")]:
        if not part or part in seen:
            continue
        seen.add(part)
        ordered.append(Path(part))
    return ordered


def desktop_exists(desktop_id):
    name = desktop_id.strip()
    if not name:
        return False
    for directory in data_dirs():
        if (directory / "applications" / name).is_file():
            return True
    return False


def vscode_desktop_id():
    for candidate in candidates:
        if desktop_exists(candidate):
            return candidate, "found"
    return token, "missing"


def substitute(text, desktop_id):
    lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#") or "=" not in line:
            lines.append(line)
            continue
        lines.append(line.replace(token, desktop_id))
    return "\n".join(lines) + "\n"


def parse_mimeapps(text):
    preamble = []
    order = []
    body = {}
    current = None
    for line in text.splitlines():
        stripped = line.strip()
        if (
            stripped.startswith("[")
            and stripped.endswith("]")
            and "=" not in stripped
        ):
            current = stripped[1:-1]
            if current not in body:
                body[current] = []
                order.append(current)
            continue
        if current is None:
            preamble.append(line)
            continue
        body[current].append(line)
    return preamble, order, body


def section_keys(lines):
    keys = {}
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        keys[key] = value
    return keys


def first_desktop(value):
    cleaned = value.strip().strip(";")
    if not cleaned:
        return ""
    return cleaned.split(";", 1)[0].strip()


def render(preamble, order, body):
    parts = []
    if any(line.strip() for line in preamble):
        parts.append("\n".join(preamble).rstrip("\n"))
    for name in order:
        block = [f"[{name}]", *body[name]]
        parts.append("\n".join(block).rstrip("\n"))
    return "\n\n".join(parts) + "\n"


desktop_id, desktop_state = vscode_desktop_id()
src_text = substitute(Path(src_path).read_text(), desktop_id)
dest = Path(dest_path)
dest_raw = dest.read_text() if dest.is_file() else ""
managed = any(
    line.startswith("# managed by dot-files configure-mime-defaults")
    for line in dest_raw.splitlines()
)

action = "keep"
new = dest_raw
if not dest.is_file() or managed:
    action = "write"
    new = src_text
else:
    src_preamble, src_order, src_body = parse_mimeapps(src_text)
    preamble, order, body = parse_mimeapps(dest_raw)
    del src_preamble
    changed = False
    for name in src_order:
        wanted = section_keys(src_body[name])
        if name not in body:
            body[name] = []
            order.append(name)
            changed = True
        current = section_keys(body[name])
        for key, value in wanted.items():
            existing = current.get(key)
            if existing is None:
                insert_at = len(body[name])
                while insert_at > 0 and body[name][insert_at - 1].strip() == "":
                    insert_at -= 1
                body[name].insert(insert_at, f"{key}={value}")
                changed = True
                continue
            named = first_desktop(existing)
            if named and desktop_exists(named):
                continue
            replaced = False
            updated = []
            for line in body[name]:
                stripped = line.strip()
                if not replaced and stripped.startswith(f"{key}="):
                    updated.append(f"{key}={value}")
                    replaced = True
                else:
                    updated.append(line)
            if not replaced:
                updated.append(f"{key}={value}")
            body[name] = updated
            changed = True
    if changed:
        action = "merge"
        new = render(preamble, order, body)

if new == dest_raw:
    action = "keep"

sys.stdout.write(f"{action}\t{desktop_id}\t{desktop_state}\n")
if dry_run or action == "keep":
    raise SystemExit(0)

dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(new)
PY
)"
mime_action="${mime_result%%$'\t'*}"
mime_rest="${mime_result#*$'\t'}"
vscode_desktop_id="${mime_rest%%$'\t'*}"
vscode_desktop_state="${mime_rest#*$'\t'}"
log "VS Code desktop id: ${vscode_desktop_id}"
if [[ "$vscode_desktop_state" == "missing" ]]; then
    warn "VS Code desktop file not found; MIME defaults still name code.desktop"
fi
case "$mime_action" in
    write) log "write ${dest}" ;;
    merge) log "merge MIME defaults into ${dest}" ;;
    keep) log "MIME defaults already set in ${dest}" ;;
    *) die "unexpected mimeapps result: ${mime_result}" ;;
esac

if [[ -f "$menu_src" ]]; then
    if [[ ! -f "$menu_dest" ]] || ! cmp -s "$menu_src" "$menu_dest"; then
        log "write ${menu_dest}"
        if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
            install -m 0644 "$menu_src" "$menu_dest"
        fi
    fi
fi

if [[ -f "$mime_xml_src" ]]; then
    if [[ ! -f "$mime_xml_dest" ]] || ! cmp -s "$mime_xml_src" "$mime_xml_dest"; then
        log "write ${mime_xml_dest}"
        if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
            install -m 0644 "$mime_xml_src" "$mime_xml_dest"
        fi
    fi
fi

if [[ -d "$svc_src" ]]; then
    shopt -s nullglob
    for desktop in "$svc_src"/*.desktop; do
        name="$(basename "$desktop")"
        for dest_dir in "$svc_kf6" "$svc_kf5"; do
            target="${dest_dir}/${name}"
            if [[ ! -f "$target" ]] || ! cmp -s "$desktop" "$target"; then
                log "write ${target}"
                if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
                    install -m 0755 "$desktop" "$target"
                fi
            fi
        done
    done
fi

# Merge keys into kdeglobals / dolphinrc without clobbering other settings.
ensure_kde_key() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value="$4"

    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: ${file} [${section}] ${key}=${value}"
        return 0
    fi

    python3 - "$file" "$section" "$key" "$value" <<'PY'
import sys
from pathlib import Path

path, section, key, value = sys.argv[1:]
p = Path(path)
text = p.read_text() if p.exists() else ""
lines = text.splitlines()
header = f"[{section}]"
out = []
in_section = False
seen_section = False
written = False

for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        if in_section and not written:
            out.append(f"{key}={value}")
            written = True
        in_section = stripped == header
        if in_section:
            seen_section = True
        out.append(line)
        continue
    if in_section and stripped.startswith(f"{key}="):
        out.append(f"{key}={value}")
        written = True
        continue
    out.append(line)

if seen_section:
    if not written:
        out.append(f"{key}={value}")
else:
    if out and out[-1] != "":
        out.append("")
    out.append(header)
    out.append(f"{key}={value}")

p.parent.mkdir(parents=True, exist_ok=True)
new = "\n".join(out) + "\n"
if new != text:
    p.write_text(new)
PY
}

seed_tango_dark() {
    local dest_file="$1"
    local src_file="$2"

    [[ -f "$src_file" ]] || return 0
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "dry-run: seed Tango Dark into ${dest_file}"
        return 0
    fi
    if [[ ! -f "$dest_file" ]]; then
        log "write ${dest_file} from ${src_file}"
        install -m 0644 "$src_file" "$dest_file"
        return 0
    fi
    log "sync Tango Dark color groups into ${dest_file}"
    python3 - "$dest_file" "$src_file" <<'PY'
import sys
from pathlib import Path

dest, src = Path(sys.argv[1]), Path(sys.argv[2])
text = dest.read_text() if dest.exists() else ""
src_text = src.read_text()
wanted = (
    "[Colors:Window]",
    "[Colors:View]",
    "[Colors:Button]",
    "[Colors:Selection]",
    "[Colors:Tooltip]",
    "[Colors:Complementary]",
    "[Colors:Header]",
)
blocks = []
current = None
buf = []
for line in src_text.splitlines():
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        if current in wanted:
            blocks.append("\n".join(buf).rstrip())
        current = stripped
        buf = [line]
        continue
    if current in wanted:
        buf.append(line)
if current in wanted and buf:
    blocks.append("\n".join(buf).rstrip())
if not blocks:
    raise SystemExit(0)

def strip_wanted(src):
    out = []
    skip = False
    for line in src.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            skip = stripped in wanted
        if not skip:
            out.append(line)
    return "\n".join(out).rstrip()

base = strip_wanted(text)
addon = "\n\n".join(blocks)
new = (base + "\n\n" + addon + "\n") if base else (addon + "\n")
if new != text:
    dest.write_text(new)
PY
}

ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" KDE SingleClick false
ensure_kde_key "${CONFIG_TARGET_DIR}/dolphinrc" KDE SingleClick false
ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" General TerminalApplication kitty
ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" General TerminalService kitty.desktop
ensure_kde_key "${CONFIG_TARGET_DIR}/dolphinrc" General TerminalApplication kitty

ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" General ColorScheme TangoDark
ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" General Name "Tango Dark"
ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" General widgetStyle Fusion
ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" Icons Theme breeze-dark
ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" KDE LookAndFeelPackage org.kde.breezedark.desktop
ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" KDE widgetStyle Fusion
ensure_kde_key "${CONFIG_TARGET_DIR}/kdeglobals" UiSettings ColorScheme TangoDark
seed_tango_dark "$theme_dest" "$theme_src"

scheme_src="${SETUP_FILES_DIR}/color-schemes/TangoDark.colors"
scheme_dest="${DOTFILES_HOME}/.local/share/color-schemes/TangoDark.colors"
if [[ -f "$scheme_src" ]]; then
    ensure_dir "$(dirname "$scheme_dest")"
    if [[ ! -f "$scheme_dest" ]] || ! cmp -s "$scheme_src" "$scheme_dest"; then
        log "write ${scheme_dest}"
        if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
            install -m 0644 "$scheme_src" "$scheme_dest"
        fi
    fi
fi


if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
    exit 0
fi

if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database "${DOTFILES_HOME}/.local/share/mime" >/dev/null 2>&1 || true
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${DOTFILES_HOME}/.local/share/applications" 2>/dev/null || true
fi

if command -v kbuildsycoca6 >/dev/null 2>&1; then
    log "kbuildsycoca6"
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || kbuildsycoca6 || true
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
    log "kbuildsycoca5"
    kbuildsycoca5 --noincremental >/dev/null 2>&1 || kbuildsycoca5 || true
else
    warn "kbuildsycoca6 not on PATH; Dolphin may need a session restart after first install"
fi
