#!/usr/bin/env bash
# Install ScummVM under ~/games, copy Quest for Glory 1-4 (and QFG5
# data if present) out of the Steam collection, and write desktop
# launchers with official ScummVM game icons.
#
# QFG1-4 are SCI and run well. QFG5 is copied when found; a launcher is
# only written if ScummVM detects it.

set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

require_user

GAMES_ROOT="${GAMES_ROOT:-${DOTFILES_HOME}/games}"
SCUMMVM_HOME="${SCUMMVM_HOME:-${GAMES_ROOT}/scummvm}"
QFG_DEST="${QFG_DEST:-${GAMES_ROOT}/quest-for-glory}"
STEAM_QFG="${STEAM_QFG:-${DOTFILES_HOME}/games/steam-library/steamapps/common/Quest for Glory Collection}"
SCUMMVM_CONFIG="${SCUMMVM_HOME}/scummvm.ini"
ICON_DIR="${SCUMMVM_HOME}/icons"
ICON_BASE="https://raw.githubusercontent.com/scummvm/scummvm-icons/master/icons"
DESKTOP_DIR="${XDG_DESKTOP_DIR:-}"
if [[ -z "$DESKTOP_DIR" ]] && command -v xdg-user-dir >/dev/null 2>&1; then
    DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
fi
DESKTOP_DIR="${DESKTOP_DIR:-${DOTFILES_HOME}/Desktop}"
APPS_DIR="${XDG_DATA_HOME:-${DOTFILES_HOME}/.local/share}/applications"
MARKER="X-DotFiles-QFG"

RSYNC_EXCLUDES=(
    --exclude DOSBOX
    --exclude dosbox
    --exclude '*.exe'
    --exclude '*.EXE'
    --exclude '*.bat'
    --exclude '*.BAT'
    --exclude '*.com'
    --exclude '*.COM'
    --exclude '*.dll'
    --exclude '*.DLL'
    --exclude installer
    --exclude INSTALL
    --exclude __MACOSX
)

