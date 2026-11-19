# Development notes

How the overlay is built, how to work on it against a running game, and
what has and has not been tried. Written while it was being built, so
some notes are dated.

## Layout

- `scripts/classic-controls.lua` - the overlay; key tables are at the top
- `scripts/classic-labors.lua` - labors per dwarf with skill-based defaults (the `classic-labors` command)
- `scripts/cc-dev/` - helpers for poking at the running game (below); not part of the mod
- `mod/` - the mod's `info.txt` and Workshop preview image
- `tools/build-mod.ps1` - assembles the mod folder and zip in `dist/`, and stages it for upload
- `tools/capture.ps1` - screenshot the game window without focusing it
- `tools/sendkeys.ps1` - send real key presses to the game window
- `tools/update-therapist.ps1` - give Dwarf Therapist a memory layout for the running game
- `tools/sendmouse.ps1` - post a left-button drag between two map tiles (the game mostly ignores it)
- `tools/gridtest.sh` - smoke test of the position-dependent screens (needs a prepared test save)

## Running from a copy of the repository

DFHack finds the scripts through a line in the game's
`dfhack-config\script-paths.txt`:

    +C:/path/to/df-classic-controls/scripts

The `+` puts it ahead of every other script folder, so it wins over a copy
installed from the Workshop. Edits then take effect after the reload
command below, without restarting the game.

## Working on it

With the game running, commands go through
`<Steam>\steamapps\common\DFHack\hack\dfhack-run.exe`:

    dfhack-run lua "reqscript('classic-controls'); require('plugins.overlay').rescan()"   # reload after an edit
    dfhack-run cc-dev/keys CUSTOM_Q            # feed a key through the overlay, print UI state
    dfhack-run cc-dev/dump-screen [pattern]    # print the text on screen
    dfhack-run cc-dev/click <x> <y>            # click an interface cell
    dfhack-run cc-dev/snap save | diff         # find which UI fields an action changes
                                                # (it crashed the game on 2026-11-18 with the hauling
                                                #  panel open: it follows every pointer under
                                                #  main_interface, stale ones included)
    dfhack-run cc-dev/build-tree               # print the game's build menu: entries, categories, hotkeys
    dfhack-run cc-dev/test-build               # press every classic build key, report what gets placed

Send keys in separate `dfhack-run` calls when a step depends on the screen
having been redrawn; several keys in one call all land in the same frame.

`cc-dev/keys` feeds interface keys the game has already translated, which says
nothing about what a real key press turns into under the player's bindings.
For that:

    tools\sendkeys.ps1 k up shift+up minus equals enter esc    # real key events, window need not be in front
    tools\sendkeys.ps1 "char:<" "char:>"                       # a typed character, for < > + and the like
    dfhack-run lua "reqscript('classic-controls').key_log_enabled = true"
    dfhack-run lua "for _, l in ipairs(reqscript('classic-controls').key_log) do print(l) end"
    dfhack-run cc-dev/test-pile make                           # a one-tile throwaway stockpile to test on
    dfhack-run cc-dev/test-pile remove                         # ... and away again ("make b" / "remove b" for a second)
    Get-Content "<game folder>\stderr.log" -Tail 12            # script errors land here, not in the command's output

Check `stderr.log` after every test run. A handler that fails is caught in
`onInput` and its key dropped, but until that was added a failing handler let
the key through to the game's own hotkeys, and a test's next letters started
a designation and created a work order. Each key press also arrives twice: once
with its interface codes and once as the bare character (`_STRING` only).

The key log shows every code the game reported for each press. Things it has
shown on this install: an arrow arrives as both `CURSOR_UP` (camera) and
`KEYBOARD_CURSOR_UP`; `-` arrives as `SECONDSCROLL_UP` and
`KEYBOARD_CURSOR_UP_Z`; `=` is bound to nothing and arrives only as the typed
character; Shift+W/A/S/D arrive with `CURSOR_*_FAST` and Shift+E/C with
`CURSOR_*_Z_FAST` beside their `CUSTOM_SHIFT_*` code, which is why a letter
press is never treated as movement (`get_move`); `<` and `>` likewise arrive only as characters, so the overlay
changes level on the character and feeds the game `CURSOR_UP_Z` /
`CURSOR_DOWN_Z` itself. A Shift sent by `sendkeys.ps1` is released by SDL straight after,
so a shifted press is followed by a stray unshifted one; real keyboards do the
same when Shift is let go first, and the overlay drops that stray step.

