# Reinstall: attach LVM home from the live ISO

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
