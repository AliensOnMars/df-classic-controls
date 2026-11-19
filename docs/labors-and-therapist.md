# Labors and Dwarf Therapist

## Labors: why everyone does everything, and the classic alternative

In this version of the game a labor is not something a dwarf has or lacks:
labors are handed out by work details, and **any labor that no work detail
restricts is done by every adult**. A new fort's details only restrict a
handful (miners, woodcutters, hunters, fisherdwarves, engravers); carpentry,
masonry, smelting, brewing and some forty others are in no detail at all. So
every dwarf really is set to do them, which is exactly what Dwarf Therapist
shows. It is the game's default, not something Therapist or this project
did.

Three ways to narrow it:

- The game's own: add a work detail for a labor, set it to "Only selected do
  this" and tick the dwarves (Labor tab, `a`, `N`, `2`, `e`).
- DFHack's labor automation: `M` on the work details page steps through
  off / legacy (autolabor) / modern (labormanager) / monitor. Autolabor keeps
  re-assigning labors by skill and by what work is waiting; anything set by
  hand is overwritten while it runs.
- Classic labors, in this project: labors per dwarf as they were in 0.47.05,
  with a sensible start, then left alone for you to edit.

Classic labors (`c` on the Labor tab's work details page, or the command
`classic-labors on` in DFHack's console):

- The work details are set aside (the same switch as Therapist's "Allow
  labor changes") and each adult is given exactly two things.
- The core labors, on for everyone because they need no skill: stone, wood,
  item, furniture, food, refuse, water, trade good and animal hauling,
  burial, push/haul vehicles, cleaning, lever operation, construction,
  construction removal, road building, recovering wounded and feed
  patients/prisoners. (Therapist's table has no "alchemy" labor in this
  version of the game.)
- Each skilled labor in which the dwarf is at least a novice, and no other.
  A labor nobody in the fort is a novice at therefore ends up with nobody:
  the command lists those, and they are yours to hand out in Therapist. In a
  new seven-dwarf fort that is most of them (50 of 65).
- Mining, woodcutting and hunting need a tool and exclude one another, so a
  dwarf skilled in more than one gets the one it is best at. Hunting goes by
  the ambusher skill, as in Therapist, not by weapon skills.
- A dwarf holding a hospital post (chief medical dwarf, doctor,
  diagnostician, surgeon, bone doctor) keeps its medical labors as they are,
  skilled or not.
- After that first pass a dwarf's labors are changed only by you (Dwarf
  Therapist is the tool for it). A newcomer, or a child coming of age, gets
  the same defaults once, on arrival.
- `classic-labors preview` shows what switching on (or `apply`) would change,
  labor by labor, without changing anything.
- The setting is kept in the fort's save, and the overlay puts the switch
  back each time the fort is loaded (the game forgets it), so Therapist's
  box does not need ticking every session.
- `c` again (or `classic-labors off`) hands labors back to the work details;
  the game re-assigns them the next time a work detail is edited.
  `classic-labors apply` gives everyone the defaults again.
- While it is on, the Labor tab's key list says "details set aside": ticking
  dwarves in work details has no effect then. It will not switch on while
  DFHack's labor automation is running, and stands aside if that is started.

Tested: on the test fort an earlier, looser version of the rule held while
the game ran and a simulated newcomer got the defaults. The rule above was
applied to a seven-dwarf fort: every dwarf ended with the 18 core labors
plus only its own skilled ones (the miners mining, the doctor the five
medical labors, and so on). Not tested: a real migrant wave, the tool-labor
tie-break (nobody there had two of the three skills), and loading a save
with it on.

## Dwarf Therapist

Dwarf Therapist (v42.1.21, the latest release when this was written) reads
the game's memory and needs a "memory layout" file for each build of the
game. It ships them up to 53.02, so against 53.17 it finds the game and then
stops with "Unidentified Game Version". DFHack can write the missing file for
whatever version is running, and with it Therapist connects and reads the
fort (names, squads, labors, skills checked against the test fort).

After each game update, with the game running through DFHack and a fort
loaded (from a copy of this repository):

    tools\update-therapist.ps1 -TherapistDir "<your Dwarf Therapist folder>"

It runs DFHack's `devel/export-dt-ini` and moves the result into Therapist's
`data\memory_layouts\windows` folder under the name Therapist expects
(`v0.53.17-steam_win64.ini`). Then start Therapist. `-GameDir` and
`-DfhackRun` point it at a game installed somewhere other than Steam's
default library.

- The layout only says where things are. If a game update changes what a
  structure means, Therapist itself needs a new release; a column that looks
  wrong after an update is the sign.
- Writing works too, tested on the test fort: with "Allow labor changes"
  ticked, a labor switched in the grid and "Commit" set that labor on the
  dwarf in the game, it was still set after the game ran on, and switching
  it back and committing cleared it again.
- "Allow labor changes" is what makes that stick. It tells the game to stop
  assigning labors from work details (`game.external_flag` becomes 1), for
  the current session only: tick it again each time a fort is loaded, or the
  game overwrites what Therapist set. Unticking it hands labors back to the
  work details. Therapist's own note says DFHack's `labormanager` must be
  off while it is used.
- Therapist's check for updates may fail ("TLS initialization failed" in its
  log), which does not affect anything else.
