# Flow

Sooth's personal World of Warcraft addon: one place to put whatever features we want.

## Layout

This is the World of Warcraft addon. It is a separate project from Flow Engine. The game is
**World of Warcraft: Forever** (client folder `_forever_`).

- `Flow.toc`: addon manifest (load order, saved variables, interface version)
- `Core.lua`: shared namespace `ns`, event bus (`ns:On(event, fn)`), **registries**
  (`ns:Register` / `ns:Get` / `ns:Each`), `/flow` slash command, `FlowDB` saved vars
- `Modules/`: features (rotation, fight profiler, advisor, gear, quests, ...)
- `Classes/<Class>/`: everything class-specific (data, trainer spells, rotation)
- `docs/ARCHITECTURE.md`: every extension point, and how to add a class without touching
  existing code.

## Features

- **Greeting**: shows a "hello sooth" dialog on login. `/flow hello` shows it again.
- **Rotation helper** (`Modules/Rotation/`): shows the spell to press next as an icon below
  the middle of the screen, and makes the matching action bar button pulse. Suggestion only:
  WoW does not let addons cast for you.
  - Border colour: green = damage, yellow = buff, blue = efficient heal, red = emergency heal.
  - **Self-heal logic**: suggests a heal only when, by the time the cast lands (cast time plus
    your latency), you'll be missing at least as much health as the heal restores, so nothing is
    wasted. Crits are ignored. It suggests an emergency heal when the incoming damage would
    kill you before you could react, unless your target will die first.
  - **Learning**: records how much your heals really restore (non-crits only) and how hard each
    kind of mob hits you, and uses both in later fights. The data is kept in `FlowDB`.
  - Rotation rules live in `Classes/<Class>/Rotation.lua`. The rules list spells you don't know
    yet; the helper skips them until you learn them. A class can give a different priority list
    per fight type (boss, several enemies, elite, normal).
  - Commands: `/flow rot on|off|lock|unlock|stats|known|debug|reset` (`known` lists the spells
    Flow thinks you have).
- **Fight profiler** (`Modules/Fight/`): records every fight: damage, healing, threat, damage
  taken, what you cast, your opener, and whether you followed the suggestion. Fights are
  labelled by type: boss, several enemies, elite or normal. After 6 comparable fights of a type,
  it compares your best third with your worst third. Spells you used more in your best fights
  move up within the rotation's interchangeable groups. `/flow fights` shows the findings;
  `/flow fights report` prints a one-line summary after each fight.
- **Advisor** (`Modules/Advisor/`): an orange "!N" button next to the rotation icon. It lists
  ways to get better, most important first, each with what it improves: spells to train
  (from your last trainer visit, or from guide data), rotation spells missing from your action
  bars, upgrades sitting in your bags, empty gear slots, unspent talent points, professions
  that are capped or behind your level, and habits from your best fights. Hover the button to
  see the list, click it to print, shift-drag to move. Also `/flow advice`.

- **Quest markers** (`Modules/QuestMarks.lua`): icons above nameplates. Skull = a mob you need
  to kill, diamond = a mob that drops an item you need, star = an NPC your quest mentions.
  Which mob drops which item is learned the first time you loot one. Nameplates must be on
  (V for enemies, Shift+V for friendly, or `/flow quest plates`). `/flow quest` lists your
  objectives.
- **Training** (`Modules/Trainer.lua`): reminds you at each level up, and at the trainer lists
  what you can learn now and whether you can afford it.
- **Spec advice** (`Modules/Spec.lua`): `/flow spec` shows the recommended levelling spec and
  why. `/flow spec dps|heal|tank|auto` picks the role that gear advice favours.
- **Gear scores** (`Modules/Gear/`): every item tooltip shows a score for each role:
  red = DPS, green = Heal, blue = Tank. Each score shows +/- against what you wear, plus a
  verdict: Upgrade, Keep (better for another role) or Sell. Stat weights are in
  `Classes/<Class>/Data.lua`. Weapon speed, sockets, set bonuses and equip effects show a
  note but aren't scored yet. Enchants, armor type, resistances, unique items and combos are
  empty placeholders. See [docs/GEAR_PLAN.md](docs/GEAR_PLAN.md).
- **Quest reward badges** (`Modules/Gear/QuestRewards.lua`): when a quest offers a choice, the
  best upgrade for each role gets a badge: red D (DPS), green H (Heal), blue T (Tank). If no
  choice beats what you wear for any role, the one that sells for the most gets a gold $.

- **Navigation arrow** (`Modules/Nav/`): points at your next quest goal: the nearest spawn of a
  mob to kill, the mobs or objects that drop an item you need, or the NPC to turn in to. It
  shows a short sentence and the distance. Left-click for details, right-click for the next
  goal, shift-drag to move. **Pathing:** WoW doesn't tell addons where you can walk, so Flow
  records the trails you travel and uses A* search over them. Once trails are known, the arrow
  leads you along roads and around hills; in new places it points in a straight line.
  Locations need Questie + QuestieDB. `/flow nav on|off|learn|forget`.
- **Missed quests** (`Modules/Quests/`): `/flow missed`, plus advisor entries. Lists quests in
  zones you've quested in that you haven't done (needs Questie + QuestieDB; data is read at
  runtime, never copied).

- **Combat log analysis** (`tools/analyze-combatlog.ps1`, `Modules/CombatLogFile.lua`): Forever
  blocks addons from *listening to* the combat log, but the game can still *write* it to
  `Logs\WoWCombatLog*.txt`. `/flow log` toggles that, and `/flow log auto` turns it on at every
  login. The script reads the files and writes:
  - a report with DPS by fight type, damage by spell, your best vs worst fights (casts per
    minute, seal uptime, opener), heal sizes and overheal, avoidance, how hard each mob hits,
    and recommendations. It goes to `H:\wow-notes\WoW Forever\Reports\`.
  - `Learned\CombatLog.lua`, which Flow loads to use those learnings. It sets the spell order
    within the adaptive groups and the real heal sizes, and seeds how hard each mob hits.
  Run it with: `powershell -ExecutionPolicy Bypass -File tools\analyze-combatlog.ps1`,
  then `/reload` in game.

## Debugging without a Lua install

`/flow rot why` explains each rotation rule. It shows whether the spell is known, its
condition, cooldown, range, whether it's on your bars, and the last error.

This PC has no Lua interpreter, so code is only checked in game. Turn on `/console scriptErrors 1`
to see errors, or use `/flow rot debug` to show the reason for each suggestion and any errors
the rotation helper catches.

## Install (dev)

The addon folder in the game is a junction pointing at this repo, so edits here are live after `/reload`:

```
G:\Blizzard\World of Warcraft\_forever_\Interface\AddOns\Flow  ->  H:\Flow
```

## Interface version

The `## Interface:` number in the `.toc` must match the client, or the addon shows as "out of date".
In game, run `/dump select(4, GetBuildInfo())` to get the right number and put it in the `.toc`.
