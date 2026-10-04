# Ventoy live procedures

## Reinstall: attach LVM home

Script: `setup/ventoy/runewyrm/reinstall-attach-home.sh`

Copy the `setup/ventoy/runewyrm/` folder onto the Ventoy stick. It does
not need the rest of this repo. It refuses to run unless the installed
root is `runewyrm` (installer defaults like `localhost` are accepted only
when the LVM home already looks like that box).

`runewyrm` keeps `/` on the installer disk and `/home` on LVM:

```text
VG  lv-home
LV  home                 /dev/lv-home/home   ~3.64 TiB
PVs /dev/nvme1n1         /dev/nvme2n1
```

After wiping and reinstalling only the root disk, boot the OpenMandriva
live image from Ventoy and run:

```bash
sudo bash /path/on/ventoy/runewyrm/reinstall-attach-home.sh
```

Then reboot into the installed disk and:

```bash
~/dot-files/setup/role.sh workstation
```

## Install Home Assistant OS on ward-drake

Script: `setup/ventoy/ward-drake/install-haos.sh`

Copy the `setup/ventoy/ward-drake/` folder onto the Ventoy stick. It does
not need the rest of this repo. Put `haos_generic-x86-64-18.3.img.xz` in
`raw-disc-images/` on the stick. Leave other
`haos_generic-x86-64-*.img.xz` files out of that directory. The script
takes the highest version it finds, and it already has the checksum for
18.3.

Boot the OpenMandriva live image on the NUC. The desktop mounts the
stick at `/media/live/Ventoy`, and that mount is often `noexec`. Open
a root shell and run bash on the script:

```bash
sudo su
bash /media/live/Ventoy/scripts/ward-drake/install-haos.sh
```

That writes the image onto the internal WD SN550 (`WDS500G3X0C`). It
refuses the Ventoy stick, a disk that holds the running system, and any
other model. First boot is the Home Assistant onboarding screen. Set
the hostname to ward-drake. The 2021 config stays on castellan.
