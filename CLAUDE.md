# CS.Coder - Quest Indicator — notes for Claude (and any dev)

Read this first when working on the addon. Last updated 2026-11-08 (v1.1.0 published).

## Working with the user
- Chat in **Brazilian Portuguese**; code, comments, commits, docs and in-game text in **English**.
- The user tests in game and sends screenshots. They like short replies and step-by-step guidance
  for web UIs (CurseForge, GitHub), **one step at a time**.
- There is no way to run WoW here: always run the local checks below before saying something works,
  and ask the user to `/reload` and send screenshots for anything visual.
- Publish (tag) **only when the user says so**: "publica", and also **"manda/sobe pro git" means publish**
  (commit + push + tag the next version), not just push.

## What it is
A floating, animated "!" over quest mobs (on their nameplates) and over the nearest quest item in
the world. Client: **WoW Forever** (`_forever_`, Interface 16001 = CurseForge "WoW Forever 1.60.1"),
a Classic base with modern APIs (C_NamePlate, C_TooltipInfo, C_QuestLog, Settings API).

## Files
| File | What |
|---|---|
| `CSCoder_QuestIndicator.toc` | `## Version: @project-version@` (the packager fills it from the tag), `X-Curse-Project-ID: 1793185` |
| `Locales.lua` | Panel text. `ns.LANGUAGES` = enUS, ptBR, esES (esMX uses it), deDE, frFR, itIT. Blocks are appended over time (minimap, resets, toggles, switches, v2); later blocks override earlier keys. Unknown game languages fall back to English. |
| `CSCoder_QuestIndicator.lua` | Everything else (sections below). |
| `icons/<category>/<name>.tga` | 37 icons (since 2026-11-09, made by the user with ChatGPT), 256 px, 32-bit uncompressed TGA: `standard` (14), `themed` (11), `states` (12). Catalogue `ICON_CATEGORIES`; style key "category/name"; old keys (gold/blue/red/badge/pixel) migrate via `OLD_STYLES`. Picked in a window (`AddIconPicker`/`BuildIconPicker`). `tools/make_icons.ps1` made the old 5 and is obsolete. |
| `media/` | README images only (logo, icon sheet). Ignored by the packager. |
| `tools/` | Dev tools (not packaged): `wowmock.lua`, `halve_tga.lua` (256 -> 128 px icons), `make_icons.ps1`, `make_logo.ps1`, `switch_mode.ps1` + `mode-dev.bat` / `mode-release.bat` (installed addon = junction to source, or a copy of the latest GitHub release). The CurseForge app must NOT manage this addon on the dev PC: on 2026-11-09 it replaced the junction with the v1.1.0 copy. |
| `.pkgmeta` | Packager: ignores media, README, .github, tools, CLAUDE.md. |
| `.github/workflows/release.yml` | Tag `v*` → BigWigs packager `-g forever` → CurseForge + GitHub Releases. |

