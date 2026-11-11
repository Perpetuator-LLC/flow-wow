# Flow (WoW addon) architecture

Flow for WoW, not Flow Engine. The design rule is **open for extension, closed for modification**:
new classes, specs, fight types, metrics, advisors and gear considerations are added by
*registering* them from new files. The core and feature modules don't change.

## Registries

`Core.lua` provides three calls:

```lua
ns:Register(kind, key, value)   -- add an extension (keys are unique per kind)
ns:Get(kind, key)               -- look one up
for key, value in ns:Each(kind) do ... end   -- all of a kind, in load order
```

| Kind | Key | Value | Used by |
|---|---|---|---|
| `class` | class token, e.g. `PALADIN` | `{ specs, leveling, weights, weaponSpeed, proficiency }` | Spec advice, gear scoring |
| `classSpells` | class token | list of `{ level, spell, improves, note }` | Advisor: "go train X" |
| `rotation` | class token | `{ heals, priority, priorities = { [fightType] = list } }` | Rotation engine |
| `fightType` | e.g. `boss`, `aoe`, `elite`, `normal` | `{ order, label, match = fn(info) }` | Rotation (per-type lists), profiler |
| `metric` | e.g. `dps`, `hps`, `tps`, `dtps` | `{ label, role, higherBetter, value = fn(fight) }` | Profiler: what a "good fight" means per role |
| `fightProbe` | any | `{ start, tick, finish, events = { EVENT = fn(fight, ...) } }` | Profiler: what gets recorded per fight |
| `advisor` | any | `{ check = fn() -> { {importance, text, improves}, ... } }` | Advice button, `/flow advice` |
| `gearAnalyzer` | any | `fn(item) -> bonus{dps,heal,tank}, notes` | Gear scores, quest reward badges |
| `profGuide` | profession name | `{ kind = "craft"|"gather", tool, steps = { {recipe, item, learn, yellow, green, grey, mats, station} }, nodes }` | Skill planner (`Modules/Crafting/SkillPlan.lua`) |
| `itemSource` | item ID | `{ name, gather, objects, node, skill, yield }` or `{ smelt = {from, n, skill} }` or `{ drops = {npc names} }` or `{ vendor = true }` | Skill planner: where materials come from |
| (perf) | `ns.perf.Wrap(name, fn)` | timed function | `/flow perf`, diagnostics snapshot |
| `weaponMaster` | NPC name | `{ skills = { [itemSubclassID] = true } }` | Weapon master stops when an upgrade needs a weapon skill (`Modules/Gear/WeaponSkills.lua`) |
| `routeObjective` | e.g. `xp`, `distance` | `{ label, tip, color, weigh = fn(goal, ctx) -> multiplier, keep = fn(goal, ctx) -> bool }` | What the route optimises (`Modules/Nav/XpValue.lua`); `/flow nav sort <key>` |
| `test` | "area: what it checks" | `fn(t)` with `t:ok`, `t:eq`, `t:near` | `/flow test`, diagnostics snapshot |
| `charData` | a path in `ns.db`: `"trainer"` or `"quests.notOffered"` | `{ adopt = fn(old, ctx) -> value, later = bool }`; register with `ns:PerCharacter(path, def)` | Per-character saved data (`Core.lua`): kept in `FlowCharDB`, at its usual place in `ns.db` while you play. `adopt` sorts data saved before the split (shared by all characters); `later` runs it at login as `adopt(old, ctx, current)`, `false` = try next login |
| `mount` | race token, e.g. `Human` | `{ trainer, vendor, what }` NPC names | Mount milestone (`Modules/Nav/Mounts.lua`) |
| `sharedPlaces` | `community` | `{ npcs = { [name] = { id, map, x, y, roles = "vendor,repair", f = "H" | "A" | "AH" } }, mailboxes = { {map, x, y} } }` | NPC spots Flow players shared (`Learned/Places.lua`, written by `tools/share-places.ps1`; docs/SHARE-PLACES.md): route points and "Nearest ..." where you haven't been yourself |
| `mountRule` | `default` | `{ level, ridingCost, mountCost, saveFrom, classMount = { CLASS = spell } }` | Mount milestone: when to save, learn and buy |
| `action` | any | `{ order, get = fn(ctx) -> { type = "spell" or "item" or "interact" or "sit" or "wait", spell, item, targetSlot, icon, label, urgent, before } }` | Flow Actions: what the key does out of combat (`Modules/Rotation/Actions.lua`, `BuffItems.lua`). `urgent` shows ahead of the rotation's own suggestion |
| `status` | any | `{ order, get = fn() -> { icon, text, color, tip } or nil }` | Status icons in a row above the Flow key, between fights (`Modules/Rotation/Display.lua`): things to sort out, instead of chat lines. Turned off from the key's right-click menu |
| `navGoal` | any | `{ collect = fn() -> { {key, points, text, kind, weight, optional, cost, blockedBy, anywhere, milestone, along, area, npcs}, ... } }` | Route: `cost` (copper) or `blockedBy` (text) keeps a stop off the route but listed with its reason |
| `questNeed` | quest ID | `{ where = "deep in Palemane Rock", note, tool = "Fishing", item = id }` | What's worth knowing before walking to a quest's giver, which Questie doesn't say (`Modules/Quests/QuestNeeds.lua`): `where` and `note` go on its pickup stop; `tool`/`item` (what the giver wants you to carry first) keep the pickup waiting, with that reason, until you have it. Escort quests get their own note from Questie's data, no entry needed |

Events: `ns:On(event, fn)`. Saved data ready: `ns:OnLoad(fn(db))`. Slash subcommands:
`ns.commands.name = fn(args)` gives `/flow name`.

