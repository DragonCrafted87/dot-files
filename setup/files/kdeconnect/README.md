# KDE Connect on GrapheneOS

The workstation role installs the desktop package, Qt5 Multimedia QML
(needed by `kdeconnect-sms` on Rock), `kpeoplevcard` (contact names),
opens LAN ports 1714-1764, and starts `kdeconnect-indicator` from Hyprland.
Pairing is still a phone-side step.

OpenMandriva no longer puts `kdeconnectd` on PATH. The binaries are
`kdeconnect-indicator` (tray), `kdeconnect-app`, `kdeconnect-sms`,
`kdeconnect-cli`, `kdeconnect-handler`, and `kdeconnect-settings`.

Rock's `kdeconnect-sms` is still Qt5 / Kirigami.2. Do not set
`QML_IMPORT_PATH` to `/usr/lib64/qt6/qml` or it mixes Qt6 QtQml with
Qt5 Kirigami and the window fails to load.

## Phone

1. Install **KDE Connect** from F-Droid (or Accrescent / the official APK).
   Do not need Play Services.
1. Join the same Wi-Fi as the workstation. Discovery does not work over
   mobile data.
1. Open KDE Connect on both sides. Request pairing from the phone and
   accept on the desktop (or the other way around).
1. Grant SMS, contacts, notifications, and storage when asked.
1. Device menu → Plugin settings → enable **SMS** / **Send SMS** and
   **Contacts** / **Synchronize contacts**.

KDE Connect does not need to be the default SMS app.

## Contact names in kdeconnect-sms

Bare numbers means the SMS window has no KPeople vCard cache yet.

1. Install `kpeoplevcard` and `kpeople` (this module does that).
1. On the phone, Contacts permission + Contacts plugin on.
1. Wait for sync, or force it:

   ```bash
   rm -rf ~/.local/share/kpeoplevcard
   killall kdeconnect-sms kdeconnect-indicator 2>/dev/null || true
   bash ~/.config/hypr/scripts/start-kdeconnect.sh
   kdeconnect-sms
   ```

1. Confirm vCards landed:

   ```bash
   find ~/.local/share/kpeoplevcard -name '*.vcf' | head
   ```

If that directory stays empty, the phone plugin is not sending contacts
(GrapheneOS Contacts permission or the plugin toggle).

## Desktop

- Tray: `kdeconnect-indicator` (started by
  `config/hypr/scripts/start-kdeconnect.sh`).
- SMS window: `kdeconnect-sms` (needs `qt5-qtmultimedia`).
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
