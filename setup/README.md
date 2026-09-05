# setup

One control script at this directory root applies a machine role by
calling modules under `modules/`. Re-running a role is the intended
upgrade path.

```bash
~/dot-files/setup/role.sh workstation
~/dot-files/setup/role.sh laptop
~/dot-files/setup/role.sh htpc
~/dot-files/setup/role.sh server
```

## First boot

From a computer that already works, against a fresh box that has a user
and sshd:

```bash
./setup/init-remote.sh dragon@newbox.lan workstation
```

`init-remote.sh` opens one SSH master and then:

1. Installs this computer's SSH public keys on the new box
2. Copies the secrets list onto the new box
3. Installs `git` and `curl` on the new box
4. Generates `~/.ssh/id_ed25519` on the new box if it is missing
5. Prints the public key and registers it with GitHub using `gh` on
   this computer
6. `git clone git@github.com:DragonCrafted87/dot-files.git ~/dot-files`

Same role names as `role.sh`: `workstation`, `laptop`, `htpc`, `server`.
After the clone, SSH in and run the role:

```bash
~/dot-files/setup/role.sh workstation
```

## Reset without reinstalling

Keeps `/home` and the role's declared packages. Drops other
user-installed rpms and extra Flatpaks (Plasma leftovers included).

```bash
./setup/role.sh workstation reset
RESET_CONFIRM=yes ./setup/role.sh workstation reset
DOTFILES_DRY_RUN=1 ./setup/role.sh laptop reset
```

The first run only prints the extras. Add names to
`files/packages/never-remove.list` if something you want is listed.

Optional overrides:

```bash
DOTFILES_HOSTNAME=study.lan ~/dot-files/setup/role.sh laptop
DOTFILES_DRY_RUN=1 ~/dot-files/setup/role.sh server
```

A single module can be run on its own:

```bash
~/dot-files/setup/modules/link-user-config.sh
```

## Roles

| Role | Extra modules |
| --- | --- |
| `workstation` | Hyprland, desktop apps, Brave, VS Code, LibreOffice, CUPS, Steam, BOINC Manager |
| `laptop` | same minus Steam, plus power-profiles-daemon, BOINC Manager |
| `htpc` | Hyprland, desktop apps, Brave, k3s, BOINC client |
| `server` | CLI baseline, k3s, BOINC client; no GUI session |

The chosen role is written to `~/.config/dot-files/role`.

Rock extra / restricted / non-free are enabled on every role. Architecture
is AMD family 23+ → `znver1`, otherwise `x86_64` (ISO `rpm %{_arch}` is
usually `x86_64` even on Zen). The opposite arch is disabled.

Harvest printer queues on the current workstation, then commit them:

```bash
sudo ~/dot-files/setup/utility/harvest-cups.sh
```

That copies `/etc/cups/printers.conf` and `/etc/cups/ppd/` into
`setup/files/cups/`. Workstation and laptop replay those
files.

Copy secrets onto a new box without going through `init-remote.sh`:

```bash
~/dot-files/setup/utility/transfer-secrets.sh dragon@newbox.lan
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
