# Xbox Elite + wireless dongle

`configure-xbox-controller` installs:

- `xone` (DKMS) — official Xbox Wireless Adapter and USB GIP devices
- dongle firmware extracted from Microsoft's Windows driver
- `xpadneo` (DKMS) — Bluetooth, including Elite 2 paddles and profiles
- `steam-devices` udev rules when the package exists

Wired USB often already works with in-tree `xpad`. The **dongle does not**.

## Pair the dongle

1. Unplug Xbox devices before the first install, then reboot after DKMS builds.
2. Plug the adapter into a USB-A port on the machine (avoid cheap hubs).
3. Hold the button on the dongle until its LED blinks.
4. Hold the pair button on the Elite until the Xbox button blinks.
5. Both LEDs go solid when paired.

Check:

```bash
lsusb | grep -i microsoft
lsmod | grep -E 'xone|xpad'
cat /proc/bus/input/devices | grep -A2 -i xbox
```

Steam should show an Xbox controller under Settings → Controller. Enable
Steam Input for titles that need the paddles remapped; leave it off when
the game already understands an Xbox pad.

## Bluetooth instead of the dongle

Use this on the laptop or when the adapter is not plugged in. Pair in
blueman / `bluetoothctl`. `xpadneo` exposes paddles on the default Elite
profile (no profile LED). Profiles copied from the Windows Xbox
Accessories app still apply.

Do not pair the same pad over Bluetooth and the dongle at the same time.

## Skip xpadneo

```bash
XBOX_INSTALL_XPADNEO=0 ~/dot-files/setup/modules/configure-xbox-controller.sh
```
