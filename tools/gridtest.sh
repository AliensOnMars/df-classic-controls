#!/bin/bash
# Smoke test of the screens whose buttons are placed by position, at whatever
# grid the game has now. Runs on the test save only; every change is undone.
# It was written against the author's test fort ("cc-test"): the creature,
# farm plot and building positions below are that fort's, so another save
# needs them changed. Set DF_DIR (the game's folder) and DFHACK_RUN
# (dfhack-run.exe) first, in Git Bash paths, e.g.
#   DF_DIR="/c/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress"
#   DFHACK_RUN="/c/Program Files (x86)/Steam/steamapps/common/DFHack/hack/dfhack-run.exe"
R="${DFHACK_RUN:?set DFHACK_RUN to dfhack-run.exe}"
DFDIR="${DF_DIR:?set DF_DIR to the game folder}"
SK="$(cd "$(dirname "$0")" && pwd)/sendkeys.ps1"
K() { powershell -NoProfile -File "$SK" "$@" 2>&1 | head -2; sleep 0.9; }
L() { "$R" lua "$1" 2>&1 | head -1; }
focus() { L "print(table.concat(dfhack.gui.getCurFocus(true),'|'))"; }
to_map() {
  for i in 1 2 3 4; do
    f=$(focus)
    case "$f" in
      dwarfmode/Default) return;;
      *Options*) "$R" cc-dev/click-text "Return to game" >/dev/null 2>&1; sleep 0.8;;
      *) K esc;;
    esac
  done
}
save=$(L "print(df.global.world.cur_savegame.save_dir)")
[ "$save" = "cc-test" ] || { echo "NOT THE TEST SAVE ($save) - stopping"; exit 1; }
echo "grid: $(L "print(df.global.gps.dimx..'x'..df.global.gps.dimy)")"
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1  ($2)"; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "got '$2' want '$3'"; fi; }
to_map

# --- Tasks: suspend (col 44) and zoom (col 32) on a workshop job ----------------------
K j
IDX=$(L "local info=df.global.game.main_interface.info; for i=0,#info.jobs.cri_job-1 do local j=info.jobs.cri_job[i].jb; if j then local h=dfhack.job.getHolder(j); if h and df.building_workshopst:is_instance(h) and not j.flags.suspend then print(i..' '..j.id) return end end end")
set -- $IDX; N=$1; JID=$2
L "reqscript('classic-controls').overlay_instance.pl_idx=$N"; sleep 0.4
SUSP="local j; for _,x in require('utils').listpairs(df.global.world.jobs.list) do if x.id==$JID then j=x end end; print(tostring(j and j.flags.suspend))"
K s; check "tasks: s suspends" "$(L "$SUSP")" "true"
K s; check "tasks: s again resumes" "$(L "$SUSP")" "false"
V0=$(L "print(df.global.window_x..','..df.global.window_y)")
K z; V1=$(L "print(df.global.window_x..','..df.global.window_y)")
[ "$V0" != "$V1" ] && pass "tasks: z zooms" || fail "tasks: z zooms" "view did not move"
to_map

