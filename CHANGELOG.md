# Changelog

## 0.35.53
- The camera stays where you put it: the game's "Camera Following Style" swung it back behind
  you whenever you moved. Flow switches it to Never once (you asked); it's a suggested setting
  in Options > AddOns > Flow if you want it back.
- The arrow can turn three ways (right-click it, "Arrow turns"): north-up (the default, fixed
  to the screen: it only turns as the direction to the stop changes), with my character, or
  like my minimap (turns with you if your minimap rotates, north-up if it's locked).
- Flow Router: one "Route:" dropdown (current quests, optimal with or without professions,
  completionist, and the order) instead of two checkboxes and a sub-box that couldn't reach
  Completionist. The route list moved up into the space.
- Flow Seller: an "Auto-sell" switch on the drawer's header, and both auto-sell switches (all,
  and grey junk) in Options > AddOns > Flow.
- README brought up to date with everything since 0.35.

## 0.35.52
- Auto-sell: opening a vendor now also sells everything else Flow marks "sell" (gear you've
  outgrown, outgrown food and drink, unused materials...), not just grey junk. Up to 12 a visit,
  the size of the vendor's buyback tab, so anything sold by mistake can be bought back from
  Flow's vendor drawer; buying it back tells Flow never to sell that item again. More than 12:
  the rest go on the next visit. On by default; Options > AddOns > Flow: "Auto-sell everything
  Flow marks to sell".

## 0.35.51
- Fixed: a finished quest's turn-in right next to you waited behind every quest pickup in the
  hub. A hub's business now includes ready turn-ins with the pickups (like a walkthrough: hand
  in, pick up, head out), and each turn-in frees a quest log slot for the pickups.
- North-up arrow (the default): the arrow points the way on the screen like a map, up = north.
  Right-click the arrow ("North-up arrow"), Options > AddOns > Flow, or /flow nav northup to
  switch back to turning with your character. (Add-ons can't read the camera's direction.)
- "Point the arrow here (your waypoint)" on every stop's right-click menu (world map, Flow
  Router, Flow Tracker): the arrow goes there first; the planned route stays as it is. Any spot
  on the map: Alt-click it.
- Selling: food and drink you've outgrown is marked to sell once you carry 10+ of a better tier
  of the same kind for your level.
- Lite mode in dungeons, raids and boss fights: route planning pauses, the arrow and minimap
  update twice a second, the map and tracker refresh every 2 s, the minimap areas pause. The
  rotation, the Flow key and bags run as normal.
- Flow Tracker: a faint line down the left of the stops with a small down chevron at the end:
  the order runs top to bottom.

## 0.35.50
- Minimap areas are one smooth shape per group of spawns, like the world map's areas, instead
  of the outline of many circles. Only your current stop's area shows (and the one you hover
  in the Flow Tracker).
