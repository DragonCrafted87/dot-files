# setup

One control script at this directory root applies a machine role by
calling modules under `modules/<area>/`.
Re-running a role is the intended
upgrade path. What each role runs is listed in `roles.conf`.
`roles.conf` stores module basenames; `setup/lib/lib.sh` looks each one up.

```bash
~/dot-files/setup/role.sh workstation
~/dot-files/setup/role.sh workstation --enable-subrole laptop
~/dot-files/setup/role.sh htpc
~/dot-files/setup/role.sh server
~/dot-files/setup/role.sh --target root@192.168.0.51 haos
```

```bash
~/dot-files/setup/role.sh --hostname study workstation --enable-subrole laptop
~/dot-files/setup/role.sh --dry-run server
```

## Hostname

The installer records a short name. A role run sets the static hostname
to that name plus `stealthdragonland.net`, for example
`runewyrm.stealthdragonland.net`. `--hostname` takes the short name, a
`.lan` name, or that FQDN. `/etc/hosts` keeps `127.0.1.1` on the short
name, and DNS keeps the FQDN on the machine's address.

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

Same role names as `role.sh`: `workstation`, `htpc`, `server`.
`haos` is the Home Assistant OS appliance. Run that with
`role.sh --target`, which is the section below. Laptop is a subrole
(`--enable-subrole laptop`), not a top-level role.
After the clone, SSH in and run the role:

```bash
~/dot-files/setup/role.sh workstation
```

## Reset without reinstalling

`--reset` shows the removal preview, asks for approval, then asks about
the role and subroles. The last yes reboots. Later boots remove
packages, run the normal role update, and reboot once more. Workstation
and HTPC stop at Ly. Server stops at the text console.

Quitting the pager or answering no schedules nothing. `--force` is not
a reset flag. A failed phase reboots once and retries. A second failure
stays on the console until `--reset-abort`. The install boot waits until
`mirror.openmandriva.org` resolves before it runs the role, so a slow
DNS startup does not spend both attempts.

```bash
./setup/role.sh --reset
./setup/role.sh --reset --role htpc
./setup/role.sh --dry-run --reset
./setup/role.sh --reset-abort
```

`/home` stays. The remove boot drops other user-installed rpms and extra
Flatpaks. Add names to `files/packages/never-remove.list` if something
you want is listed.

Installer changes can be tried in the OpenMandriva container, and a
role reset in the libvirt clone, before they run on a live machine.
See [testbed/README.md](testbed/README.md).

A single module can be run on its own:

```bash
~/dot-files/setup/modules/common/link-user-config.sh
```

## Module areas

Scripts sit under `modules/<area>/` so the tree shows why they exist.
`roles.conf` still lists the basename.

| Area      | What lives there                                                       |
| --------- | ---------------------------------------------------------------------- |
| `common`  | ssh, sudoers, repos, timezone, locale, plasma removal, links, XDG dirs |
| `desktop` | Hyprland, Brave, Flatpak, CUPS, gaming, MIME, VS Code                  |
| `network` | mounts, bluetooth, NFS server                                          |
| `compute` | BOINC, k3s, python-dev, MakeMKV, artifact/docker stubs                 |
| `host`    | `configure-laptop` / `htpc` / `server` leftovers                       |

Do not name folders after roles. Laptop is a workstation overlay.

## Roles

Edit `roles.conf` to change the module lists. `[common]` runs for
`workstation`, `htpc`, and `server`. `[haos]` does not run `[common]`.
`laptop` is `[subrole.laptop]` on top of `workstation`.

| Role          | Extra modules                                                                                         |
| ------------- | ----------------------------------------------------------------------------------------------------- |
| `workstation` | Hyprland, desktop apps, Brave, VS Code, LibreOffice, CUPS, Steam, MakeMKV, KDE Connect, BOINC Manager |
| `htpc`        | Hyprland, desktop apps, Brave, k3s, BOINC client. Couch build-out: `docs/htpc-role.md`                |
| `server`      | CLI baseline, k3s, BOINC client; no GUI session                                                       |
| `haos`        | SSH keys and the short hostname on a Home Assistant OS appliance                                      |

`enable-subrole laptop` adds `configure-laptop` (power-profiles-daemon).

Dolphin is the Hyprland file manager (`SUPER+E`). After
`remove-plasma-sddm` strips Plasma, it has no KService/MIME map unless
`install-desktop-packages` installs `plasma6-dolphin` plus KIO extras and
`configure-mime-defaults` writes `~/.config/mimeapps.list` and runs
`kbuildsycoca6`. Text and Markdown go to the installed VS Code entry.
An existing list keeps handlers whose desktop file is still on disk;
missing ones are filled in, and handlers that name a removed desktop
file are replaced. The other half is `config/hypr/lua/env.lua`
(`XDG_CURRENT_DESKTOP=Hyprland:KDE`) so KIO treats LibreOffice and Okular
as valid "Open with" targets.

