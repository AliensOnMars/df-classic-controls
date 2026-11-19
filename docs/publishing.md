# Publishing to the Steam Workshop, and testing the Workshop copy

## How the pieces fit

- **Source**: this repository. While you work on it, your game runs it
  straight from `scripts\` (the *working copy*), through the line
  `+<repository>/scripts` in the game's `dfhack-config\script-paths.txt`.
- **Package**: `tools\build-mod.ps1 -Stage` builds
  `dist\spriksprak_classic_controls\` (plus a zip of it for GitHub) and copies
  it into the game's upload folder,
  `%APPDATA%\Bay 12 Games\Dwarf Fortress\mods\mod_upload\`.
- **Workshop item**: the game's own Mods screen publishes whatever is in that
  upload folder. Subscribers get it in
  `<Steam library>\steamapps\workshop\content\975370\<item id>\`, where DFHack
  finds it by itself: the mod never has to be added to a world.
- While the working copy is switched on it hides any installed copy, the
  Workshop one included. `tools\dev-scripts.ps1` switches it off and on.

Commands below are run in PowerShell from the repository's folder.

## First publish

1. Build the package and put it in the upload folder:

       powershell -ExecutionPolicy Bypass -File tools\build-mod.ps1 -Stage

2. Start the game, or restart it if it is running: it only looks in the
   upload folder when it starts.
3. On the title screen choose **Mods**. Besides the installed mods the screen
   then has a **Publish mods** part listing Classic Controls, with its Steam
   title and description and "Steam file id: None yet". Click **Publish** and
   wait for the upload to finish.
   - Not listed? Look at the end of `errorlog.txt` in the game's folder for
     a line like `Mod ... skipped: ...`. (The game refuses mod IDs that start
     with "classic", which is why the ID is `spriksprak_classic_controls`.)
4. After the upload the file id shows a number, and the game has written
   `[STEAM_FILE_ID:<number>]` into the staged `info.txt`. Add that same line
   to `mod\info.txt` here and commit it. It is what makes later publishes
   update this item instead of creating a new one. (`build-mod.ps1 -Stage`
   also keeps it, and warns, if it is only in the staged copy.)
5. Open the item in Steam: Community, Workshop, Dwarf Fortress, Browse, Your
   Files (or `https://steamcommunity.com/sharedfiles/filedetails/?id=<number>`).
   - The first time, Steam asks you to accept its Workshop legal agreement;
     until then nobody else can see the item.
   - Set **Visibility** to Private (or Friends-only) while you test it.
   - Check the title, the description and the preview picture. The
     description can be edited on that page, with Steam's formatting codes.

## Testing it as a player gets it

1. On the item's page click **Subscribe**. Steam downloads it: look for
   `<Steam library>\steamapps\workshop\content\975370\<item id>\info.txt`.
2. Switch your working copy off:

       powershell -ExecutionPolicy Bypass -File tools\dev-scripts.ps1 off

3. Start the game through DFHack (restart it if it is running) and load a
   fort, preferably one from a world made before you subscribed: that also
   checks that the mod needs no adding to a world.
4. Check that the Workshop copy is the one running:

       powershell -ExecutionPolicy Bypass -File tools\dev-scripts.ps1 status

   It should end with "the running game is using:
   ...\workshop\content\975370\<item id>\scripts_modinstalled\classic-controls.lua".
   The repository's `scripts` folder there means the working copy is still
   on; "not found" means Steam has not downloaded the item or DFHack is not
   running.
5. Then, in the game:
   - `?` on the map shows the main menu of keys; `d` opens the designation
     menu with its key list.
   - DFHack's launcher (the `` ` `` key) runs `classic-labors preview`.
   - The item's folder has `therapist\v0.53.17-steam_win64.ini`, `docs\` and
     the README.
   - Nothing about the mod at the end of the game's `errorlog.txt`.
6. Switch your working copy back on and restart the game:

       powershell -ExecutionPolicy Bypass -File tools\dev-scripts.ps1 on

   You can stay subscribed: with the working copy on, it wins.
7. When you are happy with it, set the item's visibility to **Public**.

## Publishing an update

1. In `mod\info.txt`: raise `[NUMERIC_VERSION:...]` by one and change
   `[DISPLAYED_VERSION:...]` (and the two `EARLIEST_COMPATIBLE` lines if old
   saves would not work with it), and set `[STEAM_CHANGELOG:...]`. Add an
   entry to `CHANGELOG.md`.
2. Build and stage again: `tools\build-mod.ps1 -Stage`. It keeps the item's
   file id.
3. Restart the game, Mods, **Publish**. Subscribers get the new version the
   next time Steam updates the game's Workshop items.
4. GitHub: commit, tag (`git tag vX.Y.Z`, `git push --tags`) and make a
   release with the zip from `dist\`. If a game update needed a new Dwarf
   Therapist layout, add it to `therapist\` and attach a fresh
   `tools\build-therapist-bundle.ps1` zip as well.

## If something goes wrong

- **Not listed under Publish mods**: restart the game; then check
  `errorlog.txt` for "skipped".
- **The upload fails**: Steam has to be running and signed in to the account
  that should own the item.
- **No keys after subscribing**: the game has to be started with DFHack;
  `tools\dev-scripts.ps1 status` says which copy is loaded.