# --- Work orders --------------------------------------------------------------------------
K o
WO="local wo=df.global.game.main_interface.info.work_orders; print(tostring(wo.entering_number)..','..tostring(wo.b_entering_number)..','..tostring(wo.conditions.open)..','..tostring(df.global.game.main_interface.job_details.open))"
K a; check "orders: a amount box" "$(L "$WO")" "true,false,false,false"; K esc
K t; check "orders: t workshop limit box" "$(L "$WO")" "false,true,false,false"; K esc
K c; check "orders: c conditions" "$(L "$WO")" "false,false,true,false"
  FQ=$(L "print(df.global.world.manager_orders.all[0].frequency)")
  K f; check "orders: conditions f frequency" "$(L "print(df.global.world.manager_orders.all[0].frequency ~= $FQ)")" "true"
  L "df.global.world.manager_orders.all[0].frequency=$FQ"
  K a; check "orders: conditions a adds" "$(L "print(#df.global.world.manager_orders.all[0].item_conditions)")" "1"
  K i; check "orders: condition i item type list" "$(L "print(df.global.game.main_interface.info.work_orders.conditions.change_type)")" "0"; K esc
  K d; check "orders: conditions d deletes" "$(L "print(#df.global.world.manager_orders.all[0].item_conditions)")" "0"
  K esc
K d; check "orders: d details" "$(L "$WO")" "false,false,false,true"; K esc
T0=$(L "print(df.global.world.manager_orders.all[0].id)")
K shift+p; K p; check "orders: P then p puts it back" "$(L "print(df.global.world.manager_orders.all[0].id)")" "$T0"
K q; check "orders: q new-order list" "$(focus)" "dwarfmode/Info/WORK_ORDERS/Create"; K esc
to_map

# --- Nobles ------------------------------------------------------------------------------------
K n
L "reqscript('classic-controls').overlay_instance.noble_idx=1"; sleep 0.3
K enter; check "nobles: Enter lists candidates" "$(L "print(tostring(df.global.game.main_interface.info.administrators.choosing_candidate))")" "true"; K esc
K shift+s; check "nobles: S lists symbols" "$(L "print(tostring(df.global.game.main_interface.info.administrators.assigning_symbol))")" "true"; K esc
BK=$(L "local top=reqscript('classic-controls').ClassicKeysOverlay.info_tabs_row(); local w,h=dfhack.screen.getWindowSize(); for y=top+7,h-1 do local s={} for x=4,30 do local t=dfhack.screen.readTile(x,y); s[#s+1]=(t and t.ch>=32 and t.ch<127) and string.char(t.ch) or ' ' end if table.concat(s):find('Bookkeeper',1,true) then print((y-top-7)//3 + df.global.game.main_interface.info.administrators.scroll_position_noblelist) return end end")
P0=$(L "print(df.global.plotinfo.nobles.bookkeeper_settings)")
if [ -n "$BK" ]; then
  L "reqscript('classic-controls').overlay_instance.noble_idx=$BK"; sleep 0.3
  K 2; check "nobles: bookkeeper 2" "$(L "print(df.global.plotinfo.nobles.bookkeeper_settings)")" "1"
  K $((P0 + 1)); check "nobles: bookkeeper back" "$(L "print(df.global.plotinfo.nobles.bookkeeper_settings)")" "$P0"
else
  fail "nobles: bookkeeper" "row not found"
fi
to_map

# --- Places: zoom and open ------------------------------------------------------------------
K j; K tab
V0=$(L "print(df.global.window_x..','..df.global.window_y)")
K z; V1=$(L "print(df.global.window_x..','..df.global.window_y)")
[ "$V0" != "$V1" ] && pass "places: z zooms" || fail "places: z zooms" "view did not move"
to_map; K j; K tab
K enter; sleep 0.3; check "places: Enter opens the zone" "$(focus | cut -d/ -f1-2)" "dwarfmode/Zone"
to_map

# --- Chores ---------------------------------------------------------------------------------------
K y; K shift+right
for i in 1 2 3 4 5; do K right; done
CH="local li=df.global.plotinfo.labor_info; local n=0 for i,v in ipairs(li.chores) do if v then n=n+1 end end; print(n..'/'..#li.chores_exempted_children)"
C0=$(L "$CH")
L "reqscript('classic-controls').ClassicKeysOverlay.chore_pane=1"
K left; K right; sleep 0.3
K enter; C1=$(L "$CH"); K enter; C2=$(L "$CH")
[ "$C0" != "$C1" ] && [ "$C0" = "$C2" ] && pass "chores: Enter on a chore and back" || fail "chores: Enter on a chore" "$C0 -> $C1 -> $C2"
K left; K enter; C3=$(L "$CH"); K enter; C4=$(L "$CH")
[ "$C0" != "$C3" ] && [ "$C0" = "$C4" ] && pass "chores: Enter on a child and back" || fail "chores: Enter on a child" "$C0 -> $C3 -> $C4"
to_map

# --- Creature sheet: expel button, labor page ---------------------------------------------------
L "local u; for _,c in ipairs(dfhack.units.getCitizens()) do if dfhack.units.getReadableName(c):find('Logemabsam') then u=c end end; local o=reqscript('classic-controls').overlay_instance; local x,y,z=dfhack.units.getPosition(u); o.cursor=xyz2pos(x,y,z); dfhack.gui.revealInDwarfmodeMap(o.cursor, true)"
K v
K shift+e; check "sheet: E opens expel" "$(L "print(tostring(df.global.game.main_interface.view_sheets.unit_overview_expelling))")" "true"; K esc
K p
K t; check "sheet: t only-assigned on" "$(L "print(tostring(df.unit.find(df.global.game.main_interface.view_sheets.active_id).flags4.only_do_assigned_jobs))")" "true"
K t; check "sheet: t off again" "$(L "print(tostring(df.unit.find(df.global.game.main_interface.view_sheets.active_id).flags4.only_do_assigned_jobs))")" "false"
to_map

# --- Zone buttons, location details, name builder --------------------------------------------------
"$R" cc-dev/test-zone make MeetingHall >/dev/null 2>&1
L "reqscript('classic-controls').overlay_instance:query_opened_panel()"; sleep 0.4
ZF="local z=df.global.game.main_interface.civzone.cur_bld; print(tostring(z and z.spec_sub_flag.active))"
A0=$(L "$ZF"); K s; A1=$(L "$ZF"); K s
[ "$A0" != "$A1" ] && pass "zone: s suspends" || fail "zone: s suspends" "$A0 -> $A1"
K l; check "zone: l location list" "$(L "print(tostring(df.global.game.main_interface.location_selector.open))")" "true"
K enter; check "zone: attached" "$(L "print(df.global.game.main_interface.civzone.cur_bld.location_id)")" "0"
sleep 0.5; K d; check "zone: d location details" "$(L "print(tostring(df.global.game.main_interface.location_details.open))")" "true"
INS="print(df.global.game.main_interface.location_details.selected_ab.contents.desired_instruments)"
I0=$(L "$INS"); L "reqscript('classic-controls').overlay_instance.ld_idx=1"; sleep 0.3
K right; I1=$(L "$INS"); K left; I2=$(L "$INS")
[ "$I1" = "$((I0 + 1))" ] && [ "$I2" = "$I0" ] && pass "location: + and - counts" || fail "location: counts" "$I0 -> $I1 -> $I2"
K n; check "location: n name builder" "$(L "print(tostring(df.global.game.main_interface.name_creator.open))")" "true"
K esc; sleep 0.5; K esc; sleep 0.5
K l; sleep 0.3; K r; check "zone: l r takes it out" "$(L "print(df.global.game.main_interface.civzone.cur_bld.location_id)")" "-1"
to_map
"$R" cc-dev/test-zone remove >/dev/null 2>&1

# --- Farm plot --------------------------------------------------------------------------------------
L "local o=reqscript('classic-controls').overlay_instance; o.cursor=xyz2pos(53,25,176); dfhack.gui.revealInDwarfmodeMap(xyz2pos(53,25,176), true)"
K q; sleep 0.4; K c
FC="local b=df.building.find(51); print(b.plant_id[2])"
F0=$(L "$FC"); K equals; K enter; F1=$(L "$FC"); K minus; K enter; F2=$(L "$FC")
[ "$F0" != "$F1" ] && [ "$F0" = "$F2" ] && pass "farm: plant and put back" || fail "farm: plant" "$F0 -> $F1 -> $F2"
to_map

# --- Placement key list beside the game's panel -------------------------------------------------------
L "local o=reqscript('classic-controls').overlay_instance; o.cursor=xyz2pos(87,183,146); dfhack.gui.revealInDwarfmodeMap(xyz2pos(87,183,146), true)"
K b; K w; K c; sleep 0.5
echo "INFO  placement key list at column $(L "print(reqscript('classic-controls').overlay_instance.subviews.panel.frame.l)") (game panel shown only with the pointer over the window)"
to_map

echo "errors logged: $(grep -c 'classic-controls' "$DFDIR/stderr.log")"
