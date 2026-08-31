# OpenMandriva setup

Small role scripts at this directory root. Each one calls modules under
`modules/`. Re-running a role is the intended upgrade path.

## First boot

From a computer that already works, against a fresh box that has a user
and sshd:

```bash
./setup/openmandriva/init-remote.sh dragon@newbox.lan workstation
```

That copies the secrets list, copies `first-boot.sh`, then runs it over
`ssh -t` so the `gh` device login can be finished in the browser here.

`first-boot.sh` will:

1. Install `git`, `curl`, and `gh`
2. Generate `~/.ssh/id_ed25519` if it is missing
3. Print the public key
4. Run `gh auth login --web` so you can finish the device login on the
   working computer
5. Upload the new key to GitHub
6. `git clone git@github.com:DragonCrafted87/dot-files.git ~/dot-files`
7. Exec the chosen role script

Same role names as the scripts: `workstation`, `laptop`, `htpc`, `server`.

## Reset without reinstalling

Keeps `/home` and the role's declared packages. Drops other
user-installed rpms and extra Flatpaks (Plasma leftovers included).

```bash
./setup/openmandriva/reset-to-role.sh workstation
RESET_CONFIRM=yes ./setup/openmandriva/reset-to-role.sh workstation
DOTFILES_DRY_RUN=1 ./setup/openmandriva/reset-to-role.sh laptop
```

The first run only prints the extras. Add names to
`files/packages/never-remove.list` if something you want is listed.

Optional overrides:

```bash
DOTFILES_HOSTNAME=study.lan ~/dot-files/setup/openmandriva/laptop.sh
DOTFILES_DRY_RUN=1 ~/dot-files/setup/openmandriva/server.sh
```

A single module can be run on its own:

```bash
~/dot-files/setup/openmandriva/modules/link-user-config.sh
```

## Roles

| Script | Extra modules |
| --- | --- |
| `workstation.sh` | Hyprland, desktop apps, Brave, VS Code, LibreOffice, CUPS, Steam, BOINC Manager |
| `laptop.sh` | same minus Steam, plus power-profiles-daemon, BOINC Manager |
| `htpc.sh` | Hyprland, desktop apps, Brave, k3s, BOINC client |
| `server.sh` | CLI baseline, k3s, BOINC client; no GUI session |

The chosen role is written to `~/.config/dot-files/role`.

Rock extra / restricted / non-free are enabled on every role. Architecture
is AMD family 23+ → `znver1`, otherwise `x86_64` (ISO `rpm %{_arch}` is
usually `x86_64` even on Zen). The opposite arch is disabled.

Harvest printer queues on the current workstation, then commit them:

```bash
sudo ~/dot-files/setup/openmandriva/harvest-cups.sh
```

That copies `/etc/cups/printers.conf` and `/etc/cups/ppd/` into
`setup/openmandriva/files/cups/`. Workstation and laptop replay those
files.

## BOINC

Every role installs `boinc-client`. Workstation and laptop also get
`boinc-manager`. Fill `files/boinc/hosts.list` with real hostnames so
each client allows GUI RPC from the others. Role prefs live in
`files/boinc/prefs/<role>.xml`. A `git pull` plus a role rerun recopies
hosts, prefs, and helper scripts and restarts the client only if they
changed. `~/.config/dot-files/boinc-rpc.password` holds
`rpc_password`, `science_united_user`, and `science_united_password`.
`transfer-secrets.sh` copies that file. The role attaches Science United
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
~/dot-files/setup/openmandriva/modules/install-docker-image-manager.sh
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
