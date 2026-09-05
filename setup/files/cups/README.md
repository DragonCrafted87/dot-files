# CUPS harvest

Printer queues live in:

- `/etc/cups/printers.conf` — queue name, DeviceURI, options
- `/etc/cups/ppd/` — generated PPD for each queue
- `/etc/cups/classes.conf` — printer classes, if any

On the current workstation:

```bash
sudo ~/dot-files/setup/utility/harvest-cups.sh
```

Commit whatever that writes here. The office/printing module copies it
into `/etc/cups` on workstation and laptop installs.

Do not harvest `cupsd.conf` unless you changed it; the stock file is fine.
