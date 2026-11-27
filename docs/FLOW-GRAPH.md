# The Flow graph: learning routes from every player

A plan, not a description of what exists. What exists today is marked **built**; the rest
is proposed, and the choices that are the maintainer's to make are listed at the end.

## The idea

Flow plans a route by ordering the steps near you. That misses whatever isn't near: a class
quest that sends you out of the zone, a chain you should have started two zones ago, a
finished quest whose hand-in was the 31st nearest step. The fix is to plan over the whole
game once, offline, and let each player's Flow follow the part of that plan that applies to
them. Two things are needed for that, and they're separate:

1. **How long things take**: the time to get from any place to any other. Learned from
   players, the quickest wins.
2. **What must come before what**: every quest, every objective, every profession step, and
   what each one needs first. Mostly known already (Questie's data, Flow's guides).

Put together they make one graph. An optimiser turns it into an order. That order, with the
learned times, is the payload Flow ships and updates.

## Part 0: what the player did (built in 0.35.413, local only)

`Modules/Quests/Journal.lua` keeps, per character, every quest taken and handed in and every
level gained: when, where, at what level, the XP a hand-in gave, what the route's next step was
at that moment and where on the route the thing done stood (`rank`: 1 = it was the next step,
nothing = it wasn't on the route). It is the measure every later part needs: without it there
is no telling whether a change to the planner made a player's hour better or worse. The journey
before 0.35.413 can't be rebuilt: the game keeps which quests are done, not when.

## Part 1: trips (built in 0.35.350, local only)

`Modules/Nav/Legs.lua` times every trip from one step to the next and keeps your quickest for
each pair of places. A leg is:

| Field | What | Example |
|---|---|---|
| continent | the game's number | `1` |
| from, to | two 40-yard squares of the map | `"12:-67"`, `"-13:-66"` |
| `s` | seconds travelling (not fighting, not standing still) | `183.0` |
| `d` | the straight line between them, yards | `1040` |
| `m` | on foot, riding, or by flight | `"foot"` |
| `n`, `at` | how often, and when last | `3` |

No name, no quest, no character, no clock time beyond "last used" (which wouldn't be shared).
The planner already uses these: an exact trip is taken as its cost; trips between the same
two 250-yard neighbourhoods stretch the straight line by what such trips took.

Also built earlier, and part of the same picture: the **trail network** (points every 15
yards where you've walked, with the quickest time for each join; the arrow follows it), and
**gates** (lifts, city gates, passes between zones) learned as you pass through them.

### What sharing needs that local learning doesn't

- **Speed.** My 183 seconds on foot at level 21 and your 110 on an epic mount are the same
  road. A shared leg must be stored as *distance along the ground at a known speed*, not
  seconds: `ground yards = seconds x the speed you were moving at`. Then each player's Flow
  divides by their own speed. Legs.lua records the mode but not yet the speed; that's the one
  field to add before anything is shared (`v`, yards a second, averaged over the trip).
- **Flights are different.** A flight's time doesn't depend on the player. Shared as seconds,
  keyed by the two flight masters, and only usable by someone who has both.
- **"The fastest wins" needs a guard.** One mis-timed trip (lag, a warlock summon, a bug)
  would become the standard for everyone. Keep the quickest that at least **three different
  contributions** agree on within 10%, not the single quickest.
- **Faction, class, level.** A Horde road through Orgrimmar is no road for Alliance; a
  druid's travel form and a mage's portals change what's quick. Each leg carries faction
  (`H`, `A` or both), and class only when a class ability made it (detected by the jump or
  the speed).
- **Size.** A leg is about 30 bytes as text. Azeroth's quest content is a few thousand
  places; pairs that anyone actually travels between are tens of thousands, not millions.
  About 1 MB for a well-covered world, far less after a merge keeps only the best.

## Part 2: the whole-game graph

### Nodes

One node for each thing a player does at a place:

| Node | Example | Comes from |
|---|---|---|
| accept a quest | Accept: Echeyakee | Questie at run time |
| get the thing that starts a quest | Loot the Workshop Key (drops, then starts a quest) | Questie's "starts from item" |
| an objective | Kill 8 Sunscale Screechers; collect 5 Earthroot | Questie |
| get what an objective needs first | Find a Shrine Bauble before the shrine | Questie's "source items" |
| hand in | Turn in: Echeyakee | Questie |
| train | Class trainer at level 22; Journeyman Herbalism | Flow's class and profession data |
| a profession step | Smelt 20 copper; fish to 75 | Flow's guides |
| travel points | Learn a flight path; set your hearthstone | Flow |

Flow builds exactly these today as "steps" (`Modules/Nav/Goals.lua`, the `navGoal`
registry), but only for the quests in your log and the pickups around you. The graph is the
same thing for every quest in the game at once.

### What must come first (edges that order)

- a quest's objectives after its accept; its hand-in after its objectives;
- the next quest of a chain after the one before it is handed in;
- a quest that needs another one done, a level, a class, a race, a profession skill, a
  reputation;
- an objective after the item it needs;
- a profession step after the skill and the materials before it.

Flow already holds most of these as `goal.deps` and `Needs.lua`; chains come from Questie's
`preQuest` / `nextQuestInChain` fields, read at run time.

### What it costs to go from one to the next (edges that weigh)

The learned trips of part 1, with the straight line where nobody has been.

### The data rule

**Flow ships no Questie data** (CLAUDE.md, "Data rules"). The graph payload therefore holds
only what is Flow's own: quest *numbers*, an order, and learned times between squares of the
map. Names, places, objectives and requirements are still read from Questie on the player's
machine. A quest number and "this comes 412th" is not anyone's data.

## Part 3: the optimiser

### What "optimal" can and can't mean

Ordering thousands of nodes with before/after rules so the total travel is least is a
travelling-salesman problem with precedence. Nobody can prove the best order for a problem
that size; good solvers get within a few percent of it, and that is what "optimal" will mean
here. Two more things make the real problem harder than travel alone:

- **Level.** You can't do a level 40 quest at level 20, and the order you do things in decides
  when you reach 40. So it is a schedule, not only a tour: each node has an XP reward and a
  level it opens at.
- **What the player wants.** Fastest to 60 and "do everything" are different orders.

### How to solve it

Not in the game. WoW gives an add-on a few milliseconds a frame and no way to run for
minutes. The solve is an offline tool that reads the graph and the merged trips and writes
the order:

1. **Cluster.** Group nodes into hubs (a town and the objectives around it): a few hundred
   hubs instead of thousands of nodes. Chains and class quests tie hubs together.
2. **Order the hubs** by level band and travel, with a precedence-aware solver (an LKH-style
   local search, or OR-Tools' routing solver; both handle "A before B" and time windows, which
   is how level gates are expressed).
3. **Order inside each hub** exactly (they're small).
4. **Score** by simulated time to finish, using each leg's ground distance at a reference
   speed per level band (on foot to 40, mount after).
5. Keep the result only if it beats the current one. Every run starts from the current best,
   so the order only ever improves, which is the "a faster way becomes the new standard" the
   idea asks for.

### What ships

`Learned/Graph.lua`, per faction (class quests as a per-class overlay):

- `order`: quest numbers in the order to do them, each with the hub it belongs to and the
  level band it sits in. A few bytes a quest: about 30 KB for everything.
- `legs`: the merged trips. The larger part: up to 1 MB, less in practice.

### In the game

- **Filtering is free.** Leaving out professions, a zone, or a quest line removes nodes; the
  rest keep their relative order, which is still a valid order (nothing that remains needed
  something that was removed, or it's removed too).
- **Re-optimising the remainder** is what Flow's planner already does: it takes the next 30
  or so nodes *in graph order* rather than the 30 nearest, and polishes those with the
  player's own position, bags, hearthstone and flight paths. The graph says what's next; the
  planner says how to walk it from where you stand.
- **This fixes what local planning can't see**: "accept this chain now, you'll be at step 3
  of it when you're in Stonetalon"; "leave the zone at 16 for the class quest, then come
  back"; "this finished quest's hand-in is far, but it's next".

## Part 4: getting data from players to the graph

In order of how much they need deciding:

1. **Now, no network (the way `Learned/Places.lua` works today).** `/flow legs share` writes
   the shareable legs into the saved-data file; `tools/share-legs.ps1` merges them into
   `Learned/Legs.lua`; a data-only pull request sends them. Slow, but nothing leaves a
   machine without its owner running a command, and it can ship before any service exists.
2. **A companion that uploads.** WoW add-ons can't use the network. A small program on the
   player's machine (or Claude, as with `/si`) reads the saved-data file after a session and
   posts the new legs. Needs a server, an opt-in, and the decisions below.
3. **A service that merges and solves.** Receives legs, merges them with the guard above,
   runs the optimiser nightly, publishes `Learned/Graph.lua`. Flow picks it up with its
   normal update (the add-on and the graph can have separate version numbers, as proposed).

## Decisions that are the maintainer's

Nothing is uploaded anywhere until these are settled.

1. **Which fields are shared.** Proposed: continent, two squares, ground yards, mode,
   faction, class-only flag. Not shared: character, realm, account, times of day, quests in
   the log, anything about bags or gold.
2. **Where it goes.** A GitHub repository via pull requests (step 1), or a server of
   Perpetuator's (steps 2 and 3).
3. **Opt-in or opt-out.** Proposed: off until the player ticks "Share the trips Flow learns",
   with a line in the settings saying exactly what is sent.
4. **Whether the optimiser's objective is "everything" or "fastest to 60"** as the shipped
   default, with the other as a filter.
5. **Reference speeds** for scoring (on foot until which level, which mount speeds).

## Order of work

| Step | What | Needs a decision |
|---|---|---|
| 1 | Trips timed locally and used by the planner | built, 0.35.350 |
| 2 | Record speed with each leg; use the trail network's times for trips nobody made end to end | no |
| 3 | The planner takes its candidates in dependency order, not only by nearness (chains and class quests first, from the data on the machine) | no |
| 4 | `/flow legs share` and `tools/share-legs.ps1`, into `Learned/Legs.lua` | 1, 2 |
| 5 | The graph builder and optimiser as an offline tool; `Learned/Graph.lua` | 4, 5 |
| 6 | Flow follows the graph's order, filtered | after 5 |
| 7 | Companion upload and the nightly service | 2, 3 |
