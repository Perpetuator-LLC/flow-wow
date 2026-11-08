# Share your Flow places

Flow learns where things are as you play: every NPC you talk to (vendors and whether they
repair, trainers, flight masters, innkeepers, bankers, auctioneers, quest givers) and every
mailbox you open. It remembers them for all your characters, and uses them for your route and
for "Nearest repair / vendor / flight master..." (right-click the arrow).

You can share what your Flow has learned with every Flow player. It's **opt in**, and only goes
out when you send it.

## What's shared

NPCs only:
- their name and NPC ID;
- where they stand (map and coordinates);
- what they do (vendor, repair, trainer, flight master, innkeeper, banker, auctioneer, quest giver);
- which faction used them (so a Horde vendor is never offered to an Alliance player).

Plus where mailboxes are. **Nothing about you**: no character names, realm, account or play
times.

## How

1. In game: `/flow places share`, then `/reload`. The game saves the list when you reload.
   `/flow places` shows how much Flow has learned and whether you're sharing.
2. Send it to Flow. Either:
   - **with Claude:** ask your Claude session "share my Flow places". It follows CLAUDE.md: it runs
     the script and opens a pull request for you; or
   - **by hand:** in your Flow folder run
     `powershell -ExecutionPolicy Bypass -File tools\share-places.ps1`, then commit
     `Learned\Places.lua` on a branch and open a pull request (see CONTRIBUTING.md). Data-only pull
     requests need no version bump or CHANGELOG entry.
   - **no Git?** Send your `WTF\Account\<name>\SavedVariables\Flow.lua` to the maintainer, who runs
     `tools\share-places.ps1 -From <that file>`. The script reads only the shared list from it.
3. Once it's merged, every Flow player gets those spots with the next update.

`/flow places share off` takes the list out of your saved data again (at your next reload).

## How Flow uses shared spots

- Your own visits always come first. A shared spot is used only for an NPC you haven't talked to
  yourself.
- Only spots your faction can use.
- "Nearest ..." says when the one it picked was found by another Flow player.

## For the maintainer

`tools\share-places.ps1` merges a player's list into `Learned\Places.lua`, the file that ships
with Flow:
- new NPCs are added;
- known ones only gain roles, factions or an NPC ID; where they stand stays as first shared, so it
  doesn't flip between players;
- every field is checked (names can't contain quotes or control characters; coordinates are
  between 0 and 1), and the output is sorted, so the same data always gives the same file.

`-DryRun` shows what would change without writing anything.