The chosen role is written to `~/.config/dot-files/role`. An `haos`
run leaves that file alone.

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

## Home Assistant OS (ward-drake)

`ward-drake` is the Home Assistant OS image on the NUC that was
`amd64node2.lan`. The disk image step is
`setup/ventoy/ward-drake/install-haos.sh`. After that image boots, run
this from a machine that already has the repo:

```bash
./setup/role.sh --target root@192.168.0.51 haos
```

That is the run. `[haos]` does not run `[common]`, and it does not
change the saved role on the machine where you type it.

The run uses Home Assistant OS host SSH on port 22222. Key login
installs the GitHub keys into `/root/.ssh/authorized_keys` on the host
and sets the short hostname to `ward-drake`. That file is the host
login list. The Terminal & SSH app does not own it. When nothing is
listening on the port, the command writes
`~/.cache/dot-files/haos-config/authorized_keys` and stops. Copy that
file onto a USB partition named `CONFIG`, import it (`ha os import`,
or reboot with the stick attached), and run the command again.

The same run installs the key updater and the console lock under
`/mnt/overlay/dot-files`. The root filesystem is erofs, and
`/etc/systemd/system` is on that filesystem, so the role does not
install unit files there. A udev rule starts `haos-supervise.sh`
after the overlay is mounted. The supervisor refreshes the GitHub
keys two minutes after boot and every twelve hours after a successful
fetch. A bad or empty fetch leaves the current `authorized_keys` in
place and retries in two minutes. The script is `/bin/sh`. The
workstation updater stays
`/usr/local/bin/sync-github-authorized-keys.sh` and still runs as
`dragon`.

The HDMI console starts `ha-cli@tty1`, which accepts commands with no
password. The run adds `systemd.mask=ha-cli@tty1.service` and
`systemd.mask=getty@tty1.service` to `/mnt/boot/cmdline.txt`, keeping
`console=tty0`, and masks both units for the current boot. The
supervisor holds tty1. The screen says the console is locked and
names SSH port 22222. Host SSH on that port stays up. The cmdline
change applies on the next boot.

`init-remote.sh` rejects `haos` and prints that `role.sh --target`
command. DNS for `ward-drake.stealthdragonland.net` stays on
`192.168.0.1`. Until that name resolves, pass the address to
`--target`. `ssh ward-drake` uses `root` on port 22222 once the name
resolves and `ssh-config` is the file the client is reading.

Copy secrets onto a new box without going through `init-remote.sh`:

```bash
~/dot-files/setup/utility/transfer-secrets.sh dragon@newbox.lan
```

## Hyprland from source

`install-hyprland-session` enables Ly and the user session units. It
does not install the OpenMandriva Hyprland rpms, uwsm, or
pavucontrol-qt. Role reset removes the distro `hyprland` package.
`install-hyprland-source` (workstation / laptop / htpc) exits 0 while
`rpm -q hyprland` still succeeds. When that package is gone it builds
the pinned tag plus the hypr\* ecosystem into `/usr/local`.
Pins live in `setup/versions.conf` next to the BOINC and MakeMKV
versions. Current pin is **v0.56.2**; a later bump overwrites
`/usr/local` in place. Do not set the prefix to `/usr`.

Ly session name is **Hyprland**, with
`Exec=/usr/local/bin/start-hyprland`. The desktop file is
`/usr/share/wayland-sessions/hyprland.desktop`.
`hypridle`, `hyprpolkitagent`, the Hyprland portal, `hyprsunset`, and
`hyprpaper` exec `/usr/local`. hyprpwcenter is the volume UI.

