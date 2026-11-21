# Merging a contributor's pull requests (maintainer, and the maintainer's AI)

How pull requests get from GitHub into `flow-0.10` and back out to `main`. Written down after
doing it by hand for pull requests 5 to 22, so the next merge is a checklist and not a
rediscovery. Contributors: your side is [CONTRIBUTING.md](../CONTRIBUTING.md).

## The shape of it

- The maintainer works on `flow-0.10`. GitHub's `main` is `flow-0.10`, pushed. The GitHub remote
  is called `github` (`origin` is private).
- A pull request is **merged locally, fixed on top, then pushed**. GitHub marks it "merged" by
  itself when its head commit arrives on `main`; nobody clicks Merge on the website.
- Every merge gets its own version number and a thanks line in the changelog. Fixes found in
  review go in **one more commit and version on top**, not into the contributor's commits.

## Steps

1. **What's open, and where each one's head is.**
   ```
   gh pr list --repo Perpetuator-LLC/flow-wow --state open --json number,title,headRefOid
   ```
   Note every `headRefOid`. You check them again in step 8: a contributor may push while you
   work.
2. **Fetch the heads** (never check out a contributor's branch in the main folder):
   ```
   git fetch github pull/18/head:refs/pr/18
   ```
3. **Stacked pull requests.** A contributor often builds one on another. Find out which
   contains which, and merge from the bottom up, so each merge brings only its own commits:
   ```
   git merge-base --is-ancestor refs/pr/18 refs/pr/19 && echo "19 builds on 18"
   ```
4. **Merge in a side worktree**, not in the folder the game reads. The game folder is a
   junction to the main checkout, so a half-merged tree would load at the player's next
   `/reload` (it happened: five tests failed on a reload that landed mid-edit).
   ```
   git worktree add <scratch>/merge -b merge-prs flow-0.10
   git merge --no-ff refs/pr/18 -m "Merge PR #18 (Name) as 0.35.164: what it adds"
   ```
5. **The usual conflicts**, each merge:
   - `CHANGELOG.md`: their `## Unreleased` block against our numbered entries.
     `tools/pr-changelog.sh CHANGELOG.md 0.35.164 18 Name` settles it: their block goes on top,
     numbered, with "(Thanks, Name: pull request 18.)".
   - `Flow.toc`: keep both sides' new files; set `## Version:` to this merge's number.
   - `Modules/Tests.lua`: both sides append tests at the end; keep both.
   Then `tools\lint.ps1`, and commit the merge.
   - **A changelog that merges without a conflict is still wrong.** When our top of the file has
     moved far from the contributor's base, git puts their `## Unreleased` block where the top
     used to be, hundreds of lines down, and says nothing. After the merges,
     `grep -n "^## Unreleased" CHANGELOG.md` must find none: move each block to the top,
     numbered, with its thanks line. A pull request with no changelog entry gets one written
     here (0.35.360, 0.35.361).
6. **Review what came in** (the list below), as its own pass after everything is merged: a
   later pull request often fixes or changes an earlier one. Reviewing can be handed to
   sub-agents, one per pull request, each given the diff and this list; they report, the
   maintainer's session fixes.
7. **Fix on top**: one commit, the next version, a changelog entry "Fixes from the review of
   pull requests 18 to 22" that says what a player would notice. Add a test per fix. Lint.
8. **Check the heads again** (step 1's command). New commits: fetch and merge them first.
9. **Move it over and push.** In the main checkout:
   ```
   git merge --ff-only merge-prs
   ```
   then lint once more and push with the command in [PUBLISHING.md](PUBLISHING.md)
   (`... push github flow-0.10:main`). The push also publishes whatever else was waiting on
   `flow-0.10`: say so in the report if any of it hasn't been seen in the game yet.
10. **Confirm and clean up.** `gh pr list --state open` should no longer show them (GitHub
    needs a few seconds). Remove the worktree and the `merge-prs` branch. Keep `refs/pr/N`: they
    cost nothing and show what was merged.
11. **Ask for a `/reload`** (two, with some play in between) and read `tools\read-diag.ps1`:
    lint can't run the tests, only the game can.

Never run a contributor's scripts (`tools/*.py` and the like) while reviewing. Read them.

## What review keeps finding

The same things, pull request after pull request. Checking for them first saves most of the
time. Each line: what to look for, and why it bites on WoW: Forever.

| Look for | Why |
|---|---|
| A bare game function for items: `GetItemCount`, `GetItemInfo` | Gone or moved on Forever. `ns.api.Count`, `ns.api.ItemInfo` (0.35.169: a test called one and failed at every login). |
| A distance or range question asked in a fight (`CheckInteractDistance`) | Forbidden in combat on anything but an enemy: a "blocked action" popup. Go through `ns.rotation.Near` (0.35.159, again in 0.35.169). |
| Work on a tick (the 10-a-second display, every refresh of an open window) that reads buffs, bags or the whole plan | The slowdown. Once a second, out of a fight, or kept until its inputs change (0.35.169: buffs read ten times a second). |
| A setting about one character saved account-wide | `ns:PerCharacter("section.field")` next to its `ns:OnLoad` (0.35.169: "Only the dungeon run"). |
| A new option that doesn't follow the group it joins (a radio button among ticks) | The route's "includes" are ticks since 0.35.157; settings are grouped by use since 0.35.170. |
| An item matched by its ID only | Forever's IDs differ from classic's. By ID or by name (0.35.169: the enchanting rods). |
| A test that depends on the player (in a fight, dead, their route ticks, their language) or leaves something behind | It fails for the next player, or at the next run. Pass values in; put back what you change (0.35.170: the press audit test counted its own leftover). |
| A test that stands in for a game global (`with(_G, ...)`) | Taints it for the session and blocks the Flow key. Lint refuses it. |
| Hard-coded colours, a title bar built by hand | `ns.theme`, `ns.theme:TitleBar`. |
| Something clickable with no click test | CLAUDE.md, "Every change": call its OnClick in a `pcall`. |
| Skill numbers and item facts taken from memory | Check them (0.35.169: Thorium at 245, not 230). Wrong data sends the route to the wrong place. |
| A view not named "Flow <Name>", or text that says "restart the game" | CLAUDE.md, "Style"; a `/reload` is always enough. |

None of this is special to contributors: the maintainer's own changes get the same pass.

## When this changes

If a merge goes differently (a new kind of conflict, a step that turned out unnecessary, a new
thing review found twice), change this file in the same commit. The table above also lives,
shorter, in CONTRIBUTING.md ("Before you send it") so pull requests arrive needing fewer fixes:
keep the two in step.
