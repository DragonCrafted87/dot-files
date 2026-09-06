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

| Role          | Extra modules                                                                            |
| ------------- | ---------------------------------------------------------------------------------------- |
| `workstation` | Hyprland, desktop apps, Brave, VS Code, LibreOffice, CUPS, Steam, MakeMKV, BOINC Manager |
| `laptop`      | workstation plus `configure-laptop` (power-profiles-daemon)                              |
| `htpc`        | Hyprland, desktop apps, Brave, k3s, BOINC client                                         |
| `server`      | CLI baseline, k3s, BOINC client; no GUI session                                          |

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

Every role installs `boinc-client`. Workstation and laptop also get
`boinc-manager`. Fill `files/boinc/hosts.list` with real hostnames so
each client allows GUI RPC from the others. Role prefs live in
`files/boinc/prefs/<role>.xml`. A `git pull` plus a role rerun recopies
hosts, prefs, and helper scripts and restarts the client only if they
changed. `~/.config/dot-files/boinc-rpc.password` holds
`rpc_password`, `science_united_user`, and `science_united_password`.
`utility/transfer-secrets.sh` copies that file. The role attaches Science United
unattended once those fields are set.

```bash
sudo /usr/local/bin/boinc-config.sh
sudo /usr/local/bin/boinc-status.sh
sudo /usr/local/bin/boinc-status-all.sh
```

In the manager: Advanced → Select computer → hostname + that password.

k3s gets `CPUWeight=500`. BOINC gets `CPUWeight=idle`, `Nice=10`, and
`lower_client_priority`. Wine and Steam pause BOINC; gamescope is left
out because it is not used here. Per-role prefs cap cores/RAM and
suspend when other CPU is busy.

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