OpenMandriva has no single published dep list. The module translates the
Fedora set from [Hyprland discussion #284](https://github.com/hyprwm/Hyprland/discussions/284)
plus current cmake/Qt6 pieces, using the shared `pick_pkg` from `lib.sh`
(lib64\* first on 64-bit).

```bash
mkdir -p ~/.cache/hyprland-source
~/dot-files/setup/modules/desktop/install-hyprland-source.sh 2>&1 | tee ~/.cache/hyprland-source/build.log
HYPRLAND_SOURCE_ONLY=Hyprland ~/dot-files/setup/modules/desktop/install-hyprland-source.sh 2>&1 | tee -a ~/.cache/hyprland-source/build.log
HYPRLAND_SOURCE_FORCE=1 ~/dot-files/setup/modules/desktop/install-hyprland-source.sh 2>&1 | tee ~/.cache/hyprland-source/build.log
```

Override prefix or a tag (`HYPRLAND_TAG`, `AQUAMARINE_TAG`, …) in the
environment; an exported value wins over `versions.conf`. Sources cache
under `~/.cache/hyprland-source`. This module forces GCC 14 + libstdc++

- mold (OpenMandriva cooker recipe; Clang 19 crashes Hyprland at
  launch). Other source builds still use `compiler.bashrc` clang.

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
`~/desktop/MakeMKV-srN.desktop` per attached drive and deletes stale
ones. Re-run that script after plugging in a USB Blu-ray drive.

```bash
~/dot-files/setup/modules/compute/install-makemkv.sh
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
~/dot-files/setup/modules/desktop/install-scummvm-quest-for-glory.sh
```

## BOINC

Every role builds the client and manager from tagged source
`client_release/8.2/8.2.13`. Override with `BOINC_VERSION`. OpenMandriva
has no working BOINC rpms. The compile is skipped when
`/usr/local/share/boinc/.dotfiles-version` already matches the pinned
version. The manager still needs the wxGTK 3.2 runtime libraries
(`lib64wx_baseu3.2_0`, `lib64wx_baseu_net3.2_0`,
`lib64wx_gtk3u_core3.2_0`, `lib64wx_gtk3u_html3.2_0`,
`lib64wx_gtk3u_webview3.2_0`). GPU detection needs Mesa Rusticl
(`lib64RusticlOpenCL`), which provides `/etc/OpenCL/vendors/rusticl.icd`.
The client unit sets `RUSTICL_ENABLE=radeonsi` so that platform exposes
the AMD GPUs.
The compile needs `opencl-headers` and `lib64OpenCL-devel` so
`libboinc_opencl` links `libOpenCL`. Reset removes the devel packages
and Rusticl, and a matching version stamp skips the compile, so every
role run installs the wxGTK libraries and Rusticl again. A stamp match
does not count until `ldd` shows `libOpenCL.so` on `libboinc_opencl.so`.

Source builds pick up `bashrc.d/compiler.bashrc` (`clang`, `lld`,
`-march=native`). On AMD family 23+ that is the matching `znver*` ISA,
not a hard-coded `znver1`.

```text
~/.config/systemd/user/boinc-client.service
~/.local/share/boinc/                     data dir
~/.cache/boinc-build/boinc                source checkout
/usr/local/bin/boinc{,mgr,cmd}
/usr/local/bin/boinc-config
/usr/local/bin/boinc-gpu
/usr/local/bin/boinc-status
/usr/local/bin/boinc-status-all
/usr/local/share/boinc/.dotfiles-version
```

Repo copies of the helpers keep the `.sh` suffix under
`setup/files/boinc/`.
PATH names do not.

`loginctl enable-linger` keeps the user unit
running after logout so servers and the HTPC still crunch without a
desktop session.

```bash
boincmgr
boinc-config
boinc-status
boinc-status-all
systemctl --user status boinc-client.service
```

Fill `files/boinc/hosts.list` with real hostnames so each client allows
GUI RPC from the others. Role prefs live in `files/boinc/prefs/<role>.xml`
and are linked to `~/.local/share/boinc/global_prefs_override.xml`.

`boinc-config` always retargets that override from the role XML and tells
the client `--read_global_prefs_override`. After prefs are applied it
attaches Science United if the secret file has a login. `BOINC_REPLACE=1`
detaches and reattaches.

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

Native BOINC honors `run_if_user_active`, `run_gpu_if_user_active`, and
`idle_time_to_run` directly. Desktop roles keep CPU on while the session
is busy, leave the GPU off until the displays blank, and use the
idle/busy RAM split. Hyprland does not swap pref files. `boinc-gpu`
(from `idle-display-off.sh` / `idle-display-on.sh`, and from
`graphical-session.sh` at login and logout) sets GPU mode to `always`
or `never`. A server has no hypridle session, so its GPU follows the
role XML.

Current `global_preferences` overrides:

| Role          | CPU while active | CPU cap | CPU limit | Suspend if other CPU | Idle delay | RAM idle/busy | GPU while active |
| ------------- | ---------------- | ------- | --------- | -------------------- | ---------- | ------------- | ---------------- |
| `workstation` | yes              | 35%     | 50%       | 20%                  | 3 min      | 40% / 25%     | no               |
| `laptop`      | yes              | 30%     | 50%       | 20%                  | 3 min      | 30% / 15%     | no               |
| `htpc`        | yes              | 60%     | 80%       | 35%                  | 3 min      | 40% / 20%     | no               |
| `server`      | yes              | 80%     | 100%      | 30%                  | 0          | 40% / 30%     | yes              |

None of the roles run on battery. Edit the XML under `files/boinc/prefs/`
and re-run `install-boinc.sh` or `boinc-config`.

Docker image manager is a standalone placeholder, not part of every server:

```bash
~/dot-files/setup/modules/compute/install-docker-image-manager.sh
```

## Config links

`modules/common/link-user-config.sh` links every directory in repo
`config/` into `~/.config` with the same name:

```text
config/hyprland    ->  ~/.config/hyprland
config/kitty       ->  ~/.config/kitty
config/quickshell  ->  ~/.config/quickshell
```

Drop another folder under `config/` and the next role run links it. No
module edit. Loose files in `config/` are ignored. A real file or
directory already sitting at the destination is not overwritten.
