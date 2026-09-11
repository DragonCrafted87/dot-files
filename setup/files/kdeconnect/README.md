# KDE Connect on GrapheneOS

The workstation role installs the desktop package, opens LAN ports
1714-1764, and starts `kdeconnectd` from Hyprland. Pairing is still a
phone-side step.

## Phone

1. Install **KDE Connect** from F-Droid (or Accrescent / the official APK).
   Do not need Play Services.
1. Join the same Wi-Fi as the workstation. Discovery does not work over
   mobile data.
1. Open KDE Connect on both sides. Request pairing from the phone and
   accept on the desktop (or the other way around).
1. Grant SMS, contacts, notifications, and storage when asked.
1. Device menu → Plugin settings → enable **SMS** / **Send SMS**.

KDE Connect does not need to be the default SMS app.

## Desktop

- Tray / `kdeconnect-app` → the paired phone → **SMS Messages**.
- Daemon is started by `config/hypr/scripts/start-kdeconnect.sh`.
- Re-run `~/dot-files/setup/modules/install-kdeconnect.sh` after a role
  reset if the firewall ports vanished.

## GrapheneOS sent-SMS quirk

On recent GrapheneOS, Android marks SMS rows written by a non-default
SMS app as restricted. The text still leaves the phone, but the desktop
may not show the sent copy. Incoming messages are fine.

Enable USB debugging, plug the phone in, then:

```bash
adb shell appops set --uid org.kde.kdeconnect_tp READ_RESTRICTED_MESSAGES allow
adb shell am force-stop org.kde.kdeconnect_tp
```

Use UID mode. Package mode is not enough. `android-tools` is installed
by this module so `adb` is on PATH.

## Remote input (optional)

SMS and notifications do not need it. Mouse/keyboard from the phone on
Hyprland needs a RemoteDesktop portal backend such as
[hypr-kdeconnect-fix](https://github.com/gfhdhytghd/hypr-kdeconnect-fix).
