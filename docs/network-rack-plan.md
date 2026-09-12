# Network and rack plan

Logged 2026-09-12. Not purchased yet. mist-dragon stays OpenWrt 24 on two NICs
(Starlink on `eth0`, LAN/trunk on `eth1`). Work-PC isolation waits on managed
switches because that host sits behind two unmanaged switches.

## Cart to save toward

ZyXEL GS1900 pair (US SKUs from the cart snapshot):

| Role | Model | SKU | PoE | List |
| --- | --- | --- | --- | --- |
| Main / rack | GS1900-24HPv2 | GS190024HPV2-USAM01F | 24× PoE+, 170 W | $249.99 |
| Office | GS1900-8HP | GS1900-8HP-USAM03F | 8× PoE+, 70 W | $109.99 |
| | | | **Subtotal** | **$359.98** |

Rack is 31 inches deep. These are short 1U boxes (~8–12 in). Depth is not a constraint.

PoE load today: one OpenWrt AP + two other PDs. A couple more later is still
inside 170 W. A buried driveway magnet is planned as wireless (LoRa/ESP),
not a long PoE homerun.

### OpenWrt on the switches

Preferred if the exact hardware revision is supported. GS1900 is Realtek
RTL838x; LuCI/uci matches the router and AP.

**v2 PoE is the risk.** `realtek-poe` works well on many GS1900 **v1** boards.
v2 / later PSE chips have been flaky across 24.10 and 25.12 (power on by
default, weak per-port control). After purchase, check the ToH for that
revision. If OpenWrt PoE is junk on the unit in hand, keep **stock ZyXEL
firmware** for VLANs + PoE and leave OpenWrt on mist-dragon and the AP only.

Do not flash a random Omada/Netgear PoE switch expecting OpenWrt.

## Why not VLANs on the current dumb switches

Unmanaged switches are one L2 domain. The work PC, printer, AP, and house
hosts can ARP each other no matter what mist-dragon firewalls. 802.1Q through
dumb silicon is unreliable. Isolation starts when the work PC is untagged on
its own VLAN on a managed port.

Guest Wi-Fi does **not** have to wait: second SSID + NAT + client isolation on
the OpenWrt AP, uplink as WAN, no bridge onto `192.168.0.0/16`.

## Target layout

```
Starlink --eth0-- mist-dragon --eth1 802.1Q trunk
                      |
              GS1900-24HPv2 (rack)
                 |              |
           AP + PoE PDs     trunk to office
                                    |
                             GS1900-8HP
                          workstation, work PC,
                          bench machines
```

One trunk from the router is enough. Do not insert an unmanaged switch in
either trunk.

## VLAN sketch (OpenWrt DSA on mist-dragon)

IDs can move; keep them documented here when they are assigned.

| ID | Name | Untagged on | Notes |
| --- | --- | --- | --- |
| 10 | lan | house ports, AP LAN BSS | current `192.168.0.0/16` until a later split |
| 20 | work | office port for the work PC | WAN + printer `.6` only |
| 30 | guest | AP guest BSS (or AP-local NAT until trunk exists) | no LAN |
| 40 | iot | optional later | printer may stay on lan |
| 99 | mgmt | switch/AP/router UIs | do not expose to work/guest |

Printer stays on lan. One forward: `work` → `192.168.0.6` (print ports).
Work PC never shares an untagged port with lan hosts.

## LAN /16 collision (already true)

`192.168.0.1/16` includes `192.168.100.1` (Dishy). Clients ARP that address
on the LAN unless DHCP option 121/249 (`192.168.100.1/32 via 192.168.0.1`)
is pushed. Keep the router `/32` on `wan`. Do not put Dishy in table 100
(PureVPN reply table).

When VLANs land, shrinking lan to a `/24` (or several) is the durable fix.

## Rack PCs (two old towers)

Move two tower-format machines into the rack with large Noctua coolers.

Noctua NH-D15 / D15 G2 / similar dual-tower coolers are ~165–168 mm tall.
Motherboard tray + cooler must fit the case interior height:

| Rack units | Height | Dual-tower Noctua |
| --- | --- | --- |
| 4U | 177.8 mm | Tight. Many 4U chassis advertise ~160–165 mm CPU clearance. Measure the **exact** cooler + board + tray before buying 4U. |
| 5U | 222.3 mm | Comfortable for D15-class sinks and a 25 mm fan swap. |

Plan on **5U** unless a specific 4U model lists clearance above the cooler
height + ~10 mm. 31" rail depth is enough for ATX rack trays.

Look at 4U/5U **rackmount server cases** with a standard ATX tray (Silverstone
RM / CS, Rosewill RSV, Chenbro, iStarUSA), not a 1U pizza box. Need:

- ATX / eATX if the donor boards need it
- Front intake, rear exhaust; Noctua fans can replace stock if the mounts match
- USB / power / reset on the front
- PCI slot opening if a NIC or HBA moves with the board

Two chassis → 8U or 10U of rail plus the 1U switch and whatever already lives
in the rack. Leave blank U for airflow over the Noctua stacks.

## Do not do until the switches exist

- Work-PC firewall-as-VLAN on the shared dumb fabric
- `redirect-gateway` / full-tunnel PureVPN on mist-dragon
- Putting `tun0` back in the wan zone
- Enabling `pbr`

## After the switches arrive

1. Confirm GS1900 hardware version vs OpenWrt ToH; flash or keep stock.
2. Cable router trunk and office trunk only. Leave house hosts on lan untagged.
3. One office port untagged VLAN 20 for the work PC; test isolation.
4. Move guest off AP-local NAT onto VLAN 30 when the AP trunk is clean.
5. Optional: split `192.168.0.0/16` into per-VLAN prefixes.
