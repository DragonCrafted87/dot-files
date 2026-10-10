# Volume overlay requirements

Normative rules for the hyprdesk volume overlay. Display and sink routing
stay in [`REQUIREMENTS.md`](REQUIREMENTS.md). The start menu is
[`START-MENU-REQUIREMENTS.md`](START-MENU-REQUIREMENTS.md).

Keywords follow RFC 2119: MUST, MUST NOT, SHOULD, MAY.

## Scope

hyprdesk draws this overlay when the default PipeWire sink changes level
or mute. The layer namespace is `hyprdesk-osd`. Keyboard volume keys still
call `wpctl`. The menu slider follows the start menu document and uses
the same step and the same percent text.

## One overlay

1. hyprdesk MUST keep a single overlay window and update it in place.
1. A second hyprdesk process MUST NOT bind the desk socket, and it MUST
   NOT open another overlay.
1. The overlay MUST anchor to the top left with a 24px margin, on the
   overlay layer, and it MUST NOT take keyboard focus.
1. The overlay MUST stay up for 5 seconds after the last sink change,
   then hide. A new change MUST restart that timer.
1. A change the menu slider makes itself MUST NOT pop the overlay.

## Label

1. The percent MUST be centered at the top of the panel.
1. A muted sink, or a sink hyprdesk cannot read, MUST show `MUTE`.
1. Otherwise the label MUST be the sink level snapped to the 2.5% step,
   from `0%` through `150%`.
1. A step that is not a whole percent MUST keep one decimal. `72.5%`
   MUST stay `72.5%`. Whole percents MUST omit the decimal (`50%`,
   `100%`, `150%`).
1. The label MUST stay on one line. `112.5%` and `150%` MUST be fully
   visible.

## Level bar

1. The track MUST be the same width as the label.
1. The colored fill MUST sit inside the track with a visible margin on
   every side. That margin MUST remain when the level is `150%`.
1. Fill height MUST follow the snapped level divided by `1.5`. Mute MUST
   leave the track empty.
1. Above `100%`, the label, the panel border, and the fill MUST use the
   overdrive red. At `100%` and below they MUST use the palette text,
   border, and accent.

## Steps

1. The desk step MUST be 2.5 percentage points. The maximum MUST be
   `150%`.
1. `wpctl get-volume` prints two decimal places, so `0.725` comes back as
   `0.73`. The label, the fill, and the overdrive color MUST use the
   2.5% step recovered from that print.

## Panel

1. The panel SHOULD be about three quarters of a 96px width when the
   widest label still fits, with a margin between the track and the
   panel edge.
1. If that width would clip a label, the panel MUST grow until the label
   fits.
1. Colors come from `hyprtoolkit.conf`. The panel MUST NOT add a second
   window opacity on top of the palette background alpha.