- The better / worse arrows above the spec icons are always full strength (they faded with
  the spec icons for specs you aren't levelling).
- Learning from your bags: anything you can learn right now (a recipe, a scroll or book that
  teaches you something, not already known) is offered on the Flow key: "Learn: X". When your
  bags are full it comes first: learning frees the slot.
- Nearest repair and nearest vendor: right-click the arrow ("Nearest repair", "Nearest vendor
  (sell)") or /flow way repair | vendor. Flow sets your waypoint on the closest one it knows:
  merchants you've visited (it now remembers which ones repair) and every vendor and repairer
  in Questie's data. When it's far, it reminds you where your hearthstone goes.

## 0.35.49
- Fixed a blocked action: the world map's own pins were blocked in combat ("taint from Flow:
  Button:SetPassThroughButtons()"). Flow was opening the game's quest log panel itself to make
  room for the Flow Router, which ran the map from Flow's code. It never touches the game's
  map or quest panels now: with the quest log open the Router covers it, otherwise it docks
  beside the map. The stop card's link is now "Select in quest log" (press L or M to read it),
  and "Show on map" highlights the stop on Flow's map layer.
- Map: a route on/off button sits right above Flow's drawer button.
- Map labels push each other apart: each one tries eight spots around its point and takes one
  that doesn't cover another label; with no room it drops the [level] and keeps the number.
- Bags full: the "sell at a merchant" stop is planned even with a detour (it was only planned
  when a merchant was on your way).
- Flow button: the next three spells are "on deck" to its right, shrinking, with their cooldown
  timers, moving up and down as things change. Auto attack moved to the left (the "active"
  side).

## 0.35.48
- The Flow button shows a small crossed-swords badge (top-left, gently pulsing) while auto
  attack is on.
- Heals: your health is hidden from add-ons on WoW: Forever, so Flow's heal timing never fired.
  It now uses the game's own low-health warning (the red screen flash, about a third of your
  health): when it's on, Flow suggests your fastest heal. In combat that's on the Flow icon and
  glowing on your bar (the key itself is locked for the fight). New suggested setting:
  "Low-health screen warning" (needed for this).
- Stunned, feared or rooted: Flow suggests the spell that breaks you free when you have one
  (Will to Survive or Every Man for Himself, Will of the Forsaken, Escape Artist, Blessing of
  Freedom for roots).
- `/flow api` reports whether the low-health warning and loss-of-control can be read here.

## 0.35.47
- The Flow button shows a cooldown timer: seconds left, big in the middle of the icon (tenths
  under 10 s, minutes when long). Not for the 1.5 s global cooldown. Items too (a lure...).
- In a quest's area the arrow is the ring again. Pointing at the nearest spawn spot (0.35.45)
  sent you back and forth: those are where things CAN spawn, not where they are. Standing on
  one still makes the pillars wave.

## 0.35.46
- The Flow button's "drag to move" label (hold Shift) now sits above the button, on a dark tab,
  instead of covering the action's text below it. Hovering the handle lights it up, shows the
  move cursor and a tooltip, so it's clear you can grab it.
- Right on the spot (on a spawn spot, or at the stop itself), the arrow's pillars run a sine
  wave around the ring.
- Minimap clouds: redrawn only when something changed (you moved, turned, zoomed, or the stop
  changed), without the memory churn (it was 1.3 MB a second).

## 0.35.45
- Weapons: Flow now checks the weapon skills you've actually trained, not only what your class
  may use. A sword before you've learned Swords isn't offered as an upgrade (no more "you do
  not have the required proficiency"); it's kept, its tooltip says so, and if it would be an
  upgrade the route gets a weapon master stop (Woo Ping in Stormwind, Buliwyf Stonehand in
  Ironforge...) to learn it. Guns stay "your class can't use this": paladins never can.
- In a quest's area the arrow now points at the nearest spot where the thing you need spawns
  ("Nearest Bundle of Wood: 23 yd"), from Questie's spawn data, and moves on to the next spot
  after you loot one. The ring shows only when you're right on a spot.

## 0.35.44
- Fixed: with the Fishing Pole on and no note of your weapons, "put your weapon back" picked by
  item level and chose the Rust-covered Blunderbuss (a gun paladins can't use). It now uses
  Flow's gear check: your best usable weapon for your levelling spec.
- New: upgrades on the Flow key. Out of combat with nothing to cast, the key offers "Equip X
  (upgrade +N)" for gear in your bags that's better for your levelling spec (or fills an empty
  slot). Target an enemy and it comes first: "Before the fight: equip X". Weapons wait while
  you're fishing.
- Minimap areas are one soft cloud like the game's own quest areas, instead of a pile of
  overlapping circles.

## 0.35.43
- Fixed: talking to a quest giver could hide quests they DO offer (7 at once in one talk), so
  "Accept:" stops vanished for quests you hadn't taken. Flow now only judges from a real list
  of quests on screen, never in the seconds after you accept or turn in, needs two visits a
  minute apart, and skips for a day instead of a week. The ones it wrongly hid are back.
- Fixed: a quest you just accepted stayed on the route as "Accept:" until a background scan
  finished. It now leaves at once (checked against your quest log), and the route refreshes
  when the scan ends.
- Clicking anything in Flow that opens a window (arrow drawer, stop card, menus, advice) hides
  the hover tooltip, and the arrow shows no tooltip while its drawer is open.
- Intro: FLOW is bigger and bold, on top of the spinning pillars (it was drawn under them).
- The Flow key no longer offers "Cast your line" just because the pole is on: away from a
  fishing stop or where you last fished, it offers to put your weapons back.

## 0.35.42
- Cooking: Flow plans cooking where you stand only if you can make a campfire (you need Simple
  Wood AND Flint and Tinder). Otherwise it plans it at a real fire: by the cooking trainer
  (Goldshire's inn), where the Flow key opens Cooking and makes them. No known fire: the stop
  waits, saying why.
- Bags: the old green "equip now" arrow in the top-left corner is gone. The per-spec marks say
  it (green up = better for that spec, your levelling spec brightest).
- The arrow's panel is a drawer: it slides down out of the arrow, joined to it, with a ^ tab at
  the bottom to fold it back up (or click the arrow). It no longer moves. The stop card from the
  Flow Tracker and Router is still its own window with an X.

## 0.35.41
- The arrow's pillars stay small when you arrive (only a little taller than while pointing),
  and bounce up quickly as the change happens.
- The Flow Router has a header like the Flow Tracker's (dark bar, orange accent, its own
  spyglass icon), with the "?" help on the right.
- The item your current stop wants you to use (a recipe to learn...) gets Flow's (o) marker
  in the route colour on its bag slot, top-left.
- The Flow Action border is no longer route purple (it read as "epic"): spell steps use the
  spell colour (light blue), item steps the item's own quality colour.

## 0.35.40
- Fixed: at "Learn Brilliant Smallfish: use the recipe in your bags" the Flow key offered to
  equip your Fishing Pole (the word "fish" made Flow think it was fishing). Only quest
  objectives like "catch 5 fish" are guessed from their text now.
- "Make 32 x Brilliant Smallfish" with the recipe already in your bags now says "use the recipe
  in your bags first", not "buy" it.
- Diagnostics: blocked actions carry the Flow version; `/flow api` reads UnitHealthPercent (it
  may let Flow see how hurt you are).

## 0.35.39
- Crafting where you stand ("Make 4 x Roasted Boar Meat" when you carry the meat and no fire is
  known nearby): the Flow key now does all of it: makes a campfire (Basic Campfire), opens
  Cooking, then makes exactly the right number. First Aid skips the fire. A recipe in your
  bags: the key uses it.
- No Simple Wood for the campfire: a "Buy Simple Wood" stop goes on the route.
- When you're at a stop like that, the arrow's ring shows its icon bouncing in place of the
  ball: the cooking (or other profession) icon for crafting, a bag for something to use from
  your bags.

## 0.35.38
- The 3D arrow's ring has height: its dots are now little pillars with lit caps (short while
  it points the way, tall and glowing in the route colour when you've arrived). The dot in the
  middle is now a shaded sphere floating over its shadow.
- New login intro: the pillars stand tall and spin fast around a deep gold FLOW, slowing to a
  stop, with "Flow (unfettered)", the version and status underneath; then the arrow appears
  over the still pillars.
- What the route optimises is now pluggable (for contributors): a `routeObjective` registry.
  Most XP and Shortest are the built-in ones; others (fishing only, a profession race) are a
  registration away. `/flow nav sort` lists them.

## 0.35.37
- Fixed a "blocked" error: dragging the Flow cast icon when a fight started tried to finish the
  move in combat, which the game forbids for that button. A drag still going when combat
  starts is now finished just before the fight.
- Fixed: Flow counted 0 of every item, because WoW: Forever moved GetItemCount into C_Item.
  Crafting counts, lures and "put your weapon back" all read your bags correctly now.

## 0.35.36
- The arrow's panel (click the arrow) can be dragged by its title band too, like the stop
  card; it then opens where you left it (right-click the title to put it back under the arrow).
- Gear marks are one style everywhere: the game's green bag arrow pointing up = better for
  that spec, the same arrow red and pointing down = worse, a short grey dash = about the same.
- After-fight heal: offered after any fight of 6 seconds or more, for 15 seconds (it was only
  after 15-second fights, for 10). Your health is hidden from add-ons on WoW: Forever, so Flow
  can't tell how hurt you are; `/flow api` now also checks whether the damage meter or the
  health bar could tell it.

## 0.35.35
- Fixed: after a fight away from the water, the Flow key kept offering "Cast your line" and
  the game said "didn't land in fishable water" over and over. Now that message tells Flow
  there's no water there: away from a fishing stop it offers to put your weapons back
  instead; at one, it says "Face the water, then cast".

## 0.35.34
- Target an enemy with your Fishing Pole still on, and the Flow key puts your weapon back on
  first (then your shield), before your pull, even at the fishing spot. If Flow didn't note
  what you had on, it picks the best weapon in your bags. It won't offer the pole again while
  the enemy is targeted.

## 0.35.33
- The login intro starts straight away with the spin and "Flow (unfettered)" (it used to show
  your quest first and then take the arrow over, which flashed), and lasts about a second
  longer. The status line fills in as quest data and your route load.

## 0.35.32
- The login title card is gone. Instead the arrow plays a short intro: it spins up, settles
  into its ring with FLOW in the middle, and underneath says "Flow (unfettered)", the version,
  and what Flow is working with (spells, Questie, stops planned). Then it points the way as
  usual. `/flow splash` replays it; Options > AddOns > Flow turns it off.
- "ways to improve" in chat now shows Flow's version.

## 0.35.31
- The stop you choose ("Go here first") stays marked: on the map it's red inside with a bold
  dark red ring and its area stays red (like when you hover it); in the Flow Router its row is
  tinted red with a red bar, and its marker turns red. The route itself stays in the "From
  selected" orange.
- The stop card (Flow's quest view) can be dragged by its title band. It then opens where you
  left it; right-click the title to put it back beside what you click.

## 0.35.30
- Flow key with an NPC selected (Lee Brown): Fishing and Find Minerals now cast on you, never
  on your target, so they don't fail. Reeling in and gathering use the game's Interact, which
  goes to your target when you have one, so with a friendly target selected the key first
  clears it (one press). Enemy targets are left alone (that's your pull).
- Flow Router: the title stands alone; a "?" on the right shows a small legend with the same
  ^ handle and (o) marker the rows use. The background is darker.
- Flow Router and the quest log: with the Router open, the game's quest-log button now just
  closes the Router and shows the quest log (it used to close and spring back open). Flow's
  button still opens the Router over the quest log, and closes both.

## 0.35.29
- `/flow perf` also shows how much memory each part churns through (KB/s), and how much Flow
  really keeps after a clean-up, to track down a memory reading of 96 MB.
- Fixed a self-test that still used the old fishing check.

## 0.35.28
- Smoother: Flow no longer re-plans the route every 8 seconds while you stand still (only after
  you move 30 yards, or when something changes), and the background refresh of the stop list
  runs every 30 seconds instead of 10. Each one took 20-40 ms, a small stutter you could feel.

## 0.35.27
- Crafting: Flow makes exactly what reaches your target. The profession window gets a small
  Flow panel: "make 11 x Heavy Linen Bandage", First Aid 47 -> 58, and a **Make 11** button that
  crafts exactly that many. Hover it for why that number and what's next. When the skill gets
  there, Flow says "that's enough, stop crafting" and names your next stop.
- Fixed: a crafting plan vanished once you were within 10 points of its target (halfway
  through), so nothing told you when to stop. It now holds until the target is reached.
- Route stops highlight the count in "Make 11 x ...".
- Fishing keeps up with the water you'll fish in (about 25 by level 10, 75 by 20, 150 by 30)
  instead of the crafting curve, which asked for 58 at level 8.

## 0.35.26
- Fixed: the Flow key stopped fishing after the first fishing quest. The next Fishing stop
  (the "skill behind your level" one) didn't say it was for Fishing, so the key didn't
  know. Now any fishing stop counts, including quest objectives like "catch 5 fish". Fishing
  also continues wherever you have the pole on and are casting, until you walk away (then the
  key puts your weapons back).
- New: a "Buy a Shiny Bauble (lure)" stop with the Fishing Pole, when you carry no lure
  (optional, planned when the vendor is on the way).
- Options > AddOns > Flow: turn off the login title card, and turn the key's fishing and
  gathering steps on or off.
- The title card now sits lower, below the game's zone name.

## 0.35.25
- `/flow perf`: how much CPU and memory Flow uses, per part (arrow, rotation, route planning,
  world map, tracker), and any single update slow enough to feel as a hitch. Saved with the
  diagnostics so slow spots get noticed.
- The Flow Tracker shows a spinner and "updating route..." while the route is being redone.

## 0.35.24
- Professions chain: when Fishing is on your route, the fish you'll catch count toward
  Cooking (Brilliant Smallfish levels it like wolf or boar meat), so there's less meat to
  farm. The recipe (about 40 copper) goes on the route as a stop. The farm stop says how many
  fewer kills fishing saved you.

## 0.35.23
- Progress reads as a path everywhere Flow writes it: "Loot Stringy Wolf Meat 9 -> 66",
  "Slimy Menace: 0 -> 7 Murloc slain".

## 0.35.22
- Fixed: the Flow key and the icon did nothing out of combat (Devotion Aura, blessings, seals).
  Once the button had nothing to cast it hid itself and never came back until a fight started.
- New: Flow Actions on the same key, out of combat, at your route stop. Fishing: equip your
  pole, put on your best lure, cast, then press again when the bobber splashes. Mining and
  herbs: turn on Find Minerals or Find Herbs, then gather. Leaving: your weapons go back on.
  `/flow action` says what it would do and why.
- New suggested setting: "Interact key reaches objects" (needed to reel in and gather with the key).

## 0.35.21
- Fixed a self-test that dropped the oldest diagnostics line when the log was full.

## 0.35.20
- Fixed: "Flow has been blocked from an action only available to the Blizzard UI" when using
  the game menu. Flow replaced the game's popup table (0.35.17), which taints every popup,
  including Log Out and Exit. Flow also no longer closes the Options window from its own code.
- Blocked actions are now logged (what was blocked, which add-on was blamed, what was open)
  and tools/read-diag.ps1 shows them in their own section. Developer installs turn on the
  game's taint log so the cause can be found. A self-test checks the game's global tables are
  untainted.
- Flow's settings now live in the game: Game Menu > Options > AddOns > Flow. The page has your
  cast key, Flow's options (colour-blind colours, 3D arrow, minimap areas, route on the map) and
  every **Suggested WoW setting** (auto loot, nameplates, target of target, instant quest text,
  camera zoom, timestamps, ...) with what Flow suggests, plus "Use Flow's suggestions".
  /flow settings and /flow setup open it.
- Flow's target marker (o) everywhere: a ring in the route colour (epic purple in Most XP
  order) around a dot, for the stop the arrow points at on the world map, on the minimap and in
  the Flow Router, matching the arrow's ring when you arrive.

## 0.35.19
- 3D arrow (the new default): a thick chevron lying on the ground ahead of you, tilted towards
  the horizon with perspective, a lit top, darker sides, a soft shadow and a slight float. Its
  ring lies flat on the ground too. It turns left and right like before; it can't point up or
  down (WoW: Forever gives no heights). Right-click the arrow and untick "3D arrow", or
  `/flow nav arrow flat`, for the flat line arrow.

## 0.35.18
- Fishing needs a Fishing Pole: without one, "Buy a Fishing Pole" comes first and the fishing
  stop shows "needs a Fishing Pole". Fishing stops also suggest a Shiny Bauble lure.
- Minimap areas: the stop the arrow points at shows its area on the minimap (discs and a
  border, like the world map). Hover a row in the Flow Tracker and that stop's area lights up
  in the hover colour too, so you can see whether you stand in this stop's area, the next one's,
  or both.

## 0.35.17
- Waypoints from pasted coordinates. `/way` now works too (unless TomTom has it), and so does
  a whole pasted line: `45.2 63.1`, `(45.2, 63.1)`, `/way 45.2 63.1 Hogger`,
  `/way Elwynn Forest 45.2 63.1 Hogger`, `/way #1429 45 63`.
- Arrow menu (right-click): "Set a waypoint (paste coordinates)..." opens a box to paste into,
  and "Clear your waypoint".

## 0.35.16
- Mount milestone. Five levels before riding level the advice list tells you to start saving
  (how much, and what you have). At riding level "Learn riding" goes on the route as a
  milestone, then the mount itself; each waits, with its price, until you can pay. Paladins
  and warlocks get their mount from a class quest, so they only save for riding.
- The riding level (40) and prices (about 20g riding, 80g mount) are the classic ones, shown
  as estimates until WoW: Forever confirms them; they are one line to change in
  Modules/Nav/Mounts.lua.

## 0.35.15
- Fixed: "Learn Heavy Linen Bandage" (and other recipe stops) stayed after you learned it at
  the trainer. Flow now notices the "You have learned..." line at once.
- New route: **Completionist** (arrow menu, or `/flow nav complete`): every quest you can still
  do in the zones you are questing in, grey ones included, in the shortest order. XP does not
  reorder it.
- Class training is a milestone: it always makes the route (never dropped as too far) and
  counts as half the distance of a quest stop, so you train as soon as it fits around the
  quests on the way, instead of whenever you happen to pass the trainer.
- Quests that come into range as you level are folded into the route by themselves (the
  route re-plans on level up).

## 0.35.14
- For contributors: CLAUDE.md (how to work on Flow with an AI assistant), CONTRIBUTING.md,
  and GitHub issue and pull request templates.
- Tools find your WoW: Forever folder and account by themselves (set FLOW_WOW_DIR /
  FLOW_WOW_ACCOUNT to override); combat reports go to reports/ by default.

## 0.35.13
- Flow Router: the active stop (where the arrow points now) shows a selected radio dot, a
  white ring around a dot in the route colour, instead of the ^ (replaces the 0.35.12 star).
  Hover says the arrow points here; if you chose it, a click clears your choice.
- Optional profession farming (meat for Cooking when no quest needs it) is never a stop of
  its own any more, so Flow no longer sends you off to kill wolves. It is listed under "Along
  the way" in the arrow panel: loot those mobs when your quests bring you to them.
- Fixed three icon paths with single backslashes (money-blocked stops, lock icon, quest
  reward coin).

## 0.35.12
- Flow Router: your selected stop shows a filled star instead of the ^. Hover it to see that
  the route starts there; click it to clear the selection and go back to your usual order.

## 0.35.11
- Clicking a stop (Flow Router row or point, Flow Tracker row, map area) opens Flow's own
  card for it beside what you clicked, and the Flow Router stays open. The card has links:
  "Open in quest log" (the old behaviour), "Show on map" and "Go here first". Click the stop
  again, the X, or Esc to close it.
- World map areas: only the patch the route actually goes to is drawn for each stop; point at
  a stop to see every place its mobs live.
- Fixed: the arrow panel's fallback icon path (single backslashes).

## 0.35.10
- Farm stops count like quest objectives: "Loot Stringy Wolf Meat or Chunk of Boar Meat 9/66
  (~150 kills)". The count is what you carry out of what the plan uses.
- World map: every area stop gets its own patch with a border around it (the next stop
  stronger, the one you point at in the hover colour). Hover a patch to see the stop number
  and what you need there; click opens it, right-click for the menu.

## 0.35.9
- World map: a stop that is a whole area (mobs to kill, things to loot, meat to farm) shows
  where its mobs live as soft discs in the route colour, for the next stop and the one you point
  at, instead of a single dot. Farm stops also get the ring on the arrow when you are there.
- Farming is realistic now: "Loot 66 Stringy Wolf Meat or Chunk of Boar Meat (~170 kills)".
  Each material has a rough drop rate, and Flow learns yours as you loot those mobs.
- Either meat will do: wolves and boars both count, and meat already in your bags is cooked
  first.
- Optional professions (not needed for a quest) are "loot as you quest": their farm stops only
  come up when the mobs are on your way, instead of pulling you off to grind.

## 0.35.8
- Setup: new "Target of target" row, suggested on. On clients that keep it in Edit Mode the
  row says where to find it (Target Frame > Target of Target).
- Setup: when an update adds a suggestion you have not seen and that is off, the setup table
  opens once more, 30 seconds after login, with a line in chat naming what is new.
- README: feature list brought up to date (route orders and colours, Flow Router, Flow Tracker,
  quest areas, corpse arrow, blocked stops, professions, Flow Seller, self-tests); banner uses
  the current route colours.

## 0.35.7
- Arrow: in a quest area (the ring is showing), hovering the arrow or its text opens the full
  panel and moving away closes it; click to keep it open. Elsewhere hover shows a tooltip and a
  click opens the panel, as before.

## 0.35.6
- Fixed: "Buy a Mining Pick" (and "needs a Mining Pick") stayed after you bought one: Flow only
  looked for the classic item ID. Tools now count by ID or name, in your bags or equipped.

## 0.35.5
- Flow Seller (the vendor drawer) stays on screen at every vendor. With nothing to sell it's
  collapsed to its header, "Flow Seller  0 items to sell"; click the header to open or close it.
  With items to sell it opens as before.

## 0.35.4
- Flow Seller never suggests selling a profession tool (Mining Pick, Blacksmith Hammer, Skinning
  Knife, fishing poles, Arclight Spanner) while you have or plan that profession; bags show the
  profession icon with "tool for Mining".

## 0.35.3
- Cast key check: each press of your Flow key is logged in the fight record (what it was bound
  to at that moment, whether a text box had the keyboard, and whether the button then got the
  click), to find why the key sometimes does nothing.

## 0.35.2
- Party: forming a group as leader no longer builds a party route from everyone's quests and
  switches you onto it (it flooded the tracker and map). You get a one-line hint instead; others
  still get the join prompt when someone shares one.
- Right-click menu, in a group: Your own route / Party route, Share a party route, Leave it.

## 0.35.1
- Forever blocks measuring nameplates on screen, so the arrow no longer tries to point at visible
  quest mobs (it logged an error each time); the ring stays.
- `/flow talents` reads the modern talent system (C_ClassTalents), which Forever uses.
- Checked: this client gives addons no height (always 0), so no up/down hints; caves are learned
  from your trails instead.

## 0.35.0
- Caves: Flow marks trail points you walk indoors and learns entrances (where you go from
  outdoors to indoors). A stop inside is no longer pointed at in a straight line (that led on top
  of the cave, e.g. Book Return): the arrow follows your trail in, or heads for the entrance
  ("it's inside: entrance first"). Needs one walk in to learn the cave.
- Map points work like rows in the Flow Router list: hover = details (highlighted in place),
  click = open it, right-click = menu. Only the ^ handle in the list previews or changes the route.
- Cast key: Attack uses the spell button too, so pressing the key on an enemy starts auto attack.
- Diagnostics: whether this client gives addons heights (for up/down hints).

## 0.34.1
- Gear: while you wear a two-hander, a one-hander or shield is valued as a pair with the best
  partner in your bags (a shield for a one-hander, a one-hander for a shield), shown as "as a
  pair with ...". Retribution, which uses no off-hand, keeps comparing the one-hander alone.
- `/flow talents` (and the diagnostics) list this client's talent trees, for writing the
  talent plan.

## 0.34.0
- Crafting materials no profession of yours uses (learned or planned) are offered for sale (plain)
  or the auction house (better quality). Materials for planned professions are kept, e.g. Linen
  Cloth for First Aid before you've learned it.
- Weapon speed now counts a little in the gear score (up to one point either way), per spec
  preference (Retribution: slow).
- Tests: quest availability (level, holiday events, quests a giver didn't offer), sell decisions,
  weapon speed (25 in all).

## 0.33.1
- Items kept for several reasons list them all (e.g. Linen Cloth: the Redemption class quest; for
  First Aid: Linen Bandage). Profession materials name every profession of yours that uses them,
  including from Flow's levelling guides.
- Flow Router (the map drawer, renamed): "Show route on map" switch (off = the list only).
- Route lines on the map are fully opaque and a touch thicker, so they show the exact route colour
  (epic purple for Most XP first).

## 0.33.0
- After-fight heal prompt: only after fights of 15 s or more, for 10 s, and never once you target
  an enemy (you're pulling: attacks first). It was offering Holy Light before attacks at nearly
  full health. Now tested rule by rule.
- Dead: the arrow turns red and points back to your corpse ("Release your spirit" before that),
  with the minimap dot on the corpse.
- Quest stops show a quest icon in the tracker and route list: "!" to accept, "?" to turn in, a
  grey "?" for objectives of quests you're on.
- Hovering the ring lists every quest stop you're in the area for ("Also here").
- Tests: 22.

## 0.32.2
- Moving the spell icon: hold Shift (out of combat) and a "drag to move" handle appears over it;
  drag that. Dragging the secure button itself didn't work (it takes the press as a click).

## 0.32.1
- Cast key: a fight that starts while the after-fight heal is offered no longer locks the key
  to Holy Light for the whole fight (seen in the fight records); it locks to Judgement.

## 0.32.0
- Arrow: anywhere in a quest's area counts as arrived (within 45 yd of any spawn of its mobs or
  objects, not just the point the route picked), so it shows the ring there instead of pointing
  you back to one dot. In the area, when one of the quest's mobs or NPCs has a nameplate on
  screen, the arrow points straight at it ("There: Kobold Vermin").
- Hover the arrow, ring or its text for the stop's details (quest progress...).
- Heals from the cast key always land on you, whatever you have targeted. Presses and the
  game's errors in the 15 s after a fight are recorded too.
- "Choose your professions" no longer shows once you've learned two main professions.
- Tests: quest area, professions advice (19 in all).

## 0.31.1
- Cast key: never locked to nothing for a fight. The fight records showed pulls with no
  suggestion, so the key did nothing all fight; now the class picks (Paladin: Judgement, or a
  seal if you have none).
- Order modes coloured in menus and the map list: Most XP purple, Shortest blue, From selected
  orange.
- Clickable things look clickable: hand cursor on route rows, map points and the ^ handle; tracker
  rows also show "open".
- Arrived: the arrow turns into a pulsing ring with a dot in the middle.
- Route chevrons are white on every leg.
- Fixed: the advice list's go-arrow icon path (single backslashes).

## 0.31.0
- Cast key and icon: Forever ignores macro-type secure buttons (fight records showed every press
  arriving with the right spell, and nothing cast). The button now uses the "spell" type; only
  Attack still uses /startattack. Fight records also log the game's own errors and casts.
- After a fight of 6 s or more, the icon offers Holy Light for up to 12 s (Flow can't see your
  health in Forever, so it's a prompt; it goes when you heal or fight again).
- No buff reminders while resting (inns, cities); everywhere else they keep coming.
- One spec badge everywhere items are marked (bags, quest reward choices, vendor drawer): an icon
  per spec with an arrow drawn right above it (up better, down worse, flat about the same). Quest
  rewards used to show plain coloured squares.
- Tests: spec badge, after-fight heal (15 in all).

## 0.30.1
- Route: a quest's turn-in now comes along with its objectives (it used to fall off the end of
  the 14 nearest stops, so the route stopped at the last objective).
- Quests that aren't on offer stay off the route: event quests only while Questie says the event
  is on (e.g. An Apple Treat after Hallow's End), and when you talk to a quest giver, quests Flow
  expected but they don't offer are skipped for a week.
- The text under the arrow clicks like the arrow (left: panel, right: menu).
- Vendor drawer: the button says what it sells ("Sell 16 items for 1s 20c"), and the junk line
  reads "No junk left (4 grey items sold this visit)".

## 0.30.0
- Bags: gear shows a small icon per spec along the bottom with an arrow above each: up = better
  than that spec's gear, down = worse, flat bar = about the same (your levelling spec brighter).
  The sell coin and keep icons moved to the top right.
- "From selected stop" survives /reload: the chosen stop is saved, the radio and route colour
  come back as they were.
- Cast diagnostics: each fight logs what was suggested at the pull, what the key was set to,
  whether the button received your clicks or key presses, and what Flow suggested during the
  fight ("[cast]" lines), to find why the key doesn't cast.

## 0.29.1
- Splash: 2 s.
- "Hide this stop" in the menus is now "Move on (hide this for now)".
- "From selected" is greyed as "Select a waypoint" until you pick a stop, then it reads "From
  selected" and is ticked.
- From selected stop is legendary orange (route, arrow). Hovering a stop now shows only the route
  you'd follow, all in that orange, instead of two routes in different colours.
- Route lines and points sit one layer (frame strata) above the map, so map objects can't cover them.
- "Ways to improve" no longer lists quests to accept (they're on the route, tracker and map
  list); it sticks to spells, training, gear, talents and professions.

## 0.29.0
- Fixed: the spell suggestion (icon and cast key) stopped. Forever hides your buffs from addons
  (often in combat) and reading them threw an error that stopped every suggestion. Now Flow
  remembers the seals, blessings and auras you cast and uses that when buffs are hidden, and one
  failing check only skips its own rule.
- Fixed: vendor drawer icons (wrong icon call).
- Map list rows: an up-arrow handle on the left routes from that stop (hover it to preview).
  Clicking the row opens it (quest details; the drawer folds away so they show). Hovering shows
  the details right there. Right-click for a menu.
- One readable tooltip for every stop (map pins, map list, tracker): title and level, the task
  in white, objectives with progress, a short quest text, details, XP, then a hint.
- Arrow panel: the task now has a band of its own in the route colour (icon, type, the task in
  large text, distance), then the rest.
- Self-tests: `/flow test` (12 tests: registry, skill objectives and planning, XP, route colour,
  planner order and dependencies, blocked labels, buff memory, gear rule, menu, tooltip). They
  also run on every /reload into the diagnostics.

## 0.28.1
- Flow Tracker: Shift-drag its header to move it, even when docked (dragging undocks it). Drop
  it just under Questie's tracker to dock it again.

## 0.28.0
- Route and arrow share one colour, and it shows the order mode: purple (epic) = Most XP first,
  blue (rare) = Shortest path, gold (artifact) = From selected stop. Previewed route yellow,
  yours grey meanwhile, hovered stop red. Colour-blind palette keeps the same roles.
- Map drawer: the "Flow route" bar at the top is gone (the square map button does it); hidden
  stops are always listed (greyed, click to bring back).
- Profession stops (skill plan, tools to buy) follow "Include professions": off means none.
- Buying stops carry a price (guide estimate until you've seen it at a vendor, then the real
  one) and are listed as blocked until you can pay.
- Flow Tracker docks under Questie's tracker and opens downward.
- Splash: 1 s.

## 0.27.0
- Route order has three modes (map list, arrow menu): Most XP first (default), Shortest path,
  From selected stop. Clicking a stop on the world map selects it; picking one of the other two
  clears it. When the selected stop is done, the route goes back to your usual mode.
- Flow Tracker: clicking a stop opens it (quest in the quest log, anything else on the world map,
  highlighted) instead of changing the route. Right-click for a menu. The route is changed on
  the world map only.
- Flow Tracker docks on top of Questie's tracker: one column, Flow opens upward from its
  header, Questie downward from its own, one open at a time or neither. `/flow tracker undock`.
- Right-click menu (arrow and tracker rows), in Flow's style: open or hide the stop; route
  (Follow current quests / Optimal with professions / Optimal without professions); order;
  Unhide all stops.
- Minimap: a dot in the route colour for your current stop (at the edge when it's further).
- Nameplates: the NPC your current stop is about (vendor, trainer, quest giver, turn-in) gets a
  circle mark.
- Map pins and route lines sit above the map's own art (lake, towns).

## 0.26.0
- Map: a square Flow button above the game's quest log button opens and closes the route list.
  The quest log and Flow's list share the slot: one or the other, or neither.
- Map: a line from you to your first stop, and small chevrons crawling along the route to show
  which way it runs (and when a leg goes out and back). The stop you hover (on the map or in the
  list) is drawn bigger, in the hover colour with a white ring, on top of everything.
- Map list: blocked and hidden stops always get rows (up to half the list), so a full route no
  longer pushes them out of sight. Rows show a tooltip with the stop's details.
- Most XP first (new default; "Most XP first" on the map list, `/flow nav xp on|off`): still the
  shortest path, but quest stops are weighed by XP and level. Quests 3+ levels above you wait;
  more XP is worth a longer walk; quests about to go grey come a little sooner. Quest tooltips
  show XP (real from your log where the game gives it, else an estimate) and a note.
- Splash: 0.618 s.
- Flow Tracker hangs from its top-left corner, so collapsing folds it up into the header.

## 0.25.0
- Blocked stops are shown, not hidden: a lock (or coin) and the reason, e.g. "needs 1s (you have
  40c)", "needs Mining", "needs a Blacksmith Hammer". In the map route list, the Flow Tracker
  (header counts them) and `/flow nav why`. They join the route by themselves once sorted.
- Profession skill planner. "Raise your Blacksmithing skill to 20" no longer sends you to the
  trainer: Flow works out what to make (most skill per material at your skill), what that
  needs minus what's in your bags, and how to get the rest (smelt ore you carry, mine the
  veins on this map, kill the mobs that drop it, buy it). Those become route stops mixed with
  your quests by distance, re-planned as your bags and skills change. Planned crafting
  professions behind your level get optional stops the same way.
- Data: Blacksmithing, Mining, First Aid, Cooking brackets and material sources (Guides.lua,
  from public levelling guides; approximate). Opening a profession window records your real
  recipes, colours and reagents, which win over the guide data.
- `/flow prof plan` explains the plan (also in diagnostics).

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
