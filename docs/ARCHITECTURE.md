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
| `navGoal` | any | `{ collect = fn() -> { {key, points, text, kind, weight, optional, cost, blockedBy, anywhere}, ... } }` | Route: `cost` (copper) or `blockedBy` (text) keeps a stop off the route but listed with its reason |

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
Research notes: `H:\wow-notes\research\Quest Database Options.md`.

## Placeholders to grow into

- `gearAnalyzer`s: sockets, set bonuses, equip effects, enchants, armor type, resistances,
  unique, combos, and valuing weapon speed (see `docs/GEAR_PLAN.md`).
- Talent plan per class in `class.leveling.talentPlan`.
- Per-fight-type rotation lists for boss/elite once there's data showing they should differ.
