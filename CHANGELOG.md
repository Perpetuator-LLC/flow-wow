# Changelog

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
