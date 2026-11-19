# Dwarf Therapist memory layouts

Dwarf Therapist v42.1.21 (the latest release) ships memory layouts only up
to Dwarf Fortress 53.02, so against later builds it finds the game and then
stops with "Unidentified Game Version". The layouts here were written by
DFHack's `devel/export-dt-ini` against the Steam release, and checked with
Therapist v42.1.21: names, squads, labors and skills read correctly, and
labor changes made in Therapist reach the game.

| File | Game build |
|---|---|
| `v0.53.17-steam_win64.ini` | Dwarf Fortress 53.17, Steam, Windows 64-bit (build stamp `0x6aea05a1`) |

To use one, copy it into `<Dwarf Therapist folder>\data\memory_layouts\windows\`
and start Therapist. The GitHub release also has a ready-to-run copy of
Therapist v42.1.21 with these layouts already in place
(`DwarfTherapist-v42.1.21-win64-df53.17.zip`).

A layout only fits the game build it was made for. For a newer build, make a
new one from the running game with `tools\update-therapist.ps1` (see
`docs/labors-and-therapist.md`), or look for an updated Therapist release.
