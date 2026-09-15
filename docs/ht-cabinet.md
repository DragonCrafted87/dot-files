# Home theater cabinet (DIY)

Logged 2026-09-15. Build later. Gear is the Emotiva BasX MC1, BasX A7, and an Intel NUC.
Consoles stay in storage.

## Why not hang fans on the trigger jack

MC1 `TRIG OUT` is a 12 VDC **signal**. A7 `TRIG IN` wants 5–12 V and under 10 mA.
A7 `TRIG OUT` is 12 VDC and can source **up to 120 mA**. That will hold a small
relay coil or MOSFET gate. It will not run 120/140 mm fans.

Chain:

```txt
MC1 TRIG OUT  --3.5mm mono-->  A7 TRIG IN
A7 TRIG OUT   --3.5mm mono-->  fan enable (relay / MOSFET)
12 V PSU (wall) ------------->  fans
```

Do not Y-split the MC1 trigger to feed both the A7 and a relay unless the coil
is under ~30 mA. Prefer the A7 output so the processor jack stays a signal.

## Electrical

### Trigger enable

- 3.5 mm TS (tip = +12 V, sleeve = ground) from A7 `TRIG OUT`
- Isolated 12 V coil relay, ~20–40 mA coil, flyback diode across the coil
- Or logic-level N-MOSFET switching the fan 12 V return, 10 kΩ gate pulldown
- Isolate the jack sleeve from the steel chassis so the trigger ground does not
  become a speaker-return loop

Relay contacts switch the **+12 V from a dedicated brick**, not the trigger line.

### Fan power

- Mean Well GST40A12 or Noctua NV-PS1 (12 V, ≥24 W is plenty)
- Brick lives on the Furman / Isobar in the cabinet, always plugged in
- Fans only spin when the A7 is actually on

### Fans

Two 140 mm PWM, exhaust at the top rear. Intake is passive at the bottom front
and under the plinth. Quiet parts: Noctua NF-A14 PWM or NF-A12x25 PWM if the
plenum is 120 mm.

Two fans at ~800–1000 RPM move enough air for a 7-channel Class A/B amp at
living-room volume. Cap speed with a Noctua NA-FC1 on the PWM line so movie
nights are not a jet.

Optional later: NTC on the A7 top cover into a cheap W1209 so the relay only
closes above ~35 °C. First build is trigger-only.

### Power strip in the box

Furman PST-8 (or the leftover Isobar if the rack one is already bought).
A7 + MC1 + NUC + 12 V brick. Do not share the server-rack circuit.

## Box size

Outside, 3/4 in Baltic birch or oak-veneer ply:

```txt
W  24 in   interior ~22.5 in  (17 in chassis + fingers + cable)
D  24 in   interior ~22.5 in  (A7 is 15.5 in + posts + HDMI)
H  36 in   carcass
   + 5 in  plinth / locking casters   (robot vac needs ≥4 in)
```

Overall ~41 in tall. 24 in deep so the box is not a sail, but the A7 does not
hang off the back.

### Interior stack, bottom up

```txt
0–5 in     plinth. Open front and sides. Intake. Casters + levelers.
5–6 in     vented bottom shelf (1/2 in ply, 1.5 in holes or 1/4 in slots)
6–11 in    A7. Nothing on top of it. 2–3 in clear above the lid.
11–14 in   empty chimney
14–18 in   MC1 on a shelf with a 2 in rear gap for HDMI
18–22 in   NUC on a small right-side platform (short HDMI to the MC1)
22–30 in   spare / Furman tray / IR blaster
30–36 in   plenum. Two 140 mm fans on the rear panel, blowing out.
```

Shelves are 3/4 in ply on pin-adjustable 5 mm holes, 32 mm spacing. Rear 2 in
of every shelf is cut back or slotted so air and cables pass.

## Air path

Cool air in under the plinth and through the slatted lower door.
It hits the A7 first, rises past the MC1, and leaves at the top rear.
Do not put a solid back on the A7 bay. The upper back can be a removable
panel with the two fan cutouts and a 2 in cable slot at the bottom of that
panel.

Front door: slatted oak (IR + air) or smoked tempered glass with a 1 in
bottom and top reveal so the chimney still works. Glass looks cleaner; slats
cool better. If glass, leave the lower 4 in of the door as an open grill.

## Structure

- Sides, top, bottom: 3/4 in ply, dados for the fixed bottom and top plenum
- Back: two removable 1/2 in panels (lower open, upper fan panel)
- Plinth: 5 in box, 3 in locking casters inset so they do not stick out past
  the footprint. Separate screw-down levelers if the floor is out.
- Front: 1/4 in slats on a frame, or 1/4 in tempered glass in a rabbet
- Soft-close overlay hinges. No latch that traps heat if someone forgets it.
- Anti-tip strap to the wall. Loaded A7 + cabinet is enough to walk on carpet.

Finish options (pick one before cutting face frames):

- Warm oak veneer + black satin steel plinth + black glass door or top
- Black-dyed oak or charcoal stain + smoked glass

## Parts to buy first (before wood)

| Qty | Part | Why |
| --- | --- | --- |
| 1 | 3.5 mm TS cables, 3 ft | MC1→A7 and A7→relay |
| 1 | 12 V relay module or IRLZ44 MOSFET + socket | enable |
| 1 | Mean Well 12 V 3 A brick or Noctua NV-PS1 | fan PSU |
| 2 | Noctua NF-A14 PWM | exhaust |
| 1 | Noctua NA-FC1 | speed cap |
| 1 | Noctua NA-YC1 splitter | two fans, one PWM |
| 4 | 3 in locking casters, 100 lb each | roll + vac height |
| 1 | Furman PST-8 | cabinet strip |

Wood and glass after the interior mockup: cardboard shelves in a cheap cube
to confirm HDMI bend radius and speaker-post clearance.

## Do not

- Power fans from the MC1 trigger jack
- Seal the back behind the A7
- Sit the MC1 or NUC on the A7 lid
- Share the 27U server-rack circuit with the A7
- Use cheap 120 V muffin fans. They drone and they need a second relay on mains
