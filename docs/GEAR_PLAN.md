# Gear analysis plan

What gear scoring does today, and how it will grow. The code lives in `Modules/Gear/`.

## Today

- **Stat weights per role** (`Classes/<Class>/Data.lua`, `weights`): score = sum of stat × weight.
  Weights are tuned for levelling.
- **Comparison**: each role's score minus the score of what you wear in that slot. For rings and
  trinkets that's the weaker of the two; for a two-hander it's main hand + off hand.
- **Verdict**: *Upgrade* for your levelling role (or "upgrade at level N"), *Keep* when it's only
  better for another role (`/flow gear offspec` turns this off), otherwise *Sell*. If your class
  can't use the item at all, the tooltip says so.
- **Quest rewards** (`QuestRewards.lua`): the choice with the biggest gain per role gets a
  D/H/T badge. If nothing is an upgrade for any role, the highest vendor price gets a gold $.
  Uses the same `G:Compare(link)`, so every improvement to scoring improves the badges too.

## Placeholders (in `Modules/Gear/Analyzers.lua`)

Each analyzer returns a per-role bonus plus tooltip notes. The ones marked placeholder add 0 for now
but still show a note, so you can see what isn't counted yet.

`G:TooltipLines(link)` reads the item's tooltip text, for anything the item API doesn't expose.
It only understands an English client.

| Analyzer | Plan |
|---|---|
| `weaponSpeed` | **Reads speed today and notes it against the role's preference** (`weaponSpeed` in class data, e.g. Retribution prefers slow). Next: value speed properly. Abilities that hit for weapon damage (Seals, Judgement, Crusader Strike, Warrior strikes) gain more from a slow weapon at the same DPS. Model it as extra damage per ability use × uses per minute. Fast weapons matter for proc-on-hit and for rage/threat generation. |
| `sockets` | Value each socket as the best gem you'd realistically put in it for that role, plus the socket bonus if matching it is worth it. Needs a gem table per expansion. |
| `setBonus` | Count the pieces of this set you own (worn + bags + bank cache). Value = the next bonus you'd unlock × the chance you'll complete it. Bonuses need a per-set table (stats or a modelled effect). |
| `equipEffects` | Read "Equip:" / "Chance on hit:" tooltip lines and convert them to stat equivalents (e.g. "+X spell damage and healing", procs as average uptime × value). |
| `enchant` | Score the enchant on the item; also mark enchants as "transferable value lost" when replacing. |
| `armorType` | Prefer your best armor type (mail before plate at 40 for paladins), and the late-game bonus for wearing only your best type. |
| `resistances` | Worth something only for specific zones or bosses. Value them when the current zone or instance calls for it. |
| `unique` | "Unique-Equipped": don't suggest a second copy for the other ring/trinket slot. |
| `combos` | Interactions: two-hander vs one-hander + shield per role (Retribution wants a slow two-hander), stat caps (hit/defense) using what you already wear, armor-type bonuses, talents that change weights. |

## Later

- **Level scaling**: weights shift with level (stamina matters more early; mana regen matters more
  for healers later).
- **Whole-set optimiser**: pick the best combination across bags, not item by item, so caps, sets
  and gems are handled together.
- **Learning from play**: feed rotation-helper data back in (e.g. if you're often low on mana while
  questing, raise the weight of Intellect/Spirit).
- **Bag markers**: coloured upgrade arrows on bag icons, not only in tooltips.