## Adding a class

1. Create `Classes/<Class>/` with:
   - `Data.lua`: `ns:Register("class", "<TOKEN>", {...})` with specs, levelling recommendation,
     stat weights per role, weapon speed preference, armor/weapon proficiency.
   - `Spells.lua`: `ns:Register("classSpells", "<TOKEN>", {...})`.
   - `Rotation.lua`: `ns:Register("rotation", "<TOKEN>", {...})`.
2. List the files in `Flow.toc` under "Classes".

The TOC listing is the only shared file a new class touches. WoW loads only the files the
TOC lists, so that one line is unavoidable.

## How the pieces connect

```
Tracker (damage taken, target TTD, heal sizes)        FightTypes (boss/aoe/elite/normal)
        \                                                   |
         Rotation Engine --- picks next spell <-------------+
            | E.current                                      |
            v                                                v
         Display (icon + button glow)              Profiler (records fights via probes,
                                                    compares best vs worst, learns "bias")
                                                            |
            Engine uses bias to order `adaptive` rules <----+
                                                            |
Advisor <--- trainer data, class spells, bags, skills, talents, profiler insights
```

### Route weights

The planner (`Modules/Nav/Planner.lua`) minimises sum(distance x weight). A stop's weight is
set when the route is collected: by the stop itself (`navGoal`) and by the route objective
(`routeObjective`, `Modules/Nav/XpValue.lua`). `Modules/Nav/NearFirst.lua` adds a weight that
depends on where you stand, so it is applied on every plan, not at collect: stops beyond 300 yd
get up to 3x heavier, item drops not within 150 yd 1.5x more, milestones are left alone. The
goals get their own weights back after each plan. `/flow nearfirst on|off`. Not on the
"Shortest" objective (or the completionist route, which plans by distance): that stays the
shortest path.

### Route refresh

A refresh reads one `navGoal` source per frame, then plans in the next (`collectSpread` in
`Modules/Nav/Nav.lua`), so no frame does all of it. The new stops replace the old in one step at
the end. A change that arrives while it gathers, or a direct `N:Collect()`, makes it go once more.

### Dungeon runs

`Modules/Nav/Dungeons.lua` (needs Questie, read at runtime: nothing is copied into the repo)
indexes each dungeon's quests in the background, a few per frame and never in combat. `D:Runs()`
cuts them into runs (one wing, your level, one trip) and compares each with your questing XP per
hour; it's timed in `/flow perf` as "dungeon runs". A prepared run is a `navGoal` source
("dungeon"): its pickups and lead-ins (only those you can take now, `ns.quests:Available`), then
the entrance. Inside, `D:FilterInside` keeps only that dungeon's quests, your waypoint and the
party route. The Flow key's `status` icon suggests the best run.

### UI helpers

- `ns:MakeMovable(frame, save)` (`Core.lua`): Ctrl-drag for ordinary panels (`ns.MoveKeyDown`: the one place that says which key moves things).
- `ns:MoveHandle(button, opts)` (`Modules/MoveHandle.lua`): for secure buttons (the Flow key),
  which can't be dragged themselves or moved in a fight: a handle over the button while Ctrl is
  held, out of combat; drag to move, mouse wheel to resize. `ns.RestorePlace` puts it back.
- `ns.copyBox:Show(title, lines)` (`Modules/CopyBox.lua`): the Flow Copy window, text selected
  for Ctrl+C. Everything `ns:Print` says is kept for `/flow copy`.

### Rotation adaptation (and its limits)

- Rules marked `adaptive = true` that sit next to each other form a group of roughly equal
  options. The engine picks the ready one with the highest learned bias for the current fight
  type. Ties keep the written order.
- Bias comes from comparing casts per minute in the best third and worst third of comparable
  fights. "Comparable" means the same fight type and role, at least 6 seconds long, and within
  3 levels of you. Learning starts after 6 such fights.
- This is correlation, not proof. That's why it only reorders options the rotation author
  marked as interchangeable; it never adds spells or overrides heals and buffs.
- Each role has its own "good fight" metric: DPS for dps, HPS for heal, threat per second for
  tank (if the client exposes threat).

## Quest data

`Modules/Quests/QuestData.lua`, registry kind `questSource`
(`{ order, label, available, get, allIds, doable }`).

- **native** (always): the game API, for completed quests and your quest log.
- **questie** (optional): reads Questie + QuestieDB at runtime if you have them installed.
  They support Forever's classic content. **Never copy their data into this repo:** they have
  no clean licence (treat as all rights reserved). Reading them at runtime as an optional
  dependency is fine, and other guide addons such as Guidelime do the same.
- **LibQuestDB-1.0** (MIT, covers some Forever-only quests): placeholder until its API is
  confirmed in game.
- Route files from RestedXP (CC BY-NC-SA), Guidelime (all rights reserved) and similar guides
  can't be bundled either. They're for reference only, or for reading at runtime if you have
  that addon installed.
- If Flow is open-sourced, MIT works as long as the repo contains no third-party data or
  route text.

Missed quests today: doable quests in zones you've already completed quests in, that you
haven't done and aren't on. **Next step:** route steps (quest ID, NPC, coordinates) so it can
say "you passed this step without picking up X". Also a "learn" mode that records quest
givers from `QUEST_ACCEPTED`, for Forever-only quests that no database covers yet.

## Placeholders to grow into

- `gearAnalyzer`s: sockets, set bonuses, equip effects, enchants, armor type, resistances,
  unique, combos, and valuing weapon speed (see `docs/GEAR_PLAN.md`).
- Talent plan per class in `class.leveling.talentPlan`.
- Per-fight-type rotation lists for boss/elite once there's data showing they should differ.
