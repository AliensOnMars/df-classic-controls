# Classic Controls for Dwarf Fortress

Brings the keyboard-driven play of pre-Steam Dwarf Fortress (0.47.05) to the
Steam version, as a [DFHack](https://github.com/DFHack/dfhack) overlay. It
does not edit `interface.txt`: it catches key presses before the game sees
them and either turns them into the game's own actions or works the new
screens' buttons for you.

While a fort is on screen it does three things:

- **The old keys work again.** `d` designates, `b` builds, `p` places
  stockpiles, `i` zones, `q` `k` `v` `t` put a cursor on the map, `s` is
  squads, `h` hauling, `j` `u` `n` `o` `z` open the lists, and so on, with
  the 0.47.05 letters inside each menu.
- **The new screens work without the mouse.** Lists move with `-` and `=` (or
  the arrows, Shift for ten), `Enter` chooses, `Esc` backs out one step, and
  each screen's buttons are on letters. This covers designations, building,
  workshops and their tasks, stockpiles with their settings and links, zones
  and locations, hauling routes and minecarts, the whole military side, work
  orders, nobles, trade, the info window's tabs, a creature's sheet, and the
  name builder.
- **A key list is on screen for whatever is open** (yellow title; top left on
  the map, under the minimap on the full-screen windows), so nothing has to be
  memorised. The selected row of a list is marked with a yellow arrow.

Where the new game has no equivalent of an old screen, the overlay supplies
one of its own: the `r` combat reports list, the squad list on a creature's
sheet, and classic per-dwarf labors (see
[docs/labors-and-therapist.md](docs/labors-and-therapist.md)). Anything other
than the bare map pauses the game, as it used to. The mouse keeps working
throughout and can be mixed in freely.

## Requirements

- Dwarf Fortress, the Steam release. Built and tested on **53.17**.
- **DFHack 53.17-r1** (on Steam: the "DFHack" app).
- Tested with the premium graphics, in English, at interface grids from
  128x48 to 240x90. Classic ASCII graphics and other languages have not been
  tried.

A game update can move the buttons the overlay presses for you. If a key
stops doing anything after an update, the mouse still works, and the overlay
can be switched off (below) until a new version is out.

## Installing

### From the Steam Workshop

1. Install DFHack (free on the Steam store) and subscribe to Classic Controls.
2. Start the game with DFHack running (on Steam, launch DFHack). If pressing
   `d` in a fort shows no key list at the top left, DFHack is not running.
3. That's all: the mod does not need adding to a world. DFHack loads it in
   every fort, old or new.

### By hand

Download `classic_controls-<version>.zip` from the releases and unpack it into
the game's `mods` folder, so that you have `mods\classic_controls\info.txt`.
The Steam version keeps that folder in
`%APPDATA%\Bay 12 Games\Dwarf Fortress\mods` (in the game's own folder only
in portable mode). Then start the game with DFHack as above.

### From the source

Add this line to the game's `dfhack-config\script-paths.txt`, pointing at the
`scripts` folder of your copy of this repository:

    +C:/path/to/df-classic-controls/scripts

The `+` puts it ahead of any installed copy. Changes take effect on the next
start, or at once with the reload command in
[docs/development.md](docs/development.md).

## Getting started

`?` on the map shows the main menu of top-level keys in the old menu's order,
and hides it again. The title screen, world generation, embark and adventure
mode are untouched: the keys start once a fort's map is up.

A new fort, first steps:

1. Embark as normal. When the map appears the game is paused; Space pauses
   and unpauses, as it always did.
2. Look around: arrows scroll (Shift for ten), `<` `>` change level, `k`
   gives a cursor that names what is on a tile.
3. Dig: `d` opens the old designation menu (it starts on mine; `t` chop,
   `h` channel, `i` `u` `j` stairs...). Move the cursor, `Enter` on one
   corner, `Enter` on the other. `Esc` leaves.
4. Stockpiles: `p`, then the type's letter (`f` food, `w` wood, `s`
   stone...), then `Enter` on two corners.
5. Workshops and furniture: `b`, then the old letters (`w` for the workshop
   list, `b` bed, `d` door, `t` table...). `Enter` places it, then choose the
   material with `-` `=` and `Enter`.
6. Give a workshop work: `q` with the cursor near it, `a` to add a task, and
   the task's old letter. For standing production use the manager instead:
   `o`, then `q` for a new order.
7. Zones: `i`, the type's letter (`m` meeting area, `n` pasture, `b`
   bedroom...), then two corners. A zone's panel has its own keys (`a`
   assign, `l` location).
8. Dwarves: `u` lists them, `v` looks at the nearest one, and the info
   window's Labor tab (`y`) has the work details. Inside the info window the
   same letters switch tabs.
9. Nobles `n` (a manager and a bookkeeper early on), squads `s` (`C` creates
   one), hauling routes `h`, trade with `q` on the depot once a caravan is in.

Everything those steps open shows its own key list. The full reference is in
[docs/keys.md](docs/keys.md).

## Turning it off

In the DFHack console:

    overlay disable classic-controls.keys
    overlay enable classic-controls.keys

## Known limits

- This version of the game marks whole stacks and has no item view on the
  trade screen, so the old item-by-item trading keys have nothing to work on.
- On narrow interface grids (under about 140 columns) a work order's details
  button is covered by the game's own label, and the top-left key list can
  overlap the sheets the game draws on the right.
- The world map (`c`) cannot be zoomed: its scale is fixed inside the game.
- `z` opens stocks only; the old combined status screen has no equivalent.
- A few corners are still mouse-only (the image chooser for engravings and
  statues, the dye list of a dye task). The full list, and what has and has
  not been tested, is in [docs/development.md](docs/development.md).

## Documentation

- [docs/keys.md](docs/keys.md): every key, screen by screen
- [docs/labors-and-therapist.md](docs/labors-and-therapist.md): why every dwarf
  does every labor in this version, classic per-dwarf labors, and getting
  Dwarf Therapist to read the current game
- [docs/development.md](docs/development.md): how it works, working on it
  against a running game, test notes
- [CHANGELOG.md](CHANGELOG.md)

## Licence

zlib; see [LICENSE](LICENSE). Dwarf Fortress is by Bay 12 Games; DFHack is by
the DFHack team. This project is not affiliated with either.