A shifted letter sent by `sendkeys.ps1` often loses its Shift, so test those
with `cc-dev/keys`, giving every code the real press carries, joined with
`+`: `cc-dev/keys CUSTOM_SHIFT_A+CURSOR_LEFT_FAST`. Feeding `CUSTOM_SHIFT_A`
alone hid a bug that broke A, S, W, C and E on a real keyboard.

How the new UI is driven:

- Unit / building / item panels open by setting fields on
  `game.main_interface.view_sheets`; no mouse click is simulated.
- Add-task entries are the game's own `main_interface.building.button`
  objects; choosing one calls its `press()`. The game gives them no hotkeys
  any more, so the 0.47.05 ones are attached by rule (`TASK_KEYS` in the
  script: workshop kind, then job type / label / reaction). `cc-dev/tasks`
  prints what a workshop offers, for writing rules.
- The game's own keyboard cursor (designations, building placement) is moved
  by the overlay, not the game: with camera and cursor both on the arrows the
  game moves both for one press, and its Shift step is 20, not 10.
- "Add new task" and "Cancel" are clicked by finding their text on screen, so
  those two depend on the English UI text.
- Build menu entries are reached by feeding the game's own category and
  building hotkeys (`HOTKEY_BUILDING_*`); the paths are a table at the top of
  the script. If a game update moves buildings between categories,
  `cc-dev/test-build` shows which entries broke and `cc-dev/build-tree` prints
  the new layout.
- A material is picked by clicking its row; the list is found by its
  "Select materials for" heading (English UI text again).
- Stockpiles and zones are painted by the game with two mouse clicks, one per
  corner, and it has no keyboard path. The overlay keeps its own cursor and,
  on the second `Enter`, clicks both corners and then the "Accept" button.
- A zone type is chosen by setting `main_interface.civzone.adding_new_type`
  and the paint mode directly. A stockpile type is set by clicking the game's
  own preset button, found by its label, so the game applies its usual
  defaults (barrels for food, a wheelbarrow for stone).
- Stockpile and zone panels open for `q` by setting `stockpile.cur_bld` /
  `civzone.cur_bld` and the bottom mode. Clear those pointers before
  deconstructing the building they point at, or the game is left holding a
  dangling pointer.

- Unit panel tabs are switched by clicking their labels, not by setting
  `view_sheets.active_sub_tab`: the game only fills in most tabs (skills,
  health, relations, personality) when it handles the click itself. A
  sub-tab's label only exists on screen after its tab has been drawn, so that
  click is made a frame later.
- The game draws a scrolled list pinned at its end but lets the scroll number
  run past it, and the mouse wheel cannot be simulated. So `+` scrolls, and
  the next frame undoes it if nothing on screen moved.
- Nicknames use the game's own text entry, started by setting
  `unit_overview_customizing` and `unit_overview_entering_nickname`.

- Squads are ticked by setting `main_interface.squads.squad_selected`. A
  move or kill order starts by setting `giving_move_order` /
  `giving_kill_order`; the move destination is then a click on the map, and
  kill targets are unit ids added to `kill_unid` followed by a click on
  "Confirm". Cancelling orders clicks the game's button: the six order
  buttons are icons with no text, found by their position above the "Equip"
  label.

- The routine a squad follows is `squad.cur_routine_idx`, an index into
  `plotinfo.alerts.routines`. The schedule grid's cells are located from
  text (the "Add/edit routines" button, the routine's name, the squad's
  name); its buttons sit 3 rows under the cell text. The game's Esc closes
  the whole squads panel from any depth, so the overlay steps back itself by
  clearing `squad_schedule.open`, `viewing_months_squad_id`,
  `editing_routines` or `squads.editing_squad_schedule_id`.

- A squad's orders live in
  `squad.schedule.routine[r].month[m]` (`orders`, `sleep_mode`,
  `uniform_mode`). The order editor edits one month, or all twelve when
  `squads.editing_squad_schedule_month` is -1; the overlay sets the two modes
  on the same months directly. Orders are added and removed through the
  game's icon buttons, placed from the editor's "Minimum number of" label
  (see `order_editor_anchor`). A station order's spot is picked with the same
  `giving_move_order` flow as a direct move order.