Install: the source folder lives in `D:\Games\CS.Coder\WoW Addons\CSCoder_QuestIndicator\` and is a
**junction** inside `D:\Games\Battlenet\World of Warcraft\_forever_\Interface\AddOns\`, so edits are
live in game after `/reload`.

## Code map (CSCoder_QuestIndicator.lua)
- **Settings:** `DEFAULTS` = per-profile settings. Saved layout:
  `CSCoderQuestIndicatorDB = { version, language, profiles = { name = settings }, chars = { "Name - Realm" = profile }, savedCVars }`.
  `SETTINGS_VERSION` 5; older flat saves migrate into profile "Default". `db` = active profile, `root` = saved table.
  Main switches: `active` (whole addon), `enabled` (mobs), `objects` (items).
- **Quest detection:** tooltip data (`C_TooltipInfo.GetUnit`, QuestObjective lines, `completed`) or a
  hidden scanner tooltip; `C_QuestLog.UnitIsRelatedToActiveQuest` when present. Quest kind
  (normal/daily/group) from the quest log (frequency, suggestedGroup, tag info) for "color by type".
- **Icons:** one frame type for mobs, the item and the preview. Textures sit on `f.inner`, which the
  **bobber** (OnUpdate, cosine wave) moves. Do NOT go back to a looping Translation/BOUNCE animation:
  it blinks for one frame at the top.
- **Quest items:** world objects only get a nameplate as the interaction soft target
  (`softinteract`, one object, the nearest). The addon opens `SoftTargetNameplateInteract` only for
  quest objects ("gate"), sets `SoftTargetIconGameObject`, range and OnlyInRange, saves the player's
  originals in `root.savedCVars` and restores them when items are switched off. It re-applies on
  `CVAR_UPDATE` because **ForeverLootSparkles** changes the same cvars (it closes the gate for quest
  objects when its "Quest objects" option is off — that was a real bug). Cvars can't change in combat
  (`pendingCVars`).
- **Options panel** (Options > AddOns > **CS.Coder > Quest Indicator**; the "CS.Coder" parent is shared
  through the global `CSCoderOptionsParent` so future CS.Coder addons land under it):
  - **Since 2026-11-09 (user request): only TWO tabs, "Settings" and "Profiles"**, each as wide as its
    label (Ace3 style, `LayoutTabs`, re-run on language change). Settings = ONE scrolling page
    (`BuildSettingsTab`, `SETTINGS_SECTIONS`: Display, Icon, Progress, Behavior), each section with a
    heading and a small "Reset section" button. Dropdown lists are parented to the panel so the scroll
    frame does not clip them. Plain wheel scrolls the page; Shift+wheel steps a slider.
    Behavior also has the objective-complete sound (on/off, sound choice, Test).
    The preview copies a real enemy nameplate measured in the world (`MeasurePlate` ->
    `root.plateGeom`, `ApplyPlateGeometry`, icon `previewRatio`) so preview == world.
  - Sections use two columns (`COL1`, `COL2` = LEFT + 290; sliders `SLIDER_WIDTH` 200, column dropdowns 200):
    Display mobs | items, Icon float | glow, Progress options | font/outline/color (X | Y below),
    Behavior icons | language + sound. Section reset buttons sit at the right of each heading.
    Version shown next to the panel title ("dev" in the source copy).
  - Progress text formatting (2026-11-09): format menu (`PROGRESS_FORMATS`, `FormatProgress`), fonts
    from LibSharedMedia when another addon loaded it (`SharedMedia`, `FontOptions`, saved as
    "lsm:<name>", looked up lazily, no embedded lib), colour "progress" (`ProgressColor`, off by
    default), shadow check (off by default). Dropdowns wrap long lists into columns
    (`DROPDOWN_MAX_ROWS`) and can draw entries in their own font (`fontFor`).
  - Badge (branch experiment/badge, 2026-11-09): progress text in a badge; shape square/rounded/pill
    (`BADGE_SHAPES`, caps `icons/badge/*.tga` made by `tools/make_badge.lua`, `ShapeLayer`), border
    thickness, fill and border colours via the game colour picker (`OpenColorPicker`, both APIs,
    `AddColorSwatch`). Colour settings are {r,g,b,a} tables, always replaced, never edited in place.
  - (Older layout notes below.)
  - Left: a box of **four Ace3-style tabs** (game textures `UI-OptionsFrame-ActiveTab/InActiveTab`,
    tabs stretched to fill, like BlizzMove): **Display** (Enable addon; Quest mobs ☑ + size, horizontal
    offset, height; Quest items ☑ + size, height), **Icon** (style; Float ☑ + height, duration; Glow ☑ +
    intensity), **Behavior** (color by quest type, minimap button, In combat dropdown, Language dropdown),
    **Profiles** (since 2026-11-09 the Ace3/RareScanner layout the user asked for: intro, Reset Profile,
    Current Profile, New editbox + Existing Profiles dropdown, Copy From, Delete a Profile with a
    StaticPopup confirm; no rename). Other tabs have "Reset this tab". Dropdowns accept a function
    for options (lists that change).
  - Preview: since 2026-11-09 its own movable window (`PreviewWindow`, opens/closes with the panel,
    close button sets `root.previewHidden`, position in `root.previewPos`, "Preview" button toggles);
    the options box fills the panel. Sliders have a type-in box (Enter applies, Esc reverts).
  - **Gates:** controls fade and lock when what they depend on is off (`Gate`, `UpdateGates`). The minimap
    checkbox never locks (it is how you turn the addon back on).
  - Dropdowns are self-made (UIDropDownMenu differs/deprecated across clients).
  - Static texts go through `Loc(object, key)` so a language change relabels live.
- **Minimap button:** left-click options, right-click toggles `active`, drag around the edge; grey when off.
- **Setup guide** (`BuildWizard`, `ShowWizard`, `/cqi setup`): shown 3 s after login the first time on
  a character (`root.setupSeen[charKey]`; chars from before it existed are marked seen on update).
  Page 1 = logo (`icons/logo.tga`, made by `tools/make_logo_tga.ps1`), greeting, "Use default
  settings" / "Configure". Configure = Look (icon, size, anchor, X/Y, float, glow + "Use default";
  the user wants it all on one page), What to show, Done, each beside
  its own live preview (`previews` list: `BuildPreview` can make several). Any close marks it seen.
  Texts are English only until the user approves the layout.
- **Icon anchor** (`anchor`, `objectAnchor`): top/bottom/left/right of the plate; side anchors use
  the health bar (`PlateBar`). Changing it resets X/Y to that side's start.
- **Lua 200-locals limit:** the main chunk is close to it (about 6 free on 2026-11-09). New helpers
  go inside `do ... end` blocks (see the setup guide and the plate measuring code).
- **Plates on WoW Forever are restricted:** GetTop/GetPoint error ("Can't measure restricted
  regions"); size and scale can be read. `MeasurePlate` protects every read and estimates the bar.
- `/cqi` opens the options, `/cqi toggle` toggles the addon.

## Local checks (run before every hand-off)
LuaJIT (Lua 5.1, same as WoW) is installed: `C:\Users\Claudio\AppData\Local\Programs\LuaJIT\bin\luajit.exe`.
```bash
LJ="/c/Users/Claudio/AppData/Local/Programs/LuaJIT/bin/luajit.exe"
A="D:/Games/CS.Coder/WoW Addons/CSCoder_QuestIndicator"
for f in Locales.lua CSCoder_QuestIndicator.lua; do "$LJ" -e "local f,e=loadfile('$A/$f'); print('$f', f and 'OK' or e)"; done
"$LJ" "$A/tools/wowmock.lua" "$A"        # runs the addon on a mocked WoW API, clicks every control
"$LJ" "$A/tools/wowmock.lua" "$A" old    # same, starting from an old (v4) saved-variables file
```
Expect `errors: 0` and `unexpected nil globals: none`. When the mock reports an error, first check
whether the mock is missing an API (e.g. it once returned nil for `GetHighlightTexture`,
`GetStringWidth`, `check.Text`) before blaming the addon. The mock can't judge layout.

## Release
- GitHub: **cscoder69/CSCoder_QuestIndicator** (public, MIT). `gh` CLI at `C:\Program Files\GitHub CLI\gh.exe`, logged in as cscoder69.
- CurseForge: project **1793185**, author CSCoder. Repo secret `CF_API_KEY` is set (CurseForge API token).
  Keep CurseForge's own "Automatic Packaging" **off** (the GitHub Action does it; both would double-upload).
- **Version numbers (user, 2026-11-09):** bump only the third digit for now (v1.2.1, v1.2.2, ...);
  the minor number was going up too fast.
- Commits publish nothing. To release: bump nothing by hand, just
  `git tag -a vX.Y.Z -m "..." && git push origin vX.Y.Z`, then `gh run watch` the "Package and release" run.
  New files go through CurseForge moderation.
- A zip for a friend without a release: `git archive` the addon files, replace `@project-version@`
  in the .toc, zip with forward-slash paths (see v1.1.0 in the history).

## History
- 1.0.0 (2026-11-08): mob icons, item icon (soft target), options panel. Uploaded by hand.
- 1.1.0 (2026-11-08): options v2 (4 tabs, fixed preview, gates), profiles, 6 languages, color by
  quest type, combat fade/hide, minimap button, hand-driven float, ForeverLootSparkles cvar fix.
  First release through the GitHub Action (worked first time).

## Ideas the user liked, not done yet
- **Separate look for mobs vs items** (own style, float and glow per kind). Proposed a [Mobs | Items]
  selector; after that the user chose the 4-tab layout, and this stayed open — ask before building.
- **Badges** (like ItemTree's "Keep 12" pill): a floating, draggable tracker of objective badges
  ("Timberling Sprouts 8/12"), or a badge with progress above the mob.
- More: custom icon color, show only on target/mouseover, transparency, hide in dungeons/raids,
  sound when an objective completes, keybinding to toggle.
- Translations of any new text: write English first, translate when the layout is approved.
- **Roadmap agreed 2026-11-09** (in this order of interest):
  1. Progress text ("8/12") — BUILT 2026-11-09, awaiting in-game test: own "Progress" tab, on/off,
     "Attach to the icon" (X/Y from the icon, follows it; off: X/Y from the nameplate) and a separate
     "Float with the icon" (bobs in step; needs the icon's Float), own size and X/Y. Text frame
     undoes the icon scale (`f.text`, `PlaceText`).
  2. X / Y labels with -200..200 ranges and mouse-wheel steps — BUILT 2026-11-09 (items got X too).
     Drag-to-position on the preview: user postponed it for a long time (2026-11-09).
  3. Separate look for mobs vs items (approved).
  4. Custom icon color + transparency.
  5. Sound when an objective completes (user loved it).
  6. Small extras, LAST: keybinding toggle, hide in dungeons/raids, only on target/mouseover.
  - Objective tracker with badges: later, it overlaps Questie.
  - CurseForge page: GIF of the icons, screenshots of the panel/styles, better title/summary/description.
- **Other WoW clients** (Classic Era/Anniversary, Cata/MoP Classic, Retail): user decided 2026-11-09
  to wait until the addon is more mature. Don't push it before then.
