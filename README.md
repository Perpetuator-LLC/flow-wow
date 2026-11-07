<p align="center"><img src="docs/flow-banner.svg" alt="Flow: World of Warcraft levelling companion" width="720"></p>

# Flow (unfettered) WoW Mod

A levelling companion addon for **World of Warcraft: Forever**. It suggests what to press, plans
your route, judges your gear, sorts your bags, plans your professions and learns from how you
play. It started with the paladin and is built so other classes can be added without changing
existing code.

Flow for WoW is a separate project from Flow Engine.

## Features

### Combat
- **Rotation helper**: an icon shows the spell to press next, and the matching action bar or
  stance bar button glows. The border colour says why: green attack, light blue buff, gold heal,
  fast gold pulse heal now.
- **Cast button and key**: click the icon or press your Flow key to cast the suggestion. Set the
  key in `/flow settings`; it warns you about conflicts and never changes your own key bindings.
  In combat WoW freezes what a key casts, so at the pull Flow locks it to a real attack (a seal
  if none is up, then Judgement or Crusader Strike), never a heal. Shift-drag to move the button.
- **Craft the right amount**: on the profession window, Flow says how many to make to reach your
  target, with a Make N button for exactly that many, and tells you when to stop.
- **Flow Actions** (same key, out of combat, at your route stop): at a fishing spot it equips
  your Fishing Pole, puts on your best lure, casts, then reels in when the bobber splashes; at a
  mining or herb stop it turns on Find Minerals / Find Herbs and gathers; when you leave it puts
  your weapons back. Upgrades in your bags: it equips them (first, when you target an enemy).
  Crafting: campfire, open the profession, make exactly enough. One press per step.
  `/flow action` shows what it would do.
- **Buffs while questing**: keeps your seal, blessing and aura up; quiet in cities and inns.
  Remembers what you cast when the game hides your auras.
- **Heal after a fight**: after a long fight, briefly suggests a heal if you need one; never
  in combat or with an enemy targeted.
- **Smart self-heals**: suggests a heal only when none of it would be wasted by the time the
  cast lands. Suggests an emergency heal when you'd die before you could react, unless your
  target dies first. Silent when the game hides your health.
- **Fight types**: boss, several enemies, elite or normal mob, each with its own priorities.
- **Fight profiler**: records every fight and compares your best with your worst per fight
  type. It leans the rotation towards what worked (`/flow fights`).
- **Combat log reports**: `/flow log auto` writes the game's combat log file.
  `tools/analyze-combatlog.ps1` turns it into DPS, healing and tanking reports with
  recommendations, and feeds what it learned back into Flow.

### Questing and navigation
- **Route planner and arrow**: plans the whole trip (quest objectives, turn-ins after their
  objectives, quests to pick up, trainers you can afford, and profession stops) and points you
  along it. It learns trails as you walk, follows them around hills and rivers, and learns cave
  entrances so it sends you in through the door, not over the top.
- **Three route orders**, each with its own colour for the arrow, route and waypoints:
  **Most XP first** (epic purple, the default), **Shortest path** (rare blue) and **From
  selected waypoint** (legendary orange). Tooltips show each stop's XP.
- **Quest areas**: in an objective area the arrow becomes a ring; hover it to see every quest
  there. The arrow comes back when the mob or NPC you need is in sight.
- **3D arrow**: a shaded chevron lying on the ground ahead of you (or the flat line arrow:
  right-click it and untick "3D arrow").
- **Corpse arrow**: when you die the arrow turns red and points to your corpse.
- **Milestones**: class training and your mount always make the route and fit around the
  quests on the way. Flow tells you to start saving for your mount 5 levels early.
- **Completionist route**: every quest in the zones you are questing in, any level.
- **Along the way**: optional farming (meat for Cooking) is never a detour; loot it as you go.
- **Blocked stops**: stops you can't do yet stay listed, greyed, with the reason ("needs
  1g 20s", "needs a Mining Pick"), and come back by themselves when you can.