- Equipment: supplies are `squad.supplies.carry_food` / `carry_water` and
  ammunition is `squad.ammo.ammunition[i]` (`amount`, `flags.use_combat`,
  `flags.use_training`), all set directly; `squad.ammo.update.ammo` is raised
  after an amount change. A soldier's details are a working copy in
  `squad_equipment.cs_*`, changed only through the game's buttons so that
  Confirm and cancel behave as usual. The lists these screens open share one
  layout (rows 3 apart from the row the soldier list starts on, scrolled an
  entry at a time), handled by `on_pick_list_input`. Empty screen cells hold
  character 0, not a space, so search text must not end in a space.
- The uniform picker opens in the top-left corner (under where the
  overlay's own panel normally sits, which is moved aside for it). Its rows
  are the fort entity's `uniforms` plus "No uniform";
  `assign_uniform.cand_uniform` stays empty. A piece is removed with the bin
  icon 9 columns past its "Color" button.
- Creating a squad is two native lists, `create_squad.open` ("Create which
  squad?") and then `assign_uniform.open` without the equipment screen; rows
  are 3 apart under the heading and are clicked. A squad's positions are
  shown by setting `squads.viewing_squad_index`; the slots start 6 rows under
  "Back to squads", 3 apart, scrolled by `squads.scroll_position`, and a
  click on one opens `dwarfmode/UnitSelector` (`unit_selector.squad_id`,
  `squad_position`, `scroll_position`; first row "Remove assignment"). A real
  Esc there must be answered with `LEAVESCREEN` alone, or its second code
  opens the options menu. The disband bin is 12 columns past the "Schedule"
  label and raises `squads.disband_confirmation`, answered by clicking
  "Disband" or "Cancel".
- The patrol and burrow orders open their own windows, from the squads
  panel's order icons and from a schedule's order editor alike
  (`patrol_routes.open`, `burrow_selector.open`); the window sits further
  left in the second case, so everything in it is found from its text.
  Burrow ticks are `burrow_selector.selected`, set directly. Route points
  are clicks on the map (`patrol_routes.new_point`), and the map is scrolled
  first so that the cursor is not under the window. Esc in the route editor
  clicks its "Back" button when it has one, which must not be confused with
  "Back to squads" in the panel beside it.
- The routine editor is `squad_schedule.editing_routines`: rows 3 apart
  under "Military routines", with a quill 23 and a bin 33 columns from the
  heading's first letter. The game leaves
  `scroll_position_edit_routine` negative after adding a routine. Deleting
  goes through `deleting_routine_id` and a Confirm button.
- The ammunition material list is scrolled by
  `setting_ammo_scroll_position_am` (shared with the type list) and holds
  `am_cand_civ_mat` entries; neither ammunition list has a heading, so they
  are placed where the soldier list starts rather than from the last heading
  seen, which may be the uniform picker's.
- A uniform's bin in the picker is caught by DFHack's `confirm` plugin,
  which puts a "Delete uniform" box in front; clicks made while that box is
  up stack more boxes. In the order editor,
  `editing_squad_schedule_pos_selected` lists the ticked positions and
  `editing_squad_schedule_whole_squad_selected` is true when it is empty.
- The game can be driven while its window is minimised (keys and screen
  text both work), but `tools\capture.ps1` needs the window restored.
- The creatures, labor and justice tabs, and the unit list a zone opens, are
  built from the game's newer widgets. `dfhack.gui.getWidgetChildren` walks
  them; each has a `name` and a `rect` (its place on screen), so buttons are
  clicked by name and nothing is counted in columns. A list is a
  `widget_scroll_rows` (`scroll`, `num_visible`, its children the rows) and
  setting `scroll` scrolls it; a list of choices is a `widget_radio_rows`
  (`rows`, `selected_idx`); a `widget_tabs` has `cur_idx`, and a page is
  only filled in when its label is clicked; a `widget_stack` shows the child
  whose `flag.VISIBILITY_VISIBLE` is set. `cc-dev/widgets creatures|labor|justice`
  prints a tab's tree. The other tabs (tasks, places, objects, standing
  orders, stone use) keep plain lists with `scroll_position*` fields.
- Never delete a building while a chooser opened from its panel is open
  (unit list, squad list, location chooser): the chooser keeps a pointer to
  it and the game crashes on the next frame. `cc-dev/test-zone remove`
  refuses while one is open. `cc-dev/test-zone make <type>` builds a
  one-tile throwaway zone to test zone screens on.
- Ticking an animal for a pen takes it out of whatever pen it was in, and
  unticking does not put it back: test on animals that have no pen.
- If the game has to be closed without saving, `dfhack-run die` does it;
  relaunch with `steam://run/2346660` and load through the title screen with
  `cc-dev/click 86 33` (Continue), `cc-dev/click 70 33` (the world), and
  `cc-dev/click 70 33` again (the first save listed, checking its folder
  name on the row below first).
- Reports: `unit.reports.log[kind]` (0 combat, 1 sparring, 2 hunting) holds
  report ids; `df.report.find(id)` gives the line (`text`, `color`,
  `bright`, `year`, `time`) or nil once the game has dropped it. The window
  is a `gui.ZScreen` like the add-task list, not part of the overlay.
- The script's top level is close to Lua's limit of 200 local names per
  chunk ("too many local variables" on load, with the old version left
  running). The newer sections (stockpile settings and links, the info
  window, trade) are each wrapped in `do ... end`; a helper used inside such
  a block must be defined before it in the file, or it is read as a missing
  global (`typed` was, for the stockpile settings). The limit counts the
  names in scope at once, an enclosing block's included, so these blocks sit
  side by side, not inside one another; what the trade block shares with the
  info block it takes from `ClassicKeysOverlay.info_helpers`.
- Trade (`mi.trade`): `good[side]` and `goodflag[side][i].selected` hold the
  goods and the marks (side 0 the merchants, 1 the fort). Each list is 3
  screen rows to an entry and `scroll_position_item[side]` counts screen
  rows, not entries, and is not clamped. A click on an item's name or tick
  box marks it; on a category's name, folds it; on its box, marks the
  category. "Trade" must be looked for on the buttons' own row: "Trader
  Profit" two rows above starts with the same letters. Esc closes the trade
  screen and the depot's sheet under it, so a key sent afterwards lands on
  the bare map.
- Move goods (`mi.assign_trade`): ticks are `master_i_list.tgi[i].tag` until
  the screen closes. The item list also scrolls by screen row; the list of
  kinds scrolls by entry. The two sort buttons are a pair, each switching
  only its own order on. The list is re-sorted after every tick ("ticked
  first" is on), so the same row is a different item afterwards.
- "Unloaded" is not all at once: the trade screen opens once the first
  wagon is done, with part of the goods, and can fall back to "we're still
  unloading" with empty lists. Wait about two more days before testing.
  Requesting a trader ("anyone") before unpausing has a dwarf waiting at the
  depot when the wagons arrive.
- The game's "FPS has dropped below 50... enable multithreading?" box takes
  the next Enter as "Yes", whatever screen is behind it: read the screen for
  it before sending Enter after the game has been running. The choice is
  `d_init.feature.flags.MULTITHREADING` in memory and
  `[MULTITHREADING:...]` in `prefs\d_init.txt`; the box changes the first
  and not the second.
- Getting merchants for a test: `force Caravan`, unpause, and wait for
  "unloading" to finish (about three game days), then request a trader at
  the depot and wait for one to arrive. Unpausing did not hold while the
  window was minimised. The game may also stop to ask about multithreading
  when it slows down; the box takes a click on its "No". Time passing is
  real for the fort: read the announcements for what happened meanwhile.
- Stockpile settings (`custom_stockpile`): a click on a category or a list
  sub-category only selects it, but the game also switches the category's
  group flag on, even with nothing in it allowed, and opening the settings of
  a stockpile that takes nothing does the same to its first category. The
  overlay puts `settings.flags` back after a selecting click
  (`pile_select_click`) and switches the selected category's group on itself
  when something in it is allowed (`pile_group_on`). An item's real state is
  `spec_item[i].set_pointer.value`, not its `on` field; a yes / no
  sub-category's is `sub_mode_ptr[i].value`, and `sub_mode_ptr_type[i]` is -1
  for sub-categories that have a list instead. The item filter only starts
  when its box is clicked: setting `entering_spec_filter` is not enough.
- Stockpile links (`stockpile_link`): the window's two add buttons raise
  `adding_new_link` (type 1 give, 0 take) and the next click on the map picks
  the other end, so the map is scrolled until the cursor is clear of the
  panel and the links window. A link in one direction replaces one in the
  other between the same two stockpiles. "Links only" is
  `stockpile_flag.use_links_only`, set directly.
- Work orders and nobles are tabs of the info window (`mi.info`,
  `current_mode`); the overlay takes the keys there and on the new-order
  screen (`create_work_order`), and leaves the other tabs alone. Their
  lists are filtered by the game as you type, so their length cannot be
  read: the selection is a row on screen (`rows_input`), moving past the
  last row scrolls, and each frame `render_rows` undoes a scroll past the
  end. Typed characters must reach the game: on the new-order screen the
  overlay turns `entering_job_filter` on for the one key and off again a
  frame later, because DFHack keeps overlays out while it is on.
- Number keys can arrive as cursor movement as well as a character, so
  handlers that use digits read them (`typed_digit`) before `take_move`.
- Under the info window, and under an order's details window, the game's
  map hotkeys still fire (`p` starts a stockpile and closes everything), so
  unused letters are swallowed there. Ctrl+ and Alt+ combinations are passed
  on: DFHack's own overlays on these screens use them.
- Creating an order happens inside the click, so anything that compares
  "before and after" must count before clicking. A number typed for an
  amount applies as it is typed; Esc only stops the typing.
- The overlay's frame is wider than any screen so that its panel can be
  placed under the minimap (`show_panel`'s `left` and `top`); the framework
  trims the frame to the screen.
- Orders given inside a squad's positions view go to
  `squads.squad_hfid_selected` (historical figure ids) and land in
  `squad.positions[i].orders`, not `squad.orders`. A squad's typed name is
  `squad.alias`, entered through `squads.entering_squad_nickname`; the quill
  on the squad list (2 rows above the squad's name, 14 columns along) opens
  the game's word-by-word name builder instead (`name_creator`).
- The name builder, a job's details (`job_details`) and a location's details
  (`location_details`) open over anything else, so `dispatch` asks
  `detail_window()` first. The game takes the typing in their filter and
  number boxes (`entering_cull_str`, the `*_doing_filter` flags,
  `entering_desired_number`, a pointer that is nil when idle), and `onInput`
  passes keys through while one is on.
  - Name builder: placed from its "Done" and first "Clear" labels. A click on
    a part's label sets `cur_name_place` and refills `word_index`; a click on
    a word assigns it.
  - Job details: `current_option` is -1 while the list of options shows, else
    the option's type, whose list has its own scroll field (`JD_LISTS`).
    Setting `current_option` back to -1 returns to the options. The window
    stands in a different place when opened from a workshop, so its title
    row is looked for. A choice closes the window. The IMAGE option is not
    handled.
  - Location details: the count buttons stand at a different column for each
    kind of location, so they are found as the first cells after the row's
    text whose texture (`readTile(x, y).tile`) is not the row's background.
    The occupation list scrolls by entry (`scroll_position_occupation`). A
    zone that has a location shows two buttons where it had one: choose /
    change (4 columns left) and details; the chooser then starts with a
    "Remove current location assignment" row and the rest stands 3 lower.
- Announcements (`mi.announcements.stack`, focus `dwarfmode/Announcements`):
  a `widget_tabs` of 25 `widget_scroll_rows`, so the list is driven like the
  creatures tab (`scroll`, `num_visible`). A row with a place has a
  `widget_recenter_button`; a fight's row has a plain `widget` button at its
  end instead, which puts a `widget_report_popup` in front as the stack's
  second child. The popup's lines are in its `texts` field, a shared pointer
  DFHack cannot follow: its first 8 bytes are read as the address of the
  `widget_scroll_rows`. Closing the popup reads as focus `dwarfmode/Default`
  for a frame, so the selection is only reset after the window has stayed
  shut for 20 frames. PgUp / PgDn arrive with diagonal cursor-move codes as
  well as `STANDARDSCROLL_PAGE*`, and Home / End as `CUSTOM_HOME` /
  `CUSTOM_END`; `tools\sendkeys.ps1` knows `pgup pgdn home end`.
- Pausing is one check a frame (`hold_the_clock`): "busy" is a cursor mode,
  a bottom mode other than NONE, an open sheet, any focus other than exactly
  `dwarfmode/Default`, or one of the overlay's own windows on top. Going
  busy records whether the game was running and pauses it; going idle
  restores that. Tested with real keys from a running and from a paused
  game on: designations, squads, zones, build, stockpiles, creatures,
  tasks, nobles, announcements, reports, `k`, `q` and `v`.
- The add-task list presses the game's own buttons (`button:press()`). A
  button that opens a submenu replaces `building.button` but, pressed this
  way, leaves `building.filtered_button` (the list the game draws) pointing
  at the old buttons, already freed: reading one's text crashes the game,
  and so does the game's next redraw. `task_buttons()` spots that (an entry
  of the filtered list that is not in `button`) and rebuilds the filtered
  list. In a submenu the game's button is "Back", not "Cancel".
- A DFHack list scrolls its selected row out of sight if it is selected
  before the list's first layout (`page_size` still 1): select afterwards.
- The game does not expose a designation box's first corner (it is not in
  `selection_rect`), so `on_designation_corner` gives both Enters to the
  game itself (`feed('SELECT')`, which designates at once) and remembers the
  corner. Old designations in the box are cleared before the second Enter
  and restored on tiles the game left empty.
- When a dwarf takes on a designation the game clears the tile's `dig` /
  `smooth` flag and the order lives on only as a job at `job.pos`; the game
  will not designate over such a tile. `jobs_back_to_designations` removes
  those jobs in the box and puts the matching flag back (`FROM_JOB`: Dig and
  felling, gathering, removing constructions or stairs are `dig=Default`;
  the stair, ramp and channel jobs their own values; smoothing and
  fortifying `smooth=1`, engraving `smooth=2`), then the usual replacement
  runs. Track jobs are left alone (the job does not say which direction).
- Farm plot sheet: the season tabs are `view_sheets.active_sub_tab` (0-3);
  the list under them is not in any structure DFHack shows, so it is read
  off the screen from "Leave fallow" down, 3 rows to a crop. It scrolls by
  `view_sheets.scroll_position_displayed_items`, which the game does not
  clamp (past the end it just stops drawing further), so the end is found by
  scrolling one more and taking it back if the top row did not change. A
  click on a crop's name does nothing: its tick box does, and that box moves
  two columns left when the list has a scroll bar, so it is found as the
  first tile after the name that is not the row's background. The crop
  itself is `building_farmplotst.plant_id[season]` (-1 fallow); every-season
  fertilizing is `farm_flags.seasonal_fertilize`.
- Local constants defined further down the file (`TOP_ROWS`, `SHEET_COLS`)
  are nil in functions written above them, and a nil in a render function
  stops the overlay drawing on that screen and fills `stderr.log` every
  frame. Check `stderr.log` after loading any change to rendering.
- Building placement: the first `Enter` sets `buildreq.selection_pos` (x is
  -30000 when there is no corner; `Esc` clears it), and nothing else in
  `buildreq` follows the cursor until the second `Enter`, which fills
  `pos` and `total_sq` and moves on to the materials. The preview is drawn
  with `guidm.renderMapOverlay` (map tiles, `paintTile(..., true)`) using the
  `CURSORS` graphics DFHack's own placement tools use.
- Never keep a `findGraphicsTile` result across frames without checking it:
  the game reloads its graphics with each save it loads and the numbers
  change, so a pen made when the script loaded draws black squares after
  another save is loaded (the placement preview did this).
- Mouse messages posted to the window (`tools\sendmouse.ps1`) do not draw
  boxes: the game takes the pointer's position from the real mouse, not from
  the message, so mouse-driven behaviour cannot be tested that way.
- DFHack's own overlay on the work details page takes `M` (labor
  automation); the overlay's keys there must avoid it. The switch both use
  is `game.external_flag.automatic_professions_disabled`. With it clear the
  game does not continually re-apply work details either: labors set by hand
  survived two game days, until a detail was edited.
- Patch scripts must be written to a file, not passed through a shell
  heredoc: the heredoc halves backslashes, which turned `\\n` in a Lua
  string into a real line break twice.
- Removing a building is `dfhack.buildings.deconstruct`: it queues the
  game's own removal job on a started building and deletes an unstarted one
  on the spot, so for that case the sheet is closed first (a panel left open
  on a deleted building is the crash described below). A queued removal is a
  `DestroyBuilding` job on the building, removed again to call it off.
- A designation tool is changed by leaving the old one and entering the new,
  which puts the game's cursor back in the middle of the view; the overlay
  sets it back straight away and again a frame later.
- Chores page (`labor_standing_orders_interfacest`, category 5): `unit` and
  `labor_list` with their own scroll fields; everything is placed from the
  "Children do chores" button. Which list is in front is
  `ClassicKeysOverlay.chore_pane`.
- Sort headings: the named children of the `widget_columns_container` that is
  the first child of a list's `widget_table` (`rows.parent`); a click sorts.
- `Enter` in the Places list leaves the game's zone or stockpile panel open
  on the map; `query_opened_panel` then puts the overlay in `q` mode on it.
- Expelling: the sheet's panel has two steps; in the second, "Expel" is on
  the same row as "Cancel" (the game's "Cancel" closes the whole panel).
- A work detail's icon is `work_detail.icon` (0 to 18), a task's repeat is
  `job.flags['repeat']`, and a zone's own settings are in
  `zone.zone_settings`: all set directly, as nothing else depends on them.
- Probing an order button with one of the player's squads ticked changes
  that squad's orders: confirming a first patrol route replaces whatever
  order it had. Tick a squad with no orders, or note `squad.orders` first.
  (A lost station order can be read back from the soldiers'
  `unit.idle_area` while the game is still paused.)
- Run `cc-dev/test-build` from the bare map with no panel open; with the
  squads panel up its key presses tick squads instead and it reports failures.
- `dfhack.timeout(n, 'frames')` counts game-loop steps, several of which pass
  between redraws: wait about 10 before reading a screen that has just been
  scrolled.
- Screen size: the game places things in four ways, and a column written
  as a fixed number is only right for the first. Left-anchored (the info
  tabs, the top-left panels, the farm list); centred (`gps.dimx // 2`: the
  chores lists, the nobles' symbol button); in thirds (`gps.dimx // 3` and
  `2 * gps.dimx // 3`: the work order buttons, see `wo_button_x`); and
  right-anchored (`gps.dimx - n`: the right-hand sheets, `gps.dimx -
  SHEET_COLS - 2`, a location's remove and rename buttons, the new and
  remove work order buttons). Where a button is a picture with no text,
  `ClassicKeysOverlay.first_picture_x` finds it as the first cell whose
  texture differs from the row's background.
- On narrow screens the info tabs wrap onto two or three lines, the active
  tab's line nearest the content, and everything below moves down with
  them: `info_tabs_row()` is the lowest tab line and `fit_to_tabs` does the
  same for tabs inside a page (the labor pages).
- The game keeps a list's stored scroll after the window grows even when the
  whole list now fits, and draws from the top regardless: every row function
  clamps the stored value to `count - visible` before trusting it.
- `mi.entering_building_name` can be left set after `n` and `Esc` on a zone;
  while it is set DFHack sends no keys to overlays at all, so the overlay
  clears it on the bare map.
- Hauling: the panel's rows are `plotinfo.hauling.view_routes` and
  `view_stops` side by side (a stop's slot is empty on its route's own row),
  scrolled by entry with `hauling.scroll_position`. The row buttons are
  found from the right, where they end in the same column on every row:
  what comes before them varies (a stop shows its minecart and how full it
  is once the route has one). A long list puts a scroll bar, two columns
  wide, right of the buttons and moves them two columns left. A stop is
  placed by a map click (`click_map_tile`); Enter with the game's own
  keyboard cursor does nothing there. Its departure conditions are plain
  data (`timeout` in ticks, 1200 a day; `load_percent`; `flags.at_most`,
  `flags.desired`; `direction`; `mode`) and are set directly; adding and
  deleting go through the window's buttons. Its links window is the
  stockpile links window (`bld_id` -1, `hr_id` / `hs_id` the route and
  stop) with a third add button; its item settings are
  `custom_stockpile` with `sp` pointing at the stop's settings and no
  `abd`.
- How many rows a list or window shows is measured down to its bottom
  border (`rows_that_fit`): the hauling panel and its windows are as tall
  as the game makes them, whatever they hold. Counting the rows drawn does
  not work: once a list is scrolled to its end fewer rows are drawn, which
  then reads as fewer fitting.
- The game's own Esc while a route or stop is being named closes the
  panel and leaves `hauling.entering_nickname` set, with what was typed
  kept; the overlay handles that Esc itself.
- The game leaves `main_interface.stockpile.cur_bld` (and
  `civzone.cur_bld`) pointing at the last building shown, and loading
  another save does not clear them. Read them only while their panel is
  open: after a second load in one session the old pointer fails every
  frame (2,484 "cur_bld" errors in `stderr.log` on 2026-11-18, after a load
  from the title screen).
- `overlay.rescan()` (the dev reload) rebuilds every overlay widget, and
  DFHack's preserve-rooms box then lists only "None" until the next save is
  loaded: it fills its role list once per world load.
- `tools\gridtest.sh` runs the position-dependent checks above at whatever
  grid the game has (change it live in Settings, Video). It works only on
  the test save, refuses to run on any other, and undoes what it changes;
  its unit, farm plot and building positions are the test fort's.

## Not done yet

Run to the end on the test save (kept here so the results are on record):

- Trade: `t` with goods marked on both sides makes the trade. DFHack asks
  "Confirm trade" first and `Enter` answers yes. `s` reaches the Seize
  button (DFHack asks first), but the game greys that button out for a
  caravan of the fort's own civilization, so nothing was seized. `o` could
  not be tried: nothing of the fort's was left at the depot. The merchant's
  counter-offer has still not been seen.
- Nobles: `Enter` on a candidate appoints them.
- Justice: `Enter` on a dwarf in the convict list convicts them, after
  DFHack's "Confirm conviction" (`Enter` again). Interrogating was not run.
- Zones: attaching a zone to a location, changing it, taking it out again,
  and founding a new guildhall from the list of trades.
- The routine's Clear key (`X`): Esc keeps the orders, Enter clears them.
- Tasks: `x` cancels a workshop job, `r` takes its worker off, `p` switches
  repeat.
- A creature's sheet: `S` (joining and leaving a squad) and `E` (two dwarves
  were expelled; "Send to" another holding was reached but not confirmed).
- A location's details: counts by arrow and by typing, the visiting rule,
  filling and emptying an occupation, on the tavern and the hospital.
- Details of a workshop task and of work orders with one and with two
  options, with the filter; the name builder from a location and a squad;
  the chores page; sorting the creatures list; a work detail's icon.

Still worked with the mouse:

- The image chooser that a task's details open for an engraving or a
  statue ("specify image"). The details window lists the option, but the
  window behind it has no keys yet.
- A dye task's details have a second list (the dyes to mix) beside the
  colours; only the first list is on keys, and none of it was tested (the
  fort has no dye jobs).
- Naming a creature with the word builder ("first name" entry) is left to
  the game.
- The merchants' counter-offer on the trade screen: it never came up in
  testing, so there was nothing to measure.

Untested, though written:

- The fix for the leftover stockpile pointer was not tried with a second
  load in one session: quitting the fort from the options menu was refused
  by the harness's safety check. The read it guards is now made only while a
  stockpile's panel is open.
- DFHack's `S` on a room's preserve-rooms box: the overlay passes the key on
  (checked), and the box takes it when fed directly, but its role list was
  empty during the test (see the dev note on `overlay.rescan`).

- A creature's sheet: assigning work animals and occupations use the same
  `-` `=` and `Enter` as the work details, but no test dwarf had either.
- The details window from a workshop's own work order tab, and the new-order
  list opened from there.
- A temple's and a library's details (the tavern, hospital and guildhall
  were the ones tried), and an improvement task's details (no filter box, so
  its list is assumed to start 3 rows higher).
