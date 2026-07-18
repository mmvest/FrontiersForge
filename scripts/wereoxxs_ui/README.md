# wereoxxs_ui

A modern replacement for the game's own UI, entirely client side. Nothing here
touches the network, everything runs off what your own client already knows.

## What it draws

**Ability bars.** The game's three hotbars redrawn as modern slots. Bars 1 and 2
are five slots, horizontal or vertical. Bar 3 is four slots, horizontal,
vertical, square (2 by 2), or diamond. Each slot draws the ability's plate and
art the way the game does, an empty slot is a dark translucent square, a slot
on cooldown dims with the seconds over it, and hovering a slot shows the
ability or item details. The selected slot of the selected bar carries a
highlight border and the ability's name in a floating box whose offset is
configurable per bar. Every bar is its own window, so each moves on its own.

**Casting bar.** When you use an ability with a cast time, a bar appears with
the spell's icon on the left, a fill that runs with the cast, the spell's name
centered, and an optional countdown in tenths of a second, like `(2.3s)`. It
disappears when the cast completes. While the Casting bar settings section is
open, the bar shows a looping five second preview so it can be dragged into
place and styled.

**Player frame.** The same style of frame as eqoa_tools, for the local player
alone. Health, power, experience bar, level on the name row, your pet as a
strip under the cell, and your active buffs and debuffs riding the icon strip
where eqoa_tools shows cooldowns.

**Target frame.** Your current target's name, level, and health percent, with
the game's own disposition face so hostile reads at a glance.

**Group frames.** A pane per group member with the health percent the game
itself knows. This is client data only, so there are no exact numbers, no
power, and no positions beyond what the game shares.

**Compass.** The same heading tape as eqoa_tools, with dots for group members
whose positions the client knows.

**Damage meter.** The same meter views as eqoa_tools, current fight, session,
and history, fed from your own combat log alone.

**Chat.** A tabbed chat window with a deep scrollback (the game keeps about 32
lines, this keeps thousands, configurable). The All tab shows everything,
prefixed with the time and the message type. Each chat type gets its own tab,
and every tell conversation gets a tab named after the other person, which
sends replies back to them. Message colors are configurable per type.

## The game's own UI

Each replaced panel can hide the game's original under **Hide the game's own
UI** in settings: the ability bars, the health/power/exp bars, the group panel,
the pet panel, and the compass. Everything is restored when the script is
turned off or ejected.

## Notes

- The casting bar starts from the ability's cooldown beginning, which is the
  one signal the client has that an ability was just used. That signal is the
  server message carrying the cooldown, so it is caught exactly when it
  arrives rather than on the next frame. An interrupted or fizzled cast still
  shows the full bar, since the client is never told.
- Buffs and debuffs show icon and name only. The client is not told their
  remaining durations.
