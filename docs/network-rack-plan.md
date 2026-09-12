# Network and rack plan

Logged 2026-09-12, updated same day. Not all of this is purchased yet.
mist-dragon stays OpenWrt 24 on two NICs (Starlink on `eth0`, LAN/trunk on
`eth1`). Work-PC isolation waits on managed switches because that host sits
behind two unmanaged switches.

## Existing rack

Open-frame 4-post, **27U**, ~**31 in** rail-to-rail (Amazon `B076VQ8WZQ`).
On **casters**, not lagged down. No plan to enclose it. Square holes + cage
nuts. Ambient air is free; still leave 1U gaps so 1U gear is not exhausting
into the next lid.

| Position | What |
| --- | --- |
| Bottom | RROYJJ 4U 24-bay hot-swap (`B095YMXW1K`, ~650 mm / 25.6 in deep) — main data server |
| Top | HP ProLiant DL360p Gen8 1U |

Do not mix rail kits between the RROYJJ, the DL360p, and the future RackChoice
5U boxes. Each chassis has its own slide pattern.

### Target U stack (bottom up)

```
4U   RROYJJ 24-bay
1U   empty / cable
5U   tower A (RackChoice)
1U   empty
5U   tower B (RackChoice)
1U   empty
1U   GS1900-24HPv2 (later)
1U   empty
1U   DL360p Gen8
1U   empty under the top of the frame
```

About 21U used, ~6U spare. Do not pack the two 5U cases against each other.

### DIY crash console (no front-U KVM)

Monitor and keyboard are only for when SSH is dead. Do not buy a 2U/4U rack
KVM; do not cantilever a VESA arm off one upright on a wheeled frame.

- **Monitor:** reuse the old VESA arm / plate on the **top crossbar**, preferably
  the **rear** bar so the panel hangs over the rack, not past the front wheels.
  Two fasteners into the bar (sister a ply or 80/20 pad if the tube is thin).
  Tilt the screen down. Cable down a rear post, not across the 19" column.
- **Keyboard:** carpentry shelf spanning the **two side posts** on one side
  (front and rear uprights). Fold-down / drop-leaf with the hinge inside the
  wheel rectangle. Mouse on the same leaf. No extra wing past the casters.
- Lock the wheels before the leaf is down. The 24-bay stays at the bottom as
  ballast. Do not block RROYJJ intakes or Gen8 exhaust.

Neck height is acceptable because this is break-glass, not a daily desk.

## Cart / save list

### Switches

ZyXEL GS1900 pair (US cart snapshot):

| Role | Model | SKU | PoE | List |
| --- | --- | --- | --- | --- |
| Main / rack | GS1900-24HPv2 | GS190024HPV2-USAM01F | 24× PoE+, 170 W | $249.99 |
| Office | GS1900-8HP | GS1900-8HP-USAM03F | 8× PoE+, 70 W | $109.99 |
| | | | **Subtotal** | **$359.98** |

PoE today: one OpenWrt AP + two other PDs. A couple more later still fits
170 W. Buried driveway magnet stays wireless (LoRa/ESP), not a PoE homerun.

### Tower-to-rack cases and rails

| Item | ASIN / SKU | Notes |
| --- | --- | --- |
| 2× RackChoice 5U ATX/EATX chassis | `B0D2ZT3QDZ` | 360 mm rad cage unused if staying on air; D15-class Noctua needs ≥170 mm CPU height (5U is the point) |
| 2× Rosewill RSV-RL26HV2 slides | `B0GZS9RJNC` | 26–39.4 in, 2U–5U chassis slides. Matches 31 in 4-post. |

Do **not** buy the RackChoice **20 in** optional rail (`B0DJPC7V3F`). Too short
for this rack. Skip StarTech UNIRAILS1UB (those are L-brackets, not chassis
slides).

Noctua NH-D15 / D15 G2 ~165–168 mm. 4U (177.8 mm) is tight after the tray;
5U (222 mm) is the safe pick.

### DL360p Gen8 PSUs (replace both)

Dead brick label: **499250-201**, 460 W on the fan. That is HP **Common Slot
Gold** 460 W (kit **503296-B21**; also seen as `499250-101` / `511777-001` /
`HSTNS-PL14`).

Replace **both** modules. The survivor lived in the same hot bay. Buy two
used-tested **460 W CS Gold**, same family. Do not mix Gold + Platinum in the
two slots.

Platinum (~94%) vs Gold (~92%) does **not** pay back here. At ~150 W output the
gap is ~3 W, a few dollars a year. This is a reliability buy, not an efficiency
buy. Only take Platinum (`739252-B21`) if it is the same price as Gold that day.

## OpenWrt on the switches

Preferred if the exact hardware revision is supported. GS1900 is Realtek
RTL838x; LuCI/uci matches the router and AP.

**v2 PoE is the risk.** `realtek-poe` works well on many GS1900 **v1** boards.
v2 / later PSE chips have been flaky across 24.10 and 25.12. After purchase,
check the ToH for that revision. If OpenWrt PoE is junk on the unit in hand,
keep **stock ZyXEL firmware** for VLANs + PoE and leave OpenWrt on mist-dragon
and the AP only.

Do not flash a random Omada/Netgear PoE switch expecting OpenWrt.

## Why not VLANs on the current dumb switches

Unmanaged switches are one L2 domain. The work PC, printer, AP, and house
hosts can ARP each other no matter what mist-dragon firewalls. 802.1Q through
dumb silicon is unreliable. Isolation starts when the work PC is untagged on
its own VLAN on a managed port.

Guest Wi-Fi does **not** have to wait: second SSID + NAT + client isolation on
the OpenWrt AP, uplink as WAN, no bridge onto `192.168.0.0/16`.

## Target network layout

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

`dishy.starlink.com` is a Unbound `local-data` A to `192.168.100.1` plus
dnsmasq `address=/dishy.starlink.com/192.168.100.1`. Do not add a second
`local=` line for dishy; OpenWrt concatenates list `local` onto one invalid
`local=` and dnsmasq will not start.

When VLANs land, shrinking lan to a `/24` (or several) is the durable fix.

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
