# setup

One control script at this directory root applies a machine role by
calling modules under `modules/`.
Re-running a role is the intended
upgrade path. What each role runs is listed in `roles.conf`.

```bash
~/dot-files/setup/role.sh workstation
~/dot-files/setup/role.sh laptop
~/dot-files/setup/role.sh htpc
~/dot-files/setup/role.sh server
```

```bash
~/dot-files/setup/role.sh --hostname study.lan laptop
~/dot-files/setup/role.sh --dry-run server
```

## First boot

From a computer that already works, against a fresh box that has a user
and sshd:

```bash
./setup/init-remote.sh dragon@newbox.lan workstation
```

`init-remote.sh` opens one SSH master and then:

1. Installs this computer's SSH public keys on the new box
1. Copies the secrets list onto the new box
1. Installs `git` and `curl` on the new box
1. Generates `~/.ssh/id_ed25519` on the new box if it is missing
1. Prints the public key and registers it with GitHub using `gh` on
   this computer
1. `git clone git@github.com:DragonCrafted87/dot-files.git ~/dot-files`

Same role names as `role.sh`: `workstation`, `laptop`, `htpc`, `server`.
After the clone, SSH in and run the role:

```bash
~/dot-files/setup/role.sh workstation
```

## Reset without reinstalling

Keeps `/home` and the role's declared packages. Drops other
user-installed rpms and extra Flatpaks (Plasma leftovers included).

```bash
./setup/role.sh --reset workstation
./setup/role.sh --reset --force workstation
./setup/role.sh --dry-run --reset laptop
```

The first run only prints the extras. Add `--force` to actually remove
them. Add names to `files/packages/never-remove.list` if something you
want is listed.

A single module can be run on its own:

```bash
~/dot-files/setup/modules/link-user-config.sh
```

## Roles

Edit `roles.conf` to change the module lists. `[common]` runs for every
role. `laptop` includes `@workstation` and then laptop-only modules.

| Role          | Extra modules                                                                                         |
| ------------- | ----------------------------------------------------------------------------------------------------- |
| `workstation` | Hyprland, desktop apps, Brave, VS Code, LibreOffice, CUPS, Steam, MakeMKV, KDE Connect, BOINC Manager |
| `laptop`      | workstation plus `configure-laptop` (power-profiles-daemon)                                           |
| `htpc`        | Hyprland, desktop apps, Brave, k3s, BOINC client                                                      |
| `server`      | CLI baseline, k3s, BOINC client; no GUI session                                                       |

Dolphin is the Hyprland file manager (`SUPER+E`). After
`remove-plasma-sddm` strips Plasma, it has no KService/MIME map unless
`install-desktop-packages` installs `plasma6-dolphin` plus KIO extras and
`configure-mime-defaults` writes `~/.config/mimeapps.list` and runs
`kbuildsycoca6`. The other half is `config/hypr/conf.d/env.conf`
(`XDG_CURRENT_DESKTOP=Hyprland:KDE`) so KIO treats LibreOffice and Okular
as valid "Open with" targets.

The chosen role is written to `~/.config/dot-files/role`.

Rock extra / restricted / non-free are enabled on every role. Architecture
is AMD family 23+ → `znver1`, otherwise `x86_64` (ISO `rpm %{_arch}` is
usually `x86_64` even on Zen). The opposite arch is disabled.

Harvest printer queues on the current workstation, then commit them:

```bash
sudo ~/dot-files/setup/utility/harvest-cups.sh
```

That copies `/etc/cups/printers.conf` and `/etc/cups/ppd/` into
`setup/files/cups/`.
Workstation and laptop replay those
files.

Copy secrets onto a new box without going through `init-remote.sh`:

```bash
~/dot-files/setup/utility/transfer-secrets.sh dragon@newbox.lan
```

## Hyprland from source

`install-hyprland-session` keeps the OpenMandriva Hyprland rpms and the
stock Ly session. `install-hyprland-source` (workstation / laptop / htpc)
then builds Hyprland **v0.56.2** plus the hypr* ecosystem into
`/opt/hyprland-0.56.2` so the two stacks do not share libraries or
binaries.

Ly extra session: **Hyprland (source 0.56.2)**. Desktop file lives in
`/etc/ly/custom-sessions/` and `/usr/share/wayland-sessions/` under the
name `hyprland-source.desktop`, never overwriting the distro
`hyprland.desktop`. The wrapper
`/opt/hyprland-0.56.2/bin/start-hyprland-source` prepends the prefix to
`PATH` / `LD_LIBRARY_PATH` only for that session.

