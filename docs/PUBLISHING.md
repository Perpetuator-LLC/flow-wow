# Publishing Flow on CurseForge

Status: prepared, not published. Building the zip works today (`tools/package.ps1`). The
steps that need your accounts and decisions are listed below.

## Before the first upload (decisions)
- [ ] **Licence.** Pick MIT or GPLv3 and add a `LICENSE` file; the package script includes it.
  Either works: Flow ships no third-party data and only reads Questie/QuestieDB/Auctionator at
  runtime.
- [ ] **Public name.** "Flow" may already be taken on CurseForge. If so, use something like
  "Flow: Levelling Companion" (the folder and TOC can stay `Flow`).
- [ ] **Author name** in `Flow.toc` (`## Author:`).
- [ ] **Forever on CurseForge.** Check that CurseForge lists World of Warcraft: Forever as a game
  version. If it doesn't yet, upload for Classic Era and say "built for Forever" in the
  description, or wait.

## First upload (manual)
1. Create a CurseForge author account and a new World of Warcraft addon project.
2. Run `powershell -ExecutionPolicy Bypass -File tools\package.ps1`; it builds
   `dist\Flow-<version>.zip`.
3. Upload the zip, choose the game version, and paste in the changelog section for that version.
4. Copy the project ID into `Flow.toc` as `## X-Curse-Project-ID: <id>`.

## Later: automatic releases
Tag a version (`v0.15.0`) and let a Gitea Actions workflow run the BigWigs packager, with
`CF_API_KEY` stored as a repository secret. It reads `.pkgmeta` (to add then) and the TOC's
project ID.

## Blizzard addon policy (already met)
- The addon is free, and its code isn't obfuscated.
- It doesn't automate gameplay: suggestions only. Casting needs a key press or click, and in
  combat the key stays on one spell for the whole fight.
