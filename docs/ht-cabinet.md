# Home theater cabinet (DIY)

Logged 2026-09-15. Gear: Emotiva BasX MC1, BasX A7, Intel NUC. Consoles stay in storage.
This box is also the stain testbed for the room bookcases.

## Locked choices

- Oak carcass and door. Stain samples on offcuts before the bookcases.
- Front door: slats or a crosshatch lattice. Air + IR both go through it.
- Back: same language. One **port per bay**, not a solid panel.
- Each port: Noctua(s) in the upper half, open cable slot under the fans.
- Fan enable: clicky 12 V relay off A7 `TRIG OUT`. Fine. The A7 already clunks.

## Why not hang fans on the trigger jack

MC1 `TRIG OUT` is a 12 VDC **signal**. A7 `TRIG IN` wants 5–12 V and under 10 mA.
A7 `TRIG OUT` is 12 VDC and can source **up to 120 mA**. That holds a relay coil.
It will not run fans.

```txt
MC1 TRIG OUT  --3.5mm TS-->  A7 TRIG IN
A7 TRIG OUT   --3.5mm TS-->  12 V relay coil
12 V brick    --relay NO-->  all fan +12 V rails
```

Relay module with a built-in flyback diode. Isolate the 3.5 mm sleeve from the
steel chassis so trigger ground does not become a speaker-return loop. Contacts
switch the brick, never the trigger line.

## Rear ports

The back is a set of removable 1/2 in oak frames, one per shelf bay, hung on
figure-8 fasteners or inset barrel bolts so a bay can come off without moving
the cabinet. Each frame is a port:

```txt
+----------------------------------+
|  fan     fan     (or slat fill)  |  ~5.5 in  (140 mm + gasket)
+----------------------------------+
|                                  |  ~2.5 in  cable trough
|   HDMI / RCA / IEC / speaker     |
+----------------------------------+
```

Interior width ~22.5 in, so a bay can take two 140 mm fans side by side and
still have ~3 in of slat or a pull handle in the middle. Cable trough is a
full-width slot with a rounded lip and a felt or rubber edge so HDMI jackets
do not saw on plywood.

### Which bays get fans

| Bay | Gear | Rear |
| --- | --- | --- |
| 1 bottom | A7 | two NF-A14 PWM, exhaust out. This is the heat source. |
| 2 | empty chimney | slat only, no fan. Lets the A7 plume keep rising. |
| 3 | MC1 | one NF-A12x25 PWM, low RPM. HDMI farm lives in this trough. |
| 4 | NUC + brick | one NF-A9 or A12, mostly to dump NUC heat out the back. |
| 5 spare | Furman | slat + trough, no fan unless something hot lands here. |

All powered fans sit on one 12 V rail behind the relay. One NA-FC1 on the PWM
line caps every fan at the same quiet speed. First-pass target ~800–1000 RPM.

Do not put a fan in the empty bay above the A7. That would short-circuit the
chimney and pull hot air out before it has crossed the amp lid.

## Air path

```txt
front lattice + plinth  -->  A7 bay  -->  rises  -->  upper bays
                               |
                               +--> A7 port fans (main exhaust)
upper bays also leak out their own port fans / slats
```

Intake is the door lattice and the open plinth. Exhaust is the rear fans,
A7 bay doing most of the work. Leave ~2 in of shelf setback at the rear of
every shelf so air and cables can turn the corner into the trough.

## Lattice

Two patterns, same reveal. Pick after a sample door:

- Horizontal slats, 1/2 in oak × 1/2 in gap. Fast to build, good airflow.
- Crosshatch / diamond, 1/2 in strips on a 1 in grid. Matches bookcases better.

Keep the open area ≥40 % on the door or the A7 will cook with the door shut.
Same rule on any rear port that does not have a fan — slat it, do not plate it.

Door is an overlay frame on soft-close hinges. No catch that someone can leave
sealed. IR remotes see through 1/2 in gaps; if a remote is fussy, park a cheap
IR repeater eye behind the lattice at MC1 height.

## Box size

3/4 in Baltic birch core, oak veneer face, or solid-sawn oak face frames on ply.

```txt
W  24 in   interior ~22.5 in
D  24 in   interior ~22.5 in   (A7 is 15.5 in + posts + HDMI)
H  36 in   carcass
   + 5 in  plinth / locking casters   (robot vac needs ≥4 in)
```

### Interior stack, bottom up

```txt
0–5 in     plinth. Open front and sides. Casters + levelers.
5–6 in     vented floor (slots, not a solid slab)
6–11 in    A7. Nothing on the lid. 2–3 in clear above it.
11–14 in   empty chimney. Slat rear, no fan.
14–18 in   MC1. Rear trough is the HDMI / trigger / IR mess.
18–22 in   NUC on a right-side platform, short HDMI down to the MC1.
22–30 in   Furman + 12 V brick + relay module.
30–36 in   unused / bookcase-stain sample shelf
```

Shelves: 3/4 in ply, 5 mm pins on 32 mm centers. Rear 2 in of each shelf cut
back or slotted.

## Structure

- Sides, top, bottom: 3/4 in ply, dados for the fixed floor and top
- Back: one removable port frame per bay, not a single sheet
- Plinth: 5 in box, 3 in locking casters inset. Separate levelers if the floor is out
- Anti-tip strap to the wall. Loaded A7 plus oak is enough to walk on carpet
- Finish: raw first. Brush 3–4 oak stains on the inside of the spare bay and
  on door offcuts. Live with them under room light before the bookcases.

## Parts to buy first (before wood)

| Qty | Part | Why |
| --- | --- | --- |
| 2 | 3.5 mm TS cables, 3 ft | MC1→A7 and A7→relay |
| 1 | 12 V relay module, opto-isolated, flyback on board | enable |
| 1 | Mean Well GST40A12 or Noctua NV-PS1 | fan PSU, ≥24 W |
| 2 | Noctua NF-A14 PWM | A7 port |
| 1 | Noctua NF-A12x25 PWM | MC1 port |
| 1 | Noctua NF-A9 PWM or second A12 | NUC port |
| 1 | Noctua NA-FC1 | speed cap |
| 2 | Noctua NA-YC1 splitters | one PWM tree |
| 4 | 3 in locking casters, 100 lb each | roll + vac height |
| 1 | Furman PST-8 | cabinet strip |

Four fans at idle are ~4–6 W. The 24 W brick is not the limit; noise is.

## Do not

- Power fans from the MC1 trigger jack
- Plate the back behind the A7
- Fan the empty bay above the A7
- Sit the MC1 or NUC on the A7 lid
- Share the 27U server-rack circuit with the A7
- Use 120 V muffin fans
