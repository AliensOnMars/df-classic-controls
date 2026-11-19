# Keys

The full reference. Every screen also shows its own keys in a yellow-titled
list while it is open, so none of this has to be learned up front.


On the map (bare, or with a unit / building / item panel open):

| Key | Does |
|---|---|
| `k` | Look: move a cursor, see what is on the tile, `Enter` opens its panel |
| `q` | Query: cursor snaps to the nearest building and opens its panel |
| `t` | Building items: the same panel, with `-` `=` stepping through what the building is made of and holds |
| `v` | View unit: cursor snaps to the nearest creature and opens its panel |
| `d` | Designations (starts on mine) |
| `i` `j` `a` `w` `l` | Zones, job list, announcements, burrows, locations |
| `s` / `m` | Squads |
| `o`, or `j` then `m` | Work orders (the old manager) |
| `n` | Nobles and administrators |
| `u` | Creatures (the old unit list). In that window the same letters switch tabs: `u` `j` `l` `y` `o` (or `m`) `n` `L` `J` |
| `r` | Reports: every creature's combat, sparring and hunting reports, the latest first |
| `c` `z` `L` `J` | World, stocks, artifacts, justice |
| `h` | Hauling: minecart routes, their stops, conditions and links, all on keys (below). The game has it on Shift+h, where "hot keys" takes the key instead |
| `?` | Show or hide the main menu: the list of these top-level keys, in the old menu's order, over the corner of the map. It gives way to whatever is opened and comes back on the bare map. The choice is remembered between sessions (`dfhack-config\classic-controls.json`) |

Everywhere a cursor is on the map (`k` / `q` / `v`, designations, building
placement, stockpiles, zones):

- Arrows move one tile, Shift+arrow ten.
- `<` and `>` change level, on the bare map as well. `-` and `=` never do.
- `-` and `=` (or `+`) move up and down whatever list is in front of you.
- `Esc` backs out one step.

Anything other than the bare map pauses the game, as it used to: `k`, `q`,
`t` and `v`, designating, the build, stockpile and zone menus, squads, the
info window and its tabs, announcements, reports, and a creature's or
building's panel however it was opened. When the last of them is closed the
game is set going again if it was running when the first was opened; if it
was already paused it stays paused. `Space` still works in between, and a
game unpaused that way is left running.

