# Reinstall: attach LVM home from the live ISO

`runewyrm` keeps `/` on the installer disk and `/home` on LVM:

```text
VG  lv-home
LV  home                 /dev/lv-home/home   ~3.64 TiB
PVs /dev/nvme1n1         /dev/nvme2n1
```

After wiping and reinstalling only the root disk, boot the OpenMandriva
live image from Ventoy and run:

```bash
sudo bash /path/on/ventoy/reinstall-attach-home.sh
```

Copy `setup/utility/reinstall-attach-home.sh` onto the stick. It does not
need the rest of this repo.

The script:

1. Activates `lv-home`
1. Finds the newly installed root (skips the two home PVs)
1. Mounts that root at `/mnt/newroot`
1. Moves an installer-created `/home` aside
1. Mounts `/dev/lv-home/home` on `/mnt/newroot/home`
1. Writes a UUID `/home` line into the installed `fstab`
1. Disables and masks SDDM on the installed root
1. Installs `git` into the installed root when dnf can reach it

Then reboot into the installed disk. `~/dot-files` is already on the LVM
volume. `role.sh` installs `git` first if the chroot step could not.

```bash
~/dot-files/setup/role.sh workstation
```

Override names if a box differs:

```bash
sudo HOME_VG=lv-home HOME_LV=home ROOT_DEV=/dev/nvme0n1p2 \
    bash reinstall-attach-home.sh
```