OpenMandriva has no single published dep list. The module translates the
Fedora set from [Hyprland discussion #284](https://github.com/hyprwm/Hyprland/discussions/284)
plus current cmake/Qt6 pieces, using the same `pick_pkg` fallbacks as
MakeMKV.

```bash
~/dot-files/setup/modules/install-hyprland-source.sh
HYPRLAND_SOURCE_FORCE=1 ~/dot-files/setup/modules/install-hyprland-source.sh
```

Override prefix or a tag (`HYPRLAND_TAG`, `AQUAMARINE_TAG`, …) in the
environment. Sources cache under `~/.cache/hyprland-source`.

## KDE Connect / GrapheneOS SMS

`install-kdeconnect` is on workstation (and therefore laptop). It
installs the `kdeconnect` rpm plus `android-tools`, and opens firewalld
ports 1714-1764 (or the packaged `kdeconnect` service if present).
Hyprland starts the daemon from `config/hypr/scripts/start-kdeconnect.sh`.

Pair the GrapheneOS phone yourself. Steps are in
`setup/files/kdeconnect/README.md`. Short version: F-Droid KDE Connect,
same Wi-Fi, pair, grant SMS/contacts/notifications, enable the SMS
plugin. Sent messages that never show up on the desktop need:

```bash
adb shell appops set --uid org.kde.kdeconnect_tp READ_RESTRICTED_MESSAGES allow
adb shell am force-stop org.kde.kdeconnect_tp
```

## MakeMKV

`install-makemkv` is on workstation (and therefore laptop). It exits
immediately if no optical drive is present (`/dev/sr*` with
`ID_CDROM=1`). Otherwise it builds MakeMKV 1.18.4 from the official
oss+bin tarballs using `clang`/`clang++` and `lld`, against distro
ffmpeg/Qt5 devel packages. Override the version with
`MAKEMKV_VERSION=1.18.4`.

Login autostart runs `~/bin/sync-makemkv-desktops.sh`, which writes one
`~/Desktop/MakeMKV-srN.desktop` per attached drive and deletes stale
ones. Re-run that script after plugging in a USB Blu-ray drive.

```bash
~/dot-files/setup/modules/install-makemkv.sh
~/bin/sync-makemkv-desktops.sh
```

## ScummVM / Quest for Glory

`install-scummvm-quest-for-glory` is an optional module (not part of any
role). It installs the distro `scummvm` package, links the binary under
`~/games/scummvm`, copies Quest for Glory data out of the Steam
collection, and writes Desktop plus applications-menu launchers.

Expected Steam path:

```text
~/games/steam-library/steamapps/common/Quest for Glory Collection/
```

Override with `STEAM_QFG`. Game data lands in `~/games/quest-for-glory/`
(DOSBox binaries are not copied). Isolated config and saves live in
`~/games/scummvm/`. Icons come from the official scummvm-icons repo.
QFG5 is copied when present; a launcher is created only if that ScummVM
build lists the game.

```bash
~/dot-files/setup/modules/install-scummvm-quest-for-glory.sh
```

## BOINC

Every role installs the Flathub app `edu.berkeley.BOINC`. OpenMandriva
has no BOINC rpms; the old Fedora packages were ABI-mismatched and are
removed on the next role run.

The client is a lingering user unit, not a system daemon:

```text
~/.config/systemd/user/boinc-client.service
~/.var/app/edu.berkeley.BOINC/          data dir
/etc/boinc-client/prefs/<role>.xml      installed role prefs
```

`loginctl enable-linger` keeps it running after logout so servers and
the HTPC still crunch without a desktop session. Manager and CLI share
that data dir:

```bash
boincmgr
flatpak run edu.berkeley.BOINC
/usr/local/bin/boinc-config.sh
/usr/local/bin/boinc-status.sh
/usr/local/bin/boinc-status-all.sh
systemctl --user status boinc-client.service
```

Fill `files/boinc/hosts.list` with real hostnames so each client allows
GUI RPC from the others. Role prefs live in `files/boinc/prefs/<role>.xml`
and are installed to `/etc/boinc-client/prefs/`. The current role from
`~/.config/dot-files/role` is copied to
`~/.var/app/edu.berkeley.BOINC/global_prefs_override.xml`.

`/usr/local/bin/boinc-config.sh` always rewrites that override from the
role XML and tells the client `--read_global_prefs_override`. After
prefs are applied it attaches Science United if the secret file has a
login. `BOINC_REPLACE=1` detaches and reattaches.

`~/.config/dot-files/boinc-rpc.password` holds `rpc_password`,
`science_united_user` (the Science United **email**), and
`science_united_password`. `utility/transfer-secrets.sh` copies that
file.

In the manager: Advanced → Select computer → `127.0.0.1` + that
password. Do not let the manager start a second client; the user unit
already owns port 31416.

k3s gets `CPUWeight=500`. BOINC gets `CPUWeight=idle`, `Nice=10`, and
`lower_client_priority`. Wine (`wine`, `wine64`, `wineserver`) pauses
BOINC via `cc_config.xml` exclusive apps. Browsers are not exclusive
apps so long-lived Brave/Firefox windows do not park the client.
RAM limits must use `ram_max_used_idle_pct` / `ram_max_used_busy_pct` /
`vm_max_used_pct` (percent 0-100). The old `*_frac` tags are ignored.

Flatpak BOINC on Hyprland does not see user idle, so `idle_time_to_run`
is left at 0 and desktop roles keep `run_if_user_active`. Protection is
the always-on CPU/RAM caps plus GPU off while the session exists.

Current `global_preferences` overrides:

| Role          | CPU while active | CPU cap | CPU limit | Suspend if other CPU | Idle delay | RAM idle/busy | GPU while active |
| ------------- | ---------------- | ------- | --------- | -------------------- | ---------- | ------------- | ---------------- |
| `workstation` | yes              | 35%     | 50%       | 20%                  | 0          | 40% / 25%     | no               |
| `laptop`      | yes              | 30%     | 50%       | 20%                  | 0          | 30% / 15%     | no               |
| `htpc`        | yes              | 60%     | 80%       | 35%                  | 0          | 40% / 20%     | no               |
| `server`      | yes              | 80%     | 100%      | 30%                  | 0          | 40% / 30%     | yes              |

None of the roles run on battery. Edit the XML under `files/boinc/prefs/`
and re-run `install-boinc.sh` or `boinc-config.sh`.

Docker image manager is a standalone placeholder, not part of every server:

```bash
~/dot-files/setup/modules/install-docker-image-manager.sh
```

## Config links

`modules/link-user-config.sh` links every directory in repo `config/`
into `~/.config` with the same name:

```text
config/hyprland    ->  ~/.config/hyprland
config/kitty       ->  ~/.config/kitty
config/quickshell  ->  ~/.config/quickshell
```

Drop another folder under `config/` and the next role run links it. No
module edit. Loose files in `config/` are ignored. A real file or
directory already sitting at the destination is not overwritten.