- **Flow Router** (the square button above the world map's quest log button): the route list
  with quest icons, the order modes, and a "Show route on map" toggle. Hover a stop for details,
  click to open its quest, use the `^` handle to route from that stop, right-click to hide it
  for now. Hidden stops stay listed so you can bring them back.
- **World map and minimap**: numbered waypoints with quest levels (`3 [9]`) and pickups
  (`!2`), a line from you to the next stop with white chevrons, hover previews in orange, and
  a minimap dot for the next stop.
- **Flow Tracker**: the route under Questie's tracker, opening downward. Click a row to open the
  quest; Shift-drag the header to move it, drop it near Questie to dock it again.
- **Arrow menu**: right-click the arrow for route (quests only, optimal with or without
  professions), order, unhide all, and party options.
- **Party routes**: share your quests as a party route if you want one; your own route stays
  separate. Anyone following it can edit it; nobody owns it.
- **Your own waypoint**: Ctrl- or Alt-click the world map, paste coordinates (`/way Elwynn Forest
  45.2 63.1`, or right-click the arrow: Set a waypoint), or `/flow way x y`; it clears when you
  arrive.
- **Only quests you can get**: holiday quests drop out when the event ends, and quests an NPC
  doesn't offer are skipped.
- **Quest markers on nameplates**: skull with your kill count, diamond with the count of an item
  a mob drops, star for NPCs to talk to; several per mob.
- **Missed quests**: quests you skipped in zones you've quested in (`/flow missed`).

### Professions
- **Skill plans**: for each profession, the cheapest path to the next skill cap: buy, learn,
  smelt, craft, gather or farm, with prices from vendors you've visited. These go into the route
  (`/flow prof plan`).
- **Guides** for Blacksmithing, Mining, First Aid, Cooking, Fishing and Herbalism, plus the
  recipes Flow has seen in your profession windows.
- **Tools**: reminds you to buy the Mining Pick or Blacksmith Hammer, and knows when you have one.

### Gear and items
- **Gear scores per role** in every tooltip, shown with your spec icons (Retribution, Holy,
  Protection) and an up, down or equal arrow above each, compared with what the item would
  replace (two one-handers are judged as a pair against a two-hander), or with your gear set
  for that role (Equipment Manager or `/flow gear save`). Weapon speed counts for each spec.
- **Quest reward badges**: the same spec icons and arrows on quest rewards, or a gold coin on
  the best one to sell.
- **Bag icons**: green arrow to equip now, spec arrows for other roles, gold coin to sell, AH,
  DE, a quest "!" for items your quests need, and profession icons for materials and tools.
  The tooltip lists every reason to keep an item (e.g. "Linen for First Aid").
- **Flow Seller**: at a vendor Flow sells grey junk by itself and lists what else to sell,
  12 at a time (the size of the buyback tab). It never sells profession tools or materials you
  need. Buy any item back with one click, and Flow then never sells it again. With nothing to
  sell it folds to "Flow Seller  0 items to sell".
- **Skill books**: tells you to hold "+N skill" items until the last points before a cap.

### Progress advice
- **Advice list** (the round spyglass button with a count): spells to train (with cost), items
  to equip, professions behind your level, talents and habits from your best fights. Rows that
  are places route you there.
- **Training and talents**: trainer reminders, profession targets for your level, and spec
  advice (`/flow spec`, `/flow talents`).

### Quality of life
- **Setup table** on first run (`/flow setup`): auto loot, nameplates, target of target,
  camera zoom, timestamps, colour-blind route colours, combat log and your cast key. When an
  update adds a new suggestion, the table shows once more.
- **Key binding mode** with save/undo/cancel (`/flow bind`), and a heads-up when the game
  auto-places new spells on your bars.
- **Colour-blind palette** for the route (in `/flow settings`).
- A short intro on the arrow at login (version and status), `/flow help`, `/flow settings`, chat timestamps, and Shift-drag to move
  any Flow element.
- **Self-tests**: `/flow test` runs Flow's built-in checks; they also run on every `/reload`.

## Requirements and companions
- World of Warcraft: Forever (interface 16001).
- Recommended: **Questie** + **QuestieDB**. Flow reads their quest and NPC data at runtime for
  the arrow, map route, missed quests and quest-item keeping. Nothing is copied from them.
- Optional: **Auctionator**, for auction house prices in sell decisions.

## Commands
`/flow help` lists everything. The main ones: `/flow setup`, `/flow settings`, `/flow rot why`,
`/flow advice`, `/flow way`, `/flow map`, `/flow nav xp|distance`, `/flow nav unhide`,
`/flow prof plan`, `/flow gear sets`, `/flow sell`, `/flow fights`, `/flow talents`,
`/flow log auto`, `/flow test`, `/flow api`.

## For developers
Start with [CONTRIBUTING.md](CONTRIBUTING.md). Using Claude or another AI assistant? Point it
at this folder: [CLAUDE.md](CLAUDE.md) tells it how Flow is built and how to test in game.

- `Flow.toc` sets the load order. `Core.lua` holds the event bus and the registries
  (`ns:Register` / `ns:Get` / `ns:Each`).
- `Modules/` holds the features. `Classes/<Class>/` holds class data, trainer spells and the
  rotation.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) lists every extension point and how to add a
  class; [docs/GEAR_PLAN.md](docs/GEAR_PLAN.md) covers gear scoring.
- **Tests:** `Modules/Tests.lua` registers self-tests (`ns:Register("test", name, fn)`). There's
  no Lua interpreter here, so they run in game: `/flow test`, and in the diagnostics on every
  `/reload` (`tools/read-diag.ps1` prints them).
- **Debugging:** `/console scriptErrors 1`, `/flow rot why` and `/flow api`.
- **Dev install:** the game's `Interface\AddOns\Flow` is a junction to this repo, so `/reload`
  picks up changes.
- **Packaging:** `tools/package.ps1` builds a release zip; see [docs/PUBLISHING.md](docs/PUBLISHING.md).
