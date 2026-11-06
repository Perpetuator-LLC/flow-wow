# Changelog

## 0.24.0
- Route colours back to green (your route) and yellow (a route you preview); your route turns blue
  while previewing and the stop under the mouse is red. "Colour-blind route colours" in
  /flow settings and /flow setup switches to orange / purple / sky blue.
- Splash is gone in about half a second.
- `/flow nav unhide` brings back every stop you hid; `/flow nav hidden` lists them.
- Stops that cost money you don't have (class training) are skipped and remembered. They
  come back on the route by themselves once you can pay, planned by distance like any other
  stop, so the trainer goes to the top when you're near it (e.g. after a hearth).
  `/flow nav why` lists what was skipped. If you can afford only some spells, the stop says so.

## 0.23.0
- Fixed: the vendor drawer didn't appear (it checked the vendor window before the game showed it).
- Auto-sell junk when you open a vendor, no confirmation (on by default; /flow setup).
- First-run setup now opens 30 seconds after login, well after the splash.
- Fixed: a shield could show as a DPS upgrade with a lower score ("better in every stat" compared
  it with a two-hander). That rule now only compares like with like, and Retribution never treats
  shields or off-hands as DPS upgrades.
- Armor counts more for DPS and Heal while levelling.
- Fixed: Kobold Candles and Gold Dust Exchange were marked [Elite]; an objective is elite only if
  every mob that drops the item is elite.
- `/flow gear why` (and the diagnostics) show each bag item's stats, scores and comparisons.

## 0.22.3
- Removed the Questie button from the Flow Tracker header; the two trackers still work as an
  accordion through their own headers. Splash fades out in 300 ms.

## 0.22.2
- Load splash: the two gold bars count down how long it stays (top empties left to right, bottom
  right to left); when they're empty the splash is gone.

## 0.22.1
- Map: thin, unbroken route lines through small round points; your route is orange (like the
  arrow), a previewed route purple. Each point shows its stop-type icon.
- New HUD-style arrow: a glowing line-drawn chevron with a ring that marks the direction.

## 0.22.0
- Stops are colour-coded by type, each with an icon too: accept (yellow !), turn in (yellow ?),
  daily (blue), kill (red skull), collect (orange diamond), use (tan), talk (green), profession
  trainer (purple), class trainer (teal), merchant (gold), hearthstone (white), skill-up (green),
  waypoint and party (sky blue). The stop the arrow points at has an orange number.
- Flow Tracker on screen, working as an accordion with Questie's tracker (blue Questie button).
- Map: the Flow route header sits just above the quest log; open it covers the quest log, rolled up
  the quest log is back.
- Merchant stop when there is enough to sell (or bags nearly full) and a merchant is on the way.
- Profession picker: offered in the advice list from level 3, `/flow professions`, setup row.
- "Accept" instead of "Pick up".
- Fixed: hovering checkpoints no longer re-plans every time (previews are cached).
- Fixed: professions are read through the newer API, so learned ones clear their trainer stops.

## 0.21.0
- Route planner: Flow checks quest availability itself (earlier quests in the chain done, race,
  class, level). It no longer sends you to pick up quests you can't take yet.
- Picks up the quests in the hub you're in before heading out (within ~250 yd), and never plans
  more pickups than your quest log has room for.
- Elite objectives are marked [Elite] and planned later.
- Hearthstone stop recognises the inn name as well as the town.
- `/flow nav why` (and the saved diagnostics) list the full planned route.

## 0.20.0
- Hearthstone: no more pop-up. While levelling, the route gets a "Set hearthstone" stop at the
  local inn when yours is set elsewhere (`/flow hearth off` to stop).
- Hide any stop: right-click it on the map or in the route list. "Show hidden stops" lists them
  greyed out; click one to bring it back.
- Setup table: tick boxes show each setting's current state; Apply turns things on or off to
  match. Quick picks: All, None, Flow suggests, WoW default, Reset. The Set button has its own column.

## 0.19.1
- Spec icons (Retribution, Holy, Protection) replace DPS / Heal / Tank words, dots and letters in
  tooltips, bag icons and quest reward badges.
- Fixed: an item at least as good in every stat (e.g. a belt with only more armor) is now an upgrade
  for every role; armor also weighs more for DPS and Heal.