- The patrol route and burrow lists were tested with one or two entries;
  scrolling a long list is written but untested.

Known limits:

- This version of the game marks whole stacks and has no item view on the
  trade screen, and the old `p` (ticked items first) on the move-goods screen
  has no button, so there is nothing to put on a key for those.
- Renaming a uniform sets its name directly (the game offers no way to do
  it); soldiers already wearing it keep the old name on their own rows.
- Screen size. The overlay works in the game's grid of cells, not in
  pixels, so the monitor's resolution only matters through the grid it
  gives. It was tested at three grids (Settings, Video, "Desired grid
  width/height"): 128x48, the normal 174x65 and 240x90. Every screen whose
  buttons are placed by position (tasks, work orders and their conditions,
  nobles, places, chores, the creature sheet, zones, location details, the
  name builder, the farm plot, building placement) passes at all three
  after the fixes listed under "Working on it". Two limits remain on small
  grids:
  - At 128 columns (probably anything under about 140) a work order's
    details button is covered by the game's own "Can use any shop" label,
    so `d` on the work orders tab does nothing; the mouse cannot click it
    either.
  - Under about 152 columns the key list in the top left overlaps the
    sheets the game draws on the right (creature, building, farm plot). The
    keys still work; only the two drawings overlap.
- Still untested: classic ASCII graphics (the button and tick-box finders
  compare tile textures, which ASCII draws differently), TrueType text
  (screens are found by reading their text with `dfhack.screen.readTile`,
  which TrueType text may defeat), and languages other than English.
- The game shows its own placement panel (size and materials) only while
  the real mouse pointer is over the window. With the pointer elsewhere the
  game draws its own building outline at the keyboard cursor instead, so
  placement still works.
- `z` opens stocks only; the old combined status screen has no equivalent in
  the new game.
- The world map (`c`) cannot be zoomed. The game's zoom keys (`[` and `]`,
  Ctrl+wheel) do nothing on that screen, and neither does the zoom factor
  the fort map uses (`gps.viewport_zoom_factor`): its scale is fixed inside
  the game, out of DFHack's reach. A zoomed view would have to be a map of
  the overlay's own, drawn from the world's data (biome, elevation, sites)
  in a window of its own; that is not built.