In `k`, `-` and `=` step through the creatures, building and items on the
tile, and `Enter` opens the selected one. The last line names the tile with
what it is made of: "limonite wall" where the game's own caption says "vein
wall", "granite cavern floor" for an unsmoothed "stone floor" underground,
"constructed granite floor", and the kind of tree or plant ("tower-cap:
trunk pillar").

In `t`, and in `q` on anything that is not a workshop (a coffin, a door),
`-` and `=` step through the building's items. `Enter` views the selected
item and `Esc` comes back to the building; `f` forbids it, `d` marks it for
dumping.

Workshop panel, Tasks tab (opened with `q` or the mouse):

| Key | Does |
|---|---|
| `a` | Add task: a list with the 0.47.05 hotkeys (`a` `b` at a carpenter queues a bed). `-` `=` and `Enter` for tasks that never had a key; submenus work the same way. The list opens on the task added last (at that kind of workshop), through its submenus too, so `a` `Enter` adds another of the same. `Esc` steps back out of a submenu, then out of the list |
| `-` `=` | Select a task (marked in yellow on the game's list) |
| `r` `s` `n` `c` | Repeat, suspend, do now, cancel the selected task |
| `d` | The selected task's details (its material and the like), where it has any: see "A task's or work order's details" below |
| `x` | Remove the building, as below |

`x` on any building looked at with `q` or `t` (or whose panel was opened with
the mouse) marks it for removal, as it used to; `x` again calls the removal
off. On a building that has not been started it cancels the construction at
once. The key list shows which of the three `x` will do. As in the game,
marking a workshop for removal drops its queued tasks, and calling the
removal off does not bring them back.

`s` on a building that is still being built (a wall, a bed, a workshop
waiting for its builder) suspends its construction, and `s` again lets it go
on: the same switch as the game's "Suspend construction" button. The key
list says which it will do. On a finished workshop `s` is still the selected
task's suspend.

`q` on a farm plot (or its panel opened with the mouse), with the old farm
keys:

- `a` `b` `c` `d` show spring, summer, autumn or winter. The panel opens on
  the season it is now.
- `-` `=` select a crop in the game's list (it scrolls on past the bottom,
  and stops at the last crop); the selection starts on the season's current
  crop. `Enter` plants it for that season; `z` leaves the plot fallow.
- `f` switches fertilizing on or off, `s` fertilizing every season.
- `x` removes the plot, `Esc` closes it.
- The key list shows the season and its crop.

After `d`, the old designation menu:

- `d` mine, `h` channel, `i`/`u`/`j` stairs, `r` ramp, `z` remove stairs/ramps
- `t` chop, `p` gather plants, `s` smooth, `e` engrave, `a` fortify, `T` track
- `x` remove designation
- `b` item properties, then `c` claim, `f` forbid, `d`/`D` dump, `m`/`M` melt, `h`/`H` hide
- `o` traffic, then `h` high, `n` normal, `l` low, `r` restricted
- `-` `=` lower and raise the designation priority
- The tool in use is picked out in yellow in the list.
- There is one cursor, as there used to be: changing tool leaves it where it
  is, a designation starts where `k` / `q` / `v` last had it (if that is
  still in view), and those start where the designation left it.
- A new designation replaces what was designated on the tile before. The
  game already does this between mining, channels and ramps; here it also
  holds between digging and smoothing (which the game stacks on one tile),
  engraving and tracks. A tile the new tool does not apply to keeps what it
  had: a tree inside a mining box keeps its felling order. This applies to
  boxes set with `Enter`, not ones drawn with the mouse. (Stairs need a box
  two levels deep to designate anything; that is the game's rule.)
- That includes work a dwarf has already taken on. Once a miner picks up a
  dig order the game removes the designation from the tile and keeps only
  the job, and it refuses to designate anything over a tile with a job: so
  a channel box over taken dig orders used to do nothing, and the miners dug
  them out flat. Now the jobs in the box are turned back into designations
  first, so the new one replaces them; a tile the new tool does not apply
  to gets its old order back (the game re-makes the job). The dwarf who had
  the job loses it. Erasing (`x`) already cleared taken jobs in the game.

After `b`, the old build list, shown on screen with its keys while the menu is open:

- Same keys and order as 0.47.05: `b` bed, `c` seat, `d` door, `t` table, `f` cabinet, `h` container, `p` farm plot, `l` well, `D` trade depot, and so on.
- Two buildings the old game did not have, on new keys: `C` then `W` is a reinforced wall, and `i` then `t` a bolt thrower.
- Submenus: `w` workshops, `e` furnaces, `C` wall/floor/stairs/track, `T` traps/levers, `M` machine components, `i` siege engines.
- Workshops defined in the raws (stock or modded) keep the key the raws give them, inside `w`.
- Placing: arrows move, `Enter` places (twice for the two corners of walls, floors, roads and farm plots). The key list stands to the right of the game's own placement panel, so its material choice ("Select material after placement", "Use closest material"), "Keep building after placement" and its warnings stay in view; the same on the materials list.
- While a wall, floor, road or farm plot is being sized (after the first `Enter`), the area it will cover is marked on the map: green where the tile looks free, red where something is in the way (rock, another building, unexplored ground). The game draws this only for a box dragged with the mouse. The marks are a guide; the game decides when the second `Enter` is pressed. `Esc` drops the first corner (and the marks) and stays in placement.
- Workshops, furnaces, the trade depot, siege engines, pumps, water wheels and other fixed-size buildings: the game previews them at the mouse pointer, not at the keyboard cursor where `Enter` places them. The overlay marks the building's footprint at the keyboard cursor (3×3 round a workshop's centre, 5×5 for the depot, and so on), green and red as above, so it can be lined up with the keys. The game's own picture still follows the mouse; park the pointer off the map to hide it. Tried with a carpenter's workshop (3×3) and the trade depot (5×5), which went red exactly where it overlapped two workshops.
- The cursor is shared with designations and `k` / `q` / `v`: a building's placement starts where the cursor was left last (if that is still in view), so one bed after another starts beside the last.
- Choosing material: `+` `-` or arrows select, `Enter` uses one, `Shift+Enter` uses that material for everything needed.
- `Esc` goes back one step (to the build list) instead of dropping to the map; from the list it closes the menu.

The game's own category buttons along the bottom still show its new keys; the list at the top left is the one the keyboard follows.

After `p`, stockpiles:

- Type keys as in 0.47.05: `a` animal, `f` food, `u` furniture, `y` graveyard, `r` refuse, `s` stone, `w` wood, `e` gem, `b` bar/block, `h` cloth, `l` leather, `z` ammo, `n` coins, `g` finished goods, `p` weapons, `d` armor, `S` sheet, `c`/`t` custom settings. `A` (all) is new.
- Arrows move the cursor; `Enter` sets one corner, `Enter` again the other. The pile gets the chosen type and you stay in placement for the next one.
- With no type chosen, the game's stockpile panel opens after placing and the same type keys set it there.
- `x` removes the stockpile under the cursor (the whole pile, not just the tiles in a rectangle as it used to).
- `q` on a stockpile: `E` `R` max barrels, `C` `V` max bins, `w` `W` wheelbarrows, `s` settings, `x` removes the stockpile (at once, as `p` then `x` did), and the links below.
- Links: `g` give to and `t` take from start a link: put the cursor on the other stockpile or workshop and press `Enter` (`Esc` cancels). `d` lists the links, where `-` `=` select and `d` deletes one; `g` and `t` work there too. `a` switches the stockpile between taking from anywhere and from its links only.
- Settings (`s`), the old three-column screen. The key list sits under the minimap.
  - Left / Right move between the columns (categories, sub-categories, items); Up / Down or `-` `=` move within one, Shift for ten. Moving shows that category's or sub-category's contents without changing anything.
  - Corpses has no sub-categories (the middle column is empty), so Left / Right go straight between it and its list of creatures. Until 2026-11-18 the keys stopped working altogether once the selection reached Corpses: the overlay found the columns by their three "All / None" headings, and that category has only two.
  - `Enter` toggles the highlighted item (or a yes / no sub-category); `p` permits it and `f` forbids it.
  - `e` enables everything in the selected category and `d` disables it; `a` allows and `b` blocks every item in the list on the right.
  - `/` filters the item list: type, then `Enter`. `/` again and Backspace to clear it.
  - `u` switches plant / animal materials on or off, `j` the rest. `A` makes the stockpile take everything and `N` nothing. `Esc` goes back to the stockpile.

`q` on the trade depot: `r` requests a trader at the depot or calls that off, and `b` switches between the broker and anyone. `t` (trade) and `g` (move goods to the depot) open those screens; the game only offers them while merchants are at the depot. In both, the key list sits under the minimap.

Trade (`t`), with the old keys:

- With more than one caravan in, pick one first: `-` `=` and `Enter`.
- Up / Down (or `-` `=`) move through a side's list, Shift for ten; Left / Right switch between the merchants' goods and the fort's.
- `Enter` marks or unmarks the item. On a category heading it marks or unmarks the whole category, and `c` folds or unfolds it.
- `t` trade, `o` offer the marked goods as a gift, `s` seize the marked goods. DFHack asks before a trade or a seizure; `Enter` answers yes and `Esc` no.
- `m` marks everything on the current side and `u` unmarks it. `/` searches the current side: type, then `Enter`.
- `Esc` leaves (it closes the depot's panel too).

Move goods (`g`):

- Kinds of item on the left, the selected kind's items on the right; Left / Right switch between the two, Up / Down (or `-` `=`) move, Shift for ten.
- `Enter` ticks or unticks an item to be brought to the depot (on a group heading, the whole group). The hauling starts when the screen is closed.
- `s` (or `/`) searches: type, then `Enter`. `m` leaves out what the merchants will not take. `d` switches between sorting by distance and by value. `a` ticks everything shown.
- `Esc` leaves.

A zone's panel (`q` on a zone, or a zone opened with the mouse, from the zones menu or from the Places list): `a` assigns to it (animals to a pen or pit, an owner to a bedroom, office, dining room or tomb, squads to a barracks or range), `l` attaches it to a location, `s` suspends or resumes it, `n` names it, `X` removes it. `Esc` closes the panel.

- On a bedroom, dining hall, office or tomb DFHack shows its own box beside the zone's panel ("Autoassign to holder of role", from its preserve-rooms tool), which opens a list of roles below itself when the mouse is over it. The key list goes underneath, clear of both, and DFHack's own keys there (`S` steps the role, `R` clears a reservation) are passed through to it.

- A zone's own settings are on keys, shown with their current state in the key list: a pit / pond `f` (kept filled with water or not); a tomb `c` (citizens buried here) and `p` (pets); an archery range `d` (steps the shooting direction round); a gather-fruit zone `t` (pick trees), `b` (pick shrubs) and `f` (gather fallen fruit).
- Once a zone has a location, `l` opens the list again to change it (with `r` there to take the zone out of its location), and `d` opens the location's details (below).
- A letter with no use on the zone's page is not passed on to the game any more (`g` used to start a gather-plants designation under the panel).

- In the list `a` opens, `-` `=` select and `Enter` ticks or unticks; `Esc` closes it. Ticking an animal that is in another pen moves it out of that pen, as in the game.
- For a barracks or an archery range `a` lists the squads: `-` `=` select one, then the old barracks keys switch what it does there: `z` sleep, `t` train, `i` keep its soldiers' own equipment, `q` keep the squad's equipment.
- In the location list `l` opens, `-` `=` select one of the fort's locations and `Enter` attaches the zone to it; `i` `t` `l` `g` `h` start a new inn, temple, library, guildhall or hospital. A temple then asks for a deity and a guildhall for a trade, from a list worked the same way. `Esc` steps back one list at a time.

A location's details (`d` on a zone that has one, or `Enter` on a location in the Places list and then `d`), with the old location screen's keys:

- `-` `=` (or Up / Down) select a row: first the counts the fort can set (goblets, instruments, thread, cloth...), then the occupations.
- On a count: Right is one more and Left one fewer; `Enter` types a number (digits, then `Enter`).
- On an occupation: `Enter` opens the list of dwarves (`-` `=` and `Enter` choose, `Esc` closes it); `x` takes the current holder off.
- `r` steps through who may visit (everyone, residents and citizens, citizens only, and members only where the location has members).
- `n` opens the name builder (below) for the location's name. `Esc` goes back to the zone. DFHack's own `Ctrl+d` retires the location.

The name builder (`n` on a location's details, `B` with a squad ticked on the squads panel), with the old name screen's keys:

- The parts of a name are on the left and the words that fit the selected part on the right. Left / Right move between the two; `-` `=` (or Up / Down, Shift for ten) select.
- `Enter` on a part goes to its words; `Enter` on a word puts it in the part.
- `r` picks a random word for the selected part, `c` clears the part, `R` makes a whole random name.
- `e` (or `/`) filters the words: type, then `Enter`.
- `Esc` is the game's "Done": the name is kept as it stands. The name so far is shown at the top of the key list.

After `i`, zones:

- Pick the type first (the old flags are separate zone types now): `w` water source, `f` fishing, `g` gather fruit, `d` garbage dump, `n` pen/pasture, `p` pit/pond, `s` sand, `c` clay, `m` meeting area, `t` animal training.
- Zone types the old game did not have: `b` bedroom, `D` dining hall, `o` office, `y` dormitory, `B` barracks, `a` archery range, `j` dungeon, `T` tomb.

- Then arrows and `Enter` twice, as for stockpiles. `Esc` goes back to the type list.
- `X` removes the selected zone. `q` on a zone opens its panel. While a zone is selected its own keys apply (above); `Esc` and `i` again bring back the type list.

After `h`, hauling routes (minecarts), with the old hauling keys. The game's panel lists each route with its stops under it; the key list sits beside it, or under the minimap while one of its windows is open.

- `-` `=` (or Up / Down, Shift for ten) select a route or a stop; the list scrolls.
- `r` adds a route. `s` adds a stop to the selected route (or to the route of the selected stop): put the cursor where it goes and press `Enter` (`Esc` calls it off). The new stop is selected.
- `v` assigns a minecart to the route: `-` `=` select (the first row is "None"), `Enter` assigns, `Esc` cancels.
- `n` names the selected route or stop: type, then `Enter`; `Esc` puts the old name back.
- `x` deletes the selected route or stop, at once (the game does not ask).
- `z` zooms to the stop (on a route, to its first stop).
- On a stop, `Enter` (or `c`) opens its departure conditions, three to a page:
  - `-` `=` select a condition; `n` adds one, `x` deletes it.
  - `t` / `T` one day less / more to wait, `f` / `F` 25% less / more full (the game's own steps), `m` at least / at most, `l` desired items / any items, `d` direction (north, east, south, west, round), `p` push / ride / guide. `Esc` (or `Enter`) is "Done".
- `l` opens the stop's stockpile links: `t` take from a stockpile (the cart loads there), `g` give to one (it unloads there), `b` both; each puts the cursor out to pick the stockpile with `Enter`. `-` `=` select a link, `m` steps it between take, give and both, `x` deletes it, `Esc` closes.
- `i` opens the items the stop loads: the stockpile settings screen, with the same keys as a stockpile's settings (`s` on a stockpile, above).
- The game shows its help for the panel each time it opens; `Enter` or `Esc` closes it.

With a creature's panel up (`v`, or `Enter` on a creature in `k`):

| Key | Page |
|---|---|
| `g` | General (overview), then the skill lists; `b` `c` `m` jump to labor, combat, other skills |
| `i` | Inventory |
| `p` | Labor: work details, workshops, locations, work animals; `l` `o` `a` jump to those |
| `w` | Wounds, then the other health pages; `h` health status; `d` the description (Health, Description) |
| `z` | Thoughts, memories, then traits, values, preferences, needs |
| `r` | Relationships, then groups |
| `k` | Kills, then squad and uniform |
| `R` | Rooms |

- Pressing a key again steps to its next page. `+` `-` scroll the page.
- `v` next creature near the cursor, `f` follow it, `y` then `n` / `p` to type a nickname or profession name.
- Tame animals: `s` marks for slaughter, `x` for gelding.
- Moving the cursor to another creature keeps the page you were on.
- `Tab` steps through the sub-tabs of the tab on show (Health: status, wounds, treatment, history, description; likewise Skills, Labor, Military, Thoughts, Personality) and `Shift+Tab` steps back; both wrap round.
- On the Labor page, `-` `=` select a row of the list (work details, workshops, locations, work animals) and `Enter` ticks it; `t` switches "will only do assigned tasks". Ticking a detail the game treats as exclusive (miners, woodcutters, hunters) unticks the other, as with the mouse.
- `S` puts a citizen in a squad, in a small window of the overlay's own: the fort's squads with their free places, `-` `=` and `Enter` to join one; the first row leaves the current squad. (The game only does this from the squad's side, `p` on the squads panel.)
- `E` expels or sends away: the game's own panel, with `-` `=` to choose where to and `Enter`. The game then lists who will leave with them; `Enter` again expels, `Esc` cancels. If the creature cannot be sent away the panel says why.
- These keys also apply to a creature's sheet opened with the mouse or from the creatures list.

After `s` (or `m`), squads:

- `a` to `j` tick and untick squads, in the order the panel lists them.
- `m` move: a cursor appears; `Enter` stations the ticked squads there.
- `k` kill: put the cursor on a creature and `Enter` orders the attack. The fort's own dwarves and animals cannot be targeted.
  - `l` picks from a list of every creature that can be attacked: anything the game counts as a danger (invaders and the like) first and in red, then nearest first. `-` `=` move, `x` marks, `Enter` attacks everything marked (or the highlighted one if nothing is).
  - `r` targets an area: `Enter` on one corner, `Enter` on the other, and everything attackable inside becomes a target. Change level between the corners to take in several levels.
- `r` patrol: a list of the fort's routes; `-` `=` move, `Enter` sends the ticked squads along that route, `a` adds a route, `e` edits and `d` deletes the highlighted one (at once, as the game's bin does), `Esc` cancels.
  - Adding or editing a route: move the cursor and `Enter` drops a point there; `-` `=` select a point in the list and `x` removes it; `n` names the route (type, then `Enter`); `Shift+Enter` saves, `Esc` goes back without saving. Saving a new route also orders the patrol. With no routes yet, `r` opens this screen directly.
- `w` defend burrows: a list of burrows; `-` `=` move, `x` ticks, `Enter` orders the defence of the ticked burrows (or the highlighted one if none is ticked), `Esc` cancels.
- `t` orders the ticked squads to train.
- `o` cancels the ticked squads' orders. `z` centres the view on the first ticked squad.
- `s` opens the schedule and `E` the equipment screen (both below).
- `C` creates a squad: `-` `=` and `Enter` choose the post that leads it (the captain of the guard, a new militia captain, or a militia captain's post left without a squad), then the same for its uniform (in that list `d` deletes and `N` renames the highlighted uniform, as on the equipment screen). `Esc` backs out of either list without creating anything.
- `p` shows the positions of the first ticked squad: `-` `=` move between them, `Enter` opens the list of dwarves for that position, `Esc` goes back to the squads. A new squad offers only its leader's position until that is filled.
  - In the list of dwarves, `-` `=` move (the list scrolls at its ends), `Enter` puts that dwarf in the position, and the first row, "Remove assignment", empties it. The list stays open after a choice; `Esc` closes it. Letters are left to DFHack's sort and filter keys there.
  - Orders for single soldiers: in the positions view `x` ticks the highlighted soldier and `a` to `j` tick by position, as the old `p` mode did. `m` `k` `r` `w` `t` and `o` then apply to the ticked soldiers only.
- `N` names the first ticked squad (also `N` inside its positions view): type the name and press `Enter`; an empty name gives the squad its own name back, `Esc` leaves it as it was.
- `B` opens the game's word-by-word name builder for the first ticked squad (keys above, under the zones).
- `D` disbands the ticked squads: the game asks first, `Enter` disbands and `Esc` keeps them. The game leaves the leader as a militia captain without a squad; `C` offers that captain again, or the Nobles screen can vacate the post.
- `Esc` cancels an order being aimed, or closes the panel.

In the schedule (`s` with squads ticked), a grid of routines across and squads down:

- Arrows move the cursor across the grid; `-` `=` also move between squads. The cell is marked on the game's grid.
- `Enter` makes the squad follow the routine under the cursor.
- `e` opens that cell's orders and `v` the squad's monthly schedule (both below). `c` is the cell's Copy (then Paste) button.
- `X` is the cell's Clear button, which wipes the squad's monthly orders under that routine; it asks first.
- `a` opens the routine editor, with the old alert page's keys: `-` `=` select a routine, `c` adds one, `N` names it (type, then `Enter`), `d` deletes it after the game's "Really delete?" (`Enter` deletes, `Esc` keeps it), `Esc` returns to the grid.
- `Esc` steps back one screen at a time: out of a sub-screen, then to the squads panel.

In the monthly schedule (`v`), a row per month with the same routine columns:

- Arrows move the cursor; `-` `=` also move between months. The list scrolls to keep the month in view.
- `Enter` (or `e`) edits that month's orders in the order editor; `Esc` there comes back to the months.
- `c` is the cell's Copy (then Paste) button.

In the equipment screen (`E` with squads ticked), a row per soldier:

- `-` `=` or Up / Down select a soldier, marked on the game's list.
- `Enter` (or `d`) opens that soldier's equipment details.
- `a` assign uniform: a list of the fort's uniforms opens; `-` `=` and `Enter` give one to the ticked squads.
  - In that list `d` deletes the highlighted uniform (DFHack asks first: `Enter` deletes, `Esc` keeps it) and `N` renames it: type the new name in the box that opens and press `Enter`.
- `n` add uniform: the same screen as a soldier's equipment, below, building a new uniform instead.
- `f` ammunition, `u` supplies, `U` update equipment.
- `Esc` steps back out of whichever of those is open, then to the squads panel.

A soldier's equipment (`Enter` on a soldier) and the add-uniform screen (`n`), with the 0.47.05 keys:

- `-` `=` select a piece. `M` picks its material and `C` its colour. `x` removes it.
- `A` armour, `H` helm, `L` legwear, `G` gloves, `B` boots, `S` shield, `W` weapon: add a piece of that kind.
- Each of those opens a list: `-` `=` and `Enter` choose from it, `Esc` backs out.
- `r` switches the uniform between worn over clothing and replacing it; `m` switches exact matches.
- `N` names the uniform: type the name and press `Enter`.
- `Enter` confirms the changes (on the add-uniform screen, saves the new uniform); `Esc` discards them.

Supplies (`u`): `-` `+` less or more water (none, water, drink), `/` `*` less or more food, Up / Down between squads, `Enter` confirms.

Ammunition (`f`):

- Up / Down select an ammunition. `-` `+` change the amount by 5, `/` `*` by 25.
- `C` and `T` switch its use in combat and in training.
- `c` adds one, chosen from a list with `-` `=` and `Enter`. `d` deletes the selected one.
- `M` opens its material list (about a thousand entries, "any material" first): `-` `=` move by one, Shift+Up / Shift+Down by ten, `Enter` chooses, `Esc` backs out.
- `Enter` confirms.

In the order editor (`e` on a schedule cell):

- `t` adds a train order. `m` adds a station order: a cursor appears and `Enter` sets the spot.
- `-` `=` set how many soldiers the next order added will ask for.
- Up and Down select an order (marked on the game's list); `x` removes it.
- `1` to `9` and `0` tick the soldiers in positions 1 to 10, so that the next order added is for them alone; `w` goes back to the whole squad. (The letters are all taken on this screen.)
- `N` names this set of orders: type the name and press `Enter`.
- `s` steps through the sleep modes and `u` switches the uniform mode; the game's two buttons show the result.
- `p` (patrol) and `d` (defend burrow) open the route and burrow lists, worked with the same keys as from the squads panel (`r` and `w` above).
- `Enter` or `Esc` finishes and returns to the grid.

Work orders (`o`, or `j` then `m`), with the old manager's keys. The key list sits under the minimap while the screen is up.

- `-` `=` select an order (Shift+Up / Shift+Down move ten).
- `q` new order: the game's task list. Type to filter it, as before; `-` `=` select, Left / Right change the workshop whose tasks are listed, `Enter` orders it, `Esc` cancels. The amount box opens straight after: type how many and press `Enter`.
- `r` removes the order, at once. `p` moves it up the list (promote) and `P` back down.
- `a` changes the amount (it was `n`, now the nobles tab) and `t` the most workshops that may work on it: type the number and press `Enter` (0 means any).
- `d` opens the order's details where it has any (below).
- `c` opens its conditions:
  - `-` `=` select a condition. `a` adds an item condition, `o` a condition on another order (pick it with `-` `=` and `Enter`), `1` to `9` add that one of the game's suggested conditions, `d` deletes the selected one.
  - On an item condition: `i` item type, `m` material and `t` traits each open a list that filters as you type (`-` `=` select, `Enter` chooses, `Esc` backs out); `q` steps the comparison (at least, at most, ...); `n` sets the number.
  - On an order condition: `c` switches between "must be completed" and "must be active".
  - `f` steps how often the order restarts (one-time, daily, monthly, seasonally, yearly). `Esc` returns to the orders.
- DFHack's own keys on this screen (Ctrl+ and Alt+ combinations: import, export, sort, search) are left alone.

A task's or work order's details (`d` on a work order, or on a task in a workshop):

- An order with one thing to settle (the wood for bolts) opens on its choices; one with several (a dress: its cloth and its size) opens on a list of them, and `Enter` goes into one.
- `-` `=` (or Up / Down, Shift for ten) select and the list scrolls; `Enter` chooses, which closes the window.
- `/` (or `s`) filters the choices: type, then `Enter`.
- `Esc` goes back one step: from a list of choices to the list of things, then out of the window.

Nobles (`n`):

- `-` `=` select a post.
- `r` (or `Enter`) replaces its holder: the candidates open, `-` `=` select (Shift+arrows by ten), `Enter` appoints, and the first row, "Leave Vacant", empties the post. `Esc` backs out.
- `S` opens the symbols of office for the post: `-` `=` select, `Enter` or `x` ticks, `Esc` is the game's "Done".
- On the bookkeeper's row, `1` to `5` set the precision and `s` steps it.
- `Esc` closes the screen.

Announcements (`a`), the game's own window, on keys:

- It opens on the latest announcement (the list runs oldest first), marked
  with a yellow arrow; the key list under the minimap shows where you are
  ("All: 320 of 320").
- `-` `=` or Up / Down move a line and Shift+Up / Shift+Down ten; PgUp / PgDn
  a page; Home / End go to the first and the latest.
- Left / Right step through the categories (All, General, ... Combat,
  Sparring, Hunting), round and round, passing over the empty ones. Each
  category keeps its place while the window is open.
- `z` zooms to the announcement's place, where it has one (this closes the
  window, as the game's button does). `Enter` does the same, and on a
  fight's line ("... is fighting!") opens that fight's report instead: there
  the same keys scroll the text and `Esc` goes back to the list.
- `Esc` closes the window.

Reports (`r`), the old combat reports screen, in a window of the overlay's own:

- One line per creature and kind of report (combat, sparring, hunting), with the date of its latest line; the most recent is at the top.
- `-` `=` or Up / Down select (Shift for ten), `Enter` reads that creature's report, oldest line first with a line for each new day, in the game's own colours. `Esc` goes back to the list, and from the list closes the window.
- While reading a report, `-` `=` or Up / Down scroll the text a line at a time and Shift+Up / Shift+Down ten lines; PgUp / PgDn scroll a page and Home / End go to either end.
- `z` zooms the map to the creature and closes the window.
- The game only keeps its most recent few thousand announcements, so an old fight drops off the list once its lines are gone.

The rest of the info window (`u`, `j` and the other tabs of the same window). The key list sits under the minimap.

- `Tab` and `Shift+Tab` move between the window's tabs from any of them: Creatures, Tasks, Places, Labor, Work orders, Nobles, Objects, Justice.
- The letters that open a tab from the map switch straight to it from any other: `u` Creatures, `j` Tasks, `l` Places, `y` Labor, `o` or `m` Work orders (`m` as on the old job list), `n` Nobles, `L` Objects, `J` Justice. Not while one of a tab's own lists or boxes is open in front of it, and typing in a search or name box is left alone. To free these letters three page keys moved: the work order amount is `a`, naming a work detail `N`, classic labors `c`, and sorting `t` / `T`.
- In every list `-` `=` (or Up / Down, Shift for ten) select a row and the list scrolls to it. Left / Right move between a tab's pages (Residents, Pets/Livestock... ; Zones, Stockpiles...). Where a page has two lists side by side, Left / Right move between the lists instead and Shift+Left / Shift+Right change page.
- Creatures: `Enter` (or `v`) opens the creature's sheet, `z` zooms to it.
- Tasks: `Enter` opens the worker's sheet (or, with no worker, the job's building), `z` zooms to the job; `m` is the old key for the manager (work orders). On a workshop job `s` suspends or resumes it (suspending takes the worker off), `x` cancels it, `r` takes the worker off and `p` switches repeating on or off (the key list says when it is on).
- Places: `Enter` opens the place's own panel (zone, stockpile, workshop...), `z` zooms to it. A zone, location or stockpile opened this way is then looked at as with `q`, so its own keys work (`a` `l` `d` `s` `n` on a zone).
- Objects: `Enter` opens the object.
- Labor, work details: the list of details on the left (moving onto one shows it) and its dwarves on the right; `Enter` on a dwarf puts them on the detail or takes them off, `s` is their "only does assigned work" button. `a` adds a detail, `N` names the chosen one (type, then `Enter`), and `1` `2` `3` set it to everybody, only the selected dwarves, or nobody. `e` opens the detail's own editor: `-` `=` move through its labors, `Enter` ticks one (or a whole group, on a heading), `i` steps to the next of the game's icons for the detail, `D` deletes the detail at once, `Esc` is "Done".
- Sorting: on the lists with column headings (creatures, a work detail's dwarves), `t` sorts by the next heading (Name, Cat, Prof, Job, Stress...) and `T` by the same one again, which reverses the order. The key list names the column.
- `/` types into a list's search box on the creatures, labor and justice tabs: type, then `Enter`; `/` and Backspace clear it.
- Labor, standing orders: `Enter` switches the order (some have three settings and step through them). Left / Right move between Workshops, Hauling, Refuse and the rest; Shift+Left / Shift+Right between Labor's four pages.
- Labor, standing orders, Chores: the fort's children on the left and the chores on the right. `-` `=` select and `Enter` ticks (a child: whether they do chores; a chore: whether children do it). Left / Right move between the two lists, and on past them to the pages either side. `c` switches "children do chores" for the whole fort.
- Labor, kitchen: `c` switches cooking and `b` brewing for the selected food; Left / Right step through the food categories.
- Labor, stone use: `Enter` switches whether the stone may be used for ordinary jobs.
- Justice: the cases on the left (moving onto one shows it) and its reports on the right; `i` and `c` are the case's Interrogate and Convict buttons, which open a list of dwarves: `-` `=` select, `Enter` chooses that dwarf, `Esc` goes back to the case.

`b` `p` `u` `o` `n` `y` `H` and `Space` `.` `F1`-`F8` on the map are the game's own keys, passed straight through.