has_sci_data() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    shopt -s nullglob
    local hits=("$dir"/RESOURCE.MAP "$dir"/resource.map "$dir"/*.MAP "$dir"/*.map "$dir"/RESOURCE.000 "$dir"/resource.000)
    shopt -u nullglob
    [[ "${#hits[@]}" -gt 0 ]]
}

copy_tree() {
    local src="$1"
    local dest="$2"
    ensure_dir "$dest"
    log "copy ${src} -> ${dest}"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    rsync -a --delete "${RSYNC_EXCLUDES[@]}" "${src%/}/" "${dest%/}/"
}

find_variant_dir() {
    local root="$1"
    shift
    local name
    for name in "$@"; do
        if [[ -d "${root}/${name}" ]] && has_sci_data "${root}/${name}"; then
            printf '%s\n' "${root}/${name}"
            return 0
        fi
    done
    if has_sci_data "$root"; then
        printf '%s\n' "$root"
        return 0
    fi
    return 1
}

fetch_icon() {
    local file="$1"
    local dest="${ICON_DIR}/${file}"
    if [[ -f "$dest" ]]; then
        return 0
    fi
    log "icon ${file}"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    if ! curl -fsSL "${ICON_BASE}/${file}" -o "$dest"; then
        warn "could not download ${file}"
        rm -f "$dest"
        return 1
    fi
}

write_desktop() {
    local dest="$1"
    local name="$2"
    local comment="$3"
    local target="$4"
    local icon="$5"
    cat >"$dest" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=${name}
Comment=${comment}
Exec=${SCUMMVM_HOME}/run-qfg.sh ${target}
Icon=${icon}
Terminal=false
Categories=Game;AdventureGame;
StartupNotify=true
${MARKER}=1
EOF
    chmod 0755 "$dest"
}

write_wrapper() {
    local dest="${SCUMMVM_HOME}/run-qfg.sh"
    log "write ${dest}"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    cat >"$dest" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
HOME_GAMES="${HOME}/games/scummvm"
CONFIG="${HOME_GAMES}/scummvm.ini"
BIN="$(command -v scummvm || true)"
if [[ -x "${HOME_GAMES}/bin/scummvm" ]]; then
    BIN="${HOME_GAMES}/bin/scummvm"
fi
if [[ -z "$BIN" ]]; then
    printf 'error: scummvm is not installed\n' >&2
    exit 1
fi
if [[ "${1:-}" == "--gui" || -z "${1:-}" ]]; then
    exec "$BIN" -c "$CONFIG"
fi
exec "$BIN" -c "$CONFIG" "$@"
EOF
    chmod 0755 "$dest"
}

write_ini_header() {
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    cat >"$SCUMMVM_CONFIG" <<EOF
[scummvm]
versioninfo=dot-files
gfx_mode=opengl
fullscreen=false
aspect_ratio=true
stretch_mode=fit
scaler=normal
scale_factor=3
themepath=/usr/share/scummvm
extrapath=/usr/share/scummvm
iconspath=${ICON_DIR}
savepath=${SCUMMVM_HOME}/saves
EOF
}

append_game_ini() {
    local section="$1"
    local gameid="$2"
    local description="$3"
    local path="$4"
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi
    cat >>"$SCUMMVM_CONFIG" <<EOF

[${section}]
gameid=${gameid}
description=${description}
path=${path}
path.extra=${path}
guioptions=sndNoMIDI
platform=pc
EOF
}

refresh_desktop_cache() {
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
    fi
    if command -v xdg-desktop-menu >/dev/null 2>&1; then
        xdg-desktop-menu forceupdate >/dev/null 2>&1 || true
    fi
}

# --- packages and layout ------------------------------------------------

ensure_packages scummvm rsync curl
command -v scummvm >/dev/null 2>&1 || die "scummvm is not on PATH after package install"
command -v rsync >/dev/null 2>&1 || die "rsync is not on PATH after package install"

if [[ ! -d "$STEAM_QFG" ]]; then
    die "Steam Quest for Glory Collection not found at ${STEAM_QFG}"
fi

ensure_dir "$GAMES_ROOT"
ensure_dir "$SCUMMVM_HOME"
ensure_dir "${SCUMMVM_HOME}/saves"
ensure_dir "$ICON_DIR"
ensure_dir "$QFG_DEST"
ensure_dir "$DESKTOP_DIR"
ensure_dir "$APPS_DIR"

if [[ ! -x "${SCUMMVM_HOME}/bin/scummvm" && "${DOTFILES_DRY_RUN:-0}" != "1" ]]; then
    ensure_dir "${SCUMMVM_HOME}/bin"
    run ln -sfn "$(command -v scummvm)" "${SCUMMVM_HOME}/bin/scummvm"
fi

write_wrapper
write_ini_header
fetch_icon "org.scummvm.scummvm.png" || fetch_icon "scummvm.png" || true

# --- copy game data -----------------------------------------------------

copied=0

qfg1_root=""
for cand in "${STEAM_QFG}/QG1" "${STEAM_QFG}/qg1" "${STEAM_QFG}/QFG1"; do
    [[ -d "$cand" ]] && qfg1_root="$cand" && break
done

if [[ -n "$qfg1_root" ]]; then
    if src="$(find_variant_dir "$qfg1_root" VGA vga QG1VGA .)"; then
        copy_tree "$src" "${QFG_DEST}/qfg1vga"
        append_game_ini qfg1vga qfg1vga "Quest for Glory I: So You Want To Be A Hero (VGA)" "${QFG_DEST}/qfg1vga"
        fetch_icon sci-qfg1vga.png || true
        copied=$((copied + 1))
    fi
    if src="$(find_variant_dir "$qfg1_root" EGA ega QG1EGA)"; then
        copy_tree "$src" "${QFG_DEST}/qfg1ega"
        append_game_ini qfg1 qfg1 "Quest for Glory I: So You Want To Be A Hero (EGA)" "${QFG_DEST}/qfg1ega"
        fetch_icon sci-qfg1.png || true
        copied=$((copied + 1))
    fi
else
    warn "QG1 not found under ${STEAM_QFG}"
fi

copy_numbered() {
    local num="$1"
    local dest_name="$2"
    local gameid="$3"
    local title="$4"
    local icon="$5"
    local root=""
    local cand
    for cand in \
        "${STEAM_QFG}/QG${num}" \
        "${STEAM_QFG}/qg${num}" \
        "${STEAM_QFG}/QFG${num}" \
        "${STEAM_QFG}/QG${num}-"; do
        if [[ -d "$cand" ]]; then
            root="$cand"
            break
        fi
    done
    if [[ -z "$root" ]]; then
        warn "QG${num} not found under ${STEAM_QFG}"
        return 0
    fi
    if ! src="$(find_variant_dir "$root" .)"; then
        warn "QG${num} has no recognizable SCI data in ${root}"
        return 0
    fi
    copy_tree "$src" "${QFG_DEST}/${dest_name}"
    append_game_ini "$gameid" "$gameid" "$title" "${QFG_DEST}/${dest_name}"
    fetch_icon "$icon" || true
    copied=$((copied + 1))
}

copy_numbered 2 qfg2 qfg2 "Quest for Glory II: Trial by Fire" sci-qfg2.png
copy_numbered 3 qfg3 qfg3 "Quest for Glory III: Wages of War" sci-qfg3.png
copy_numbered 4 qfg4 qfg4 "Quest for Glory IV: Shadows of Darkness" sci-qfg4.png

# QFG5 is SCI32 / Windows; register only if ScummVM lists it.
qfg5_root=""
for cand in "${STEAM_QFG}/QG5" "${STEAM_QFG}/qg5" "${STEAM_QFG}/QG5-" "${STEAM_QFG}/QFG5"; do
    if [[ -d "$cand" ]]; then
        qfg5_root="$cand"
        break
    fi
done
if [[ -n "$qfg5_root" ]]; then
    copy_tree "$qfg5_root" "${QFG_DEST}/qfg5"
    if [[ "${DOTFILES_DRY_RUN:-0}" != "1" ]] \
        && scummvm --list-games 2>/dev/null | grep -qiE 'qfg5|quest for glory v|dragon fire'; then
        append_game_ini qfg5 qfg5 "Quest for Glory V: Dragon Fire" "${QFG_DEST}/qfg5"
        fetch_icon sci-qfg5.png || true
        copied=$((copied + 1))
        HAVE_QFG5=1
    else
        warn "QFG5 data copied to ${QFG_DEST}/qfg5 but this ScummVM build does not list it"
        HAVE_QFG5=0
    fi
else
    HAVE_QFG5=0
fi

[[ "$copied" -gt 0 ]] || die "copied no Quest for Glory data from ${STEAM_QFG}"

# --- launchers ----------------------------------------------------------

write_one() {
    local slug="$1"
    local name="$2"
    local comment="$3"
    local target="$4"
    local icon_file="$5"
    local icon="${ICON_DIR}/${icon_file}"
    if [[ ! -f "$icon" ]]; then
        icon="scummvm"
    fi
    if [[ "${DOTFILES_DRY_RUN:-0}" == "1" ]]; then
        log "would write launcher ${slug}"
        return 0
    fi
    write_desktop "${DESKTOP_DIR}/${slug}.desktop" "$name" "$comment" "$target" "$icon"
    write_desktop "${APPS_DIR}/${slug}.desktop" "$name" "$comment" "$target" "$icon"
}

write_one scummvm-qfg "ScummVM (Quest for Glory)" \
    "ScummVM with Quest for Glory games" --gui org.scummvm.scummvm.png

if [[ -d "${QFG_DEST}/qfg1vga" ]]; then
    write_one qfg1vga "Quest for Glory I (VGA)" \
        "So You Want To Be A Hero" qfg1vga sci-qfg1vga.png
fi
if [[ -d "${QFG_DEST}/qfg1ega" ]]; then
    write_one qfg1ega "Quest for Glory I (EGA)" \
        "So You Want To Be A Hero" qfg1 sci-qfg1.png
fi
if [[ -d "${QFG_DEST}/qfg2" ]]; then
    write_one qfg2 "Quest for Glory II" "Trial by Fire" qfg2 sci-qfg2.png
fi
if [[ -d "${QFG_DEST}/qfg3" ]]; then
    write_one qfg3 "Quest for Glory III" "Wages of War" qfg3 sci-qfg3.png
fi
if [[ -d "${QFG_DEST}/qfg4" ]]; then
    write_one qfg4 "Quest for Glory IV" "Shadows of Darkness" qfg4 sci-qfg4.png
fi
if [[ "${HAVE_QFG5:-0}" == "1" ]]; then
    write_one qfg5 "Quest for Glory V" "Dragon Fire" qfg5 sci-qfg5.png
fi

refresh_desktop_cache
log "ScummVM + Quest for Glory ready under ${GAMES_ROOT}"