## 0.19.0
- Vendor drawer: "Sell all junk" (every grey item, on by default) plus up to 12 proposed items with
  their own Sell buttons; Sell All sells junk first so the proposed ones stay in the buyback tab;
  "Sold this visit" with Buy back; buttons grey out and the drawer folds away when done.
- Hearthstone reminder when you rest at an inn that isn't your home (once per inn; stronger when
  most of your route is in that zone). `/flow hearth on|off`.
- Nicer "Flow route" bar on the map panel.

## 0.18.0
- First-run setup table (`/flow setup`): auto loot, nameplates, instant quest text, auto-placing new
  spells, max zoom, chat timestamps, combat log file, cast key, Questie. Tick and Apply.
- Key binding mode (`/flow bind`): hover a button and press a key; changes are listed and only
  saved on Save. Ctrl+Z undo, Esc cancel (asks first with more than 3 changes; Esc again returns).
- Auto-placed spells: Flow says when the game puts a new spell on your bars and marks those bars
  (hover the book icon); `/flow autoplace` lists them.

## 0.17.6
- Diagnostics Claude can read from disk: Flow logs its errors and takes a snapshot of its checks on
  every `/reload` and logout (saved with Flow's data). `/flow dump` captures one on demand;
  `toolsead-diag.ps1` prints it.

## 0.17.5
- Profession and class trainers are found by NPC ID (with a name check) as well as by name, and
  Questie zones fall back to matching the game's own map names, so trainer stops show up.
- "Include professions" on the map panel (and `/flow nav professions on|off`).
- `/flow nav why`: what the route is made of and which places Flow couldn't find.

## 0.17.4
- Seal of Righteousness is suggested again a few seconds before it runs out (Forever's Judgement no
  longer uses it up), and Blessing of Might when it has under 30s left out of combat.
- `/flow rot guide`: your rotation in plain words, using the spells you have.

## 0.17.3
- Map route panel: "Click a stop to follow that route" hint, and a choice between **Follow current
  quests** (only quests in your log) and **Follow optimal path** (also pickups, trainers, skill-ups).
  Also `/flow nav quests|optimal`.

## 0.17.2
- The advice button is now a round minimap-style spyglass with an orange count bubble, and it pulses
  briefly when something important appears.

## 0.17.1
- The map route list no longer covers the map: it takes over the quest log area (or sits just
  right of the map) as a routed quest list, with an orange "Hide / Show Flow route" bar to roll
  it up and get the game's own map and quest log back.

## 0.17.0
- Joining a group asks automatically: follow the party route or keep yours. Party and personal
  routes are separate; switch any time with the toggle under the arrow.
- Forming a group as leader makes a party route by itself: quests members share come first
  (members exchange quest lists), otherwise your current route.

## 0.16.0
- Name: Flow (unfettered).
- Shared party routes: `/flow party share`; party members join with one click and anyone can
  edit (choose stops, add waypoints, reach stops). The latest edit wins for everyone; nobody owns it.

## 0.15.1
- Max camera zoom on by default; untick it in `/flow settings` (or `/flow zoom off`) for the game default.

## 0.15.0
- Fixed: the cast key did nothing on some clients. `/flow key test` shows what your key does.
- Route adds a class-trainer stop by itself when you level into new spells.
- Trip plan is colour-coded (orange = next stop, blue = quest pickups, sky blue = your waypoint)
  and listed beside the world map; hover a row to preview, click to choose.
- README banner.

## 0.14.0
- Choose your route: click a place in the advice list or a checkpoint on the world map. Picking a
  quest pickup (`!N`) routes you through all the pickups first.
- World map route with numbered checkpoints and quest levels; hover to preview another route.
  Colour-blind safe colours.
- Your own waypoint: Ctrl- or Alt-click the map, or `/flow way`.

## 0.13.0
- Keep icons in bags: a quest "!" for items your quests need, and profession icons for crafting
  materials. Tooltips explain every decision.

## 0.12.0
- Bag icons (equip, sell, AH, DE). The vendor panel sells 12 at a time with one-click buy back
  and learns what not to sell.

## 0.11.0
- Cast button and key, with conflict-aware key binding in a new settings window.

## 0.10.0
- Whole-trip route planner, stance-bar auras, chat timestamps.

## 0.9.0 and earlier
- Rotation helper, smart self-heals, fight profiler, combat log reports, advisor, gear scores
  per role and gear sets, quest markers, missed quests, navigation arrow with learned trails,
  load splash, help.
