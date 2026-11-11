# CS.Coder - Quest Indicator — notes for Claude (and any dev)

Read this first when working on the addon. Last updated 2026-11-11 (v1.2.5 published).

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
| `icons/<category>/<name>.tga` | 37 icons (since 2026-11-09, made by the user with ChatGPT), 256 px, 32-bit uncompressed TGA: `standard` (14), `themed` (11), `states` (12). Catalogue `ICON_CATEGORIES`; style key "category/name"; old keys (gold/blue/red/badge/pixel) migrate via `OLD_STYLES`. The 37 were re-cut on 2026-11-09 from the guide sheet by `tools/slice_icons.lua` (the first files were cut on a wrong grid: slivers of the neighbour, right edge lost). Picked in a window (`AddIconPicker`/`BuildIconPicker`). `tools/make_icons.ps1` made the old 5 and is obsolete. |
| `media/` | README images only (logo, icon sheet). Ignored by the packager. |
| `tools/` | Dev tools (not packaged): `wowmock.lua`, `halve_tga.lua` (256 -> 128 px icons), `make_icons.ps1`, `make_logo.ps1`, `switch_mode.ps1` + `mode-dev.bat` / `mode-release.bat` (installed addon = junction to source, or a copy of the latest GitHub release). The CurseForge app must NOT manage this addon on the dev PC: on 2026-11-09 it replaced the junction with the v1.1.0 copy. |
| `.pkgmeta` | Packager: ignores media, README, .github, tools, CLAUDE.md. |
| `.github/workflows/release.yml` | Tag `v*` → BigWigs packager `-g forever` → CurseForge + GitHub Releases. |

Install: the source folder lives in `D:\Games\CS.Coder\WoW Addons\CSCoder_QuestIndicator\` and is a
**junction** inside `D:\Games\Battlenet\World of Warcraft\_forever_\Interface\AddOns\`, so edits are
live in game after `/reload`. Second dev PC (notebook, set up 2026-11-11): source in
`G:\Games\CS.Coder\WoW\CSCoder_QuestIndicator\`, game in `G:\Games\Battlenet\World of Warcraft\_forever_\`
(same junction). Git/gh/LuaJIT installed with winget; LuaJIT at the same path as below.

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
  Translated in all 6 languages (2026-11-09).
- **Icon anchor** (`anchor`, `objectAnchor`): top/bottom/left/right of the plate; side anchors use
  the health bar (`PlateBar`). Changing it resets X/Y to that side's start.
- **Lua 200-locals limit:** the main chunk is close to it (see UI v2 below for the current room). New helpers
  go inside `do ... end` blocks (see the setup guide and the plate measuring code).
- **Plates on WoW Forever are restricted:** GetTop/GetPoint error ("Can't measure restricted
  regions"); size and scale can be read. `MeasurePlate` protects every read and estimates the bar.
- **Quest items' own look** (`objectOwnLook`, `objectStyle`, `objectBounce`, `objectGlow`, off by
  default): `Look(f, key)` picks the item's or the shared value; the icon picker edits any style key
  (`AddIconPicker(..., key)`, `iconPicker.key`). Float height/time and glow intensity stay shared.
- **Count on quest items** (`objectProgress`, on by default): `IsQuestObject` returns progress too.
  When tooltips show nothing, mobs and items fall back to their name in an unfinished objective of
  the quest log (`ObjectiveKindForName`, catches "Coyote" in "Coyote Tail: 3/8" too).
- **Hover help:** sliders and dropdowns show `TIP_<label key>` (when it exists) and `SLIDER_HINT`.
- **What's new** (`ShowNews`, `/cqi news`): once per version after an update (`root.lastVersion`;
  never in the "dev" copy, never on a fresh install). **Update `NEWS_TEXT` in all 6 languages for
  every release.**
- **Profile sharing** (Profiles tab, `OpenShareWindow`): "CQI1:key=bTRUE/nNUM/sTEXT;..." with
  %XX escapes; import only takes known keys of the right type into the current profile.
- **v1.2.2 (released 2026-11-09):**
  check mark when done (`doneCheck`, `HideOrComplete`: an icon that stops being needed within
  3 s of an objective finishing turns into ReadyCheck-Ready and fades; `questLog.completedAt`),
  animated count (`progressPulse`: `f.textPop` when the number goes up, gold with one left),
  ready-to-turn-in chat line (`readyAlert`), minimap tooltip summary (`minimapSummary`,
  `questLog.summary`), quick themes (Icon section, `THEMES` inside `BuildIconTab`), play button
  per row in the sound menu (`AddDropdown(..., preview)`). NEWS_TEXT already says 1.2.2.
  The arrow to the nearest quest mob goes in a separate branch later (user: test it apart).
- **UI v2 (released in v1.2.2):**
  OneForAll-inspired look (study of OneForAll v6.2.2 on 2026-11-09: flat dark warm panels, thin gold
  ring, gold text, switches, gold-filled sliders, browser-style tabs, hover on the HIGHLIGHT layer).
  - `Skin` kit (one table): `Panel`, `Window(f, bandHeight)`, `Button`, `Close`, `Switch(check)`,
    `Slider(slider, low, high, width)`, `Edges`, `Recolor`. Flat colour textures plus one smooth
    circle (`icons/ui/circle.tga`, made by `tools/make_ui.lua`) for knobs/thumbs/pill ends.
  - The options live in their **own window** (`BuildConfigWindow`, `ADDON.."Config"`, 780x680,
    movable, position in `root.windowPos`, Esc closes, open/close sounds). The Settings entry is a
    landing page (`BuildSettingsLanding`: logo, text, "Open settings"). `OpenPanel(toggle)` opens
    the window; the minimap button toggles it.
  - The whole options/guide/news section is one `do ... end` block exporting `BuildPanel`,
    `ShowWizard`, `ShowNews`; the gate conditions are one table `On` (`On.MobsOn()` ...). About 48
    main-chunk locals free after this. A block does not lower the peak inside it: only tables do.
- **Sound volume** (`soundVolume`, 0-100): below 100% `PlaySoundAt` plays on the Dialog channel and
  sets `Sound_DialogVolume` for 3 s (original kept in `root.dialogVolume`, restored at login if the
  game closed meanwhile). At 100% it plays on Master.
- **Instances: always off, not an option (since 2026-11-11, user's decision).** WoW Forever makes
  nameplates forbidden and unit/tooltip data *secret* inside instances; Questie switches its nameplate
  icons off there too (`Questie.IsForever and IsInInstance()`). `InstanceHidden()` = any instance.
  The old `hideInInstances` switch is gone; the Behavior section shows a note with an info icon whose
  tooltip (`HIDE_INSTANCES_TIP`) says it is the game's limit. `UsablePlate(unit)` never returns
  forbidden plates; plates are measured outside instances only.
- **Secret values** (`Hidden.Value`, `Hidden.Table`, `Hidden.UNKNOWN`): Forever can hide values from
  addons (`issecretvalue`); in the open world a quest object's tooltip turns secret in combat. Secrets
  can't be compared/searched/used as keys, so detection tests them first and answers `Hidden.UNKNOWN`;
  `Refresh`/`RefreshSoftObject` then leave the icon as it was.
- **Questie as a helper (2026-11-11, user: "auxiliar, não substituir"):** `questLog.FromQuestie(unit)`
  reads `QuestieTooltips.lookupByKey["m_"..npcId / "o_"..objectId]` (unfinished objectives of quests
  in our log, count from `Collected/Needed`). Asked only where the game leaves a gap: the game says
  related but the tooltip shows nothing open (after the quest-log name lookup), and the no-API /
  no-tooltip fallbacks. A "no" from the game is never overruled. Only when Questie is LOADED (the
  user has it installed but disabled on their main character). Everything pcall'd; mock covers
  disabled / loaded / game's no / broken Questie.
- **Hide while fighting it** (`hideWhileFighting`, OFF by default, user's request 2026-11-11): in
  `Refresh`, a needed mob with `UnitThreatSituation("player", unit) ~= nil` loses its icon (plain
  `HideIcon`, no check mark). `UNIT_THREAT_LIST_UPDATE` and `PLAYER_REGEN_ENABLED` (now `RefreshAll`)
  bring it back at once when it survives. Behavior section (COL1, below Ready alert) and the setup
  guide's page 4 "Combat and warnings". Side effect: a mob killed while hidden shows no check mark.
- **Level alert** (`highLevelRed`, ON by default, 2026-11-11; labels renamed by the user: "Alerta de
  nível", "Ocultar durante a luta", "Indisponível em instâncias", guide page "Extras"): a quest 2+
  levels above the player tints the icon `KIND_TINT.high[gap]`, one clearly different shade per level
  (user's spec): +2 light red, +3 red, +4 or more full red; over any other tint. Levels come from
  the quest log (`quests.levelByTitle/levelByID`, filled in `RebuildQuestTitles`); detection returns
  a 4th value `level` (`questLog.FromTitle/FromName/FromQuestie`) -> `ShowIcon(..., level)` ->
  `f.questLevel`. `PLAYER_LEVEL_UP` restyles (`ApplyLook` after 1 s). Mobs marked without a known
  quest get no level. Behavior section (COL1, under Hide while fighting) and the setup guide's new
  page 4 "Combat and warnings" (`WIZ_EXTRA_*`, both options; "What to show" is back to 5 checks).
- **Party rows:** in a group the tooltip lists each member's objectives under a `QuestPlayer` row;
  `QuestStateFromLines` skips rows whose guid isn't the player's.
- **Performance (2026-11-11):** quest-log events are batched (`later.questLog`, 0.1 s, one rebuild
  per burst; `UNIT_QUEST_LOG_CHANGED` registered for "player" only), the quest-item check is one per
  frame (`QueueSoft`), sliders call `ApplyLook` (look only) instead of `ApplySettings`, `CVAR_UPDATE`
  ignores our own writes and stops after 20 re-applies in 10 s (`cvarGuard`), the bobber skips
  hidden/completing icons and doesn't re-anchor the label, the 1 s recheck idles when the addon is off,
  pooled icons `ClearAllPoints`. The main chunk is AT the 200-locals limit again: new main-chunk
  helpers must go into existing tables (`questLog.FromName`, `cvarGuard.gateOpened`, `Hidden`) or
  `do ... end` blocks.
- **Bug reports (v1.2.3, released 2026-11-10):** `/cqi debug` (`ShowDebug`: versions, client, language, main switches,
  instance, plate cvars, other quest/nameplate addons, last errors) and a "Report a bug" button
  (issues URL), both in the copy window (`OpenShareWindow("copy", title, hint, text)`). Errors that
  mention the addon are kept in `root.lastErrors` (last 10) by a wrapper around the current error
  handler, which still receives every error.
- **Two quests, one mob (v1.2.3 fix, user's tester plays with many quests):** when
  `UnitIsRelatedToActiveQuest` says yes but the tooltip lists only finished quests, the mob is
  marked anyway: with the count of an open objective that names it, or with no count. TO VERIFY in
  game: a mob whose only quest is done (ready to turn in) must lose its icon; if it keeps it, the
  API also counts finished quests and this fallback needs a stricter test.
- **Badge experiment** (2026-11-09): built, tried in game, user found it ugly and dropped it; the
  commits were reverted. Do not bring it back unless asked (maybe with real artwork).
- `/cqi` opens the options, `/cqi toggle` toggles the addon, `/cqi setup` the guide, `/cqi news` what's new, `/cqi plate` measures the target plate.

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
- **Every release, before tagging:** add the version's section at the top of `CHANGELOG.md` (the
  packager uploads it as the file's changelog, `.pkgmeta` manual-changelog) and update `NEWS_TEXT`
  in all 6 languages. The workflow's `check` job (syntax, both mock runs, `tools/check_translations.lua`)
  must pass or nothing is uploaded; it can be run by hand with
  `gh workflow run "Package and release" --ref <branch>` (the release job only runs on tags).
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
- 1.2.0 (2026-11-09): progress text with fonts/formats, sound, one scrolling settings page, preview
  window, 37 icons in 3 categories (icon picker), two-column layout.
- 1.2.1 (2026-11-09): setup guide, icon anchor, items' own look and count, re-cut icons, new sound
  list (picked by ear), hover help, what's new window, profile export/import, welcome line,
  restricted-plate fixes. Version numbers: third digit only for now.
- 1.2.2 (2026-11-09): own options window in a OneForAll-like look (Settings keeps a landing page),
  check mark when done, animated count, ready alert, minimap summary, quick themes, sound preview
  and volume, hide in instanced content (default on), forbidden-plate safety.
- 1.2.3 (2026-11-10): two quests on one mob keep the mark, /cqi debug + Report a bug, error
  capture, name lookups cached per quest log scan, CHANGELOG.md for CurseForge, release check job.
- 1.2.4 (2026-11-11, first release from the second notebook): level alert (red shades), hide during
  the fight, Questie as a helper, instances always off (game's limit, info note), Extras guide page,
  party-objective and secret-value fixes, event batching and other performance work.
- 1.2.5 (2026-11-11): Gameplay tab: quest pickup (auto / button on lists, single quest at once),
  auto turn-in (rewards to choose left alone), Shift = manual, never interferes with other addons.

## Quest pickup / Gameplay tab (released in v1.2.5; turn-in confirmed in game, button position not yet)
- Third tab **Gameplay** (Settings | Gameplay | Profiles; built inline in the `builders` list —
  a named local there would cross the 200-locals limit). Settings: `questPickup` (off),
  `questPickupMode` "auto" | "button", `questPickupRepeatable` (on). Also on the setup guide's
  Extras page (switch + mode). Labels proposed by me, user said "depois ajustamos": Coleta de quests,
  Modo (Automático ao falar / Botão na janela), Incluir diárias e repetíveis, button "Pegar todas".
- Logic: own `do` block before the events section (own event frame). GOSSIP_SHOW / QUEST_GREETING
  open the next wanted quest (`C_GossipInfo.SelectAvailableQuest` / `SelectAvailableQuest(i)`),
  QUEST_DETAIL `AcceptQuest()`, the game reopens the window -> next. `tried` (10 s) stops loops on a
  full log. Auto: Shift at the start of the talk = manual until the windows close (`paused`).
  Button mode (user's spec 2026-11-11): a LIST gets the "Pegar todas" button; an NPC with a SINGLE
  quest (QUEST_DETAIL with no list seen, `sawList`) is accepted at once; a quest the player picks
  from a list is theirs. Shift = all manual; said in a visible line on the tab (`PICKUP_HOW`).
  The button is a child of the NPC window and isn't gated on `IsShown()` (the window can open a
  moment after GOSSIP_SHOW; that was why it didn't show in game the first time).
  Button: `UIPanelButtonTemplate` at the TOPRIGHT of GossipFrame/QuestFrame (-32, -30) — position
  NOT checked in game yet. Only NPC/object GUIDs (no player shares, no item quests).
- **Auto turn-in** (`questTurnIn`, off, separate switch, Gameplay tab only — not in the guide):
  finished quests first (`C_GossipInfo.GetActiveQuests` isComplete / `GetActiveTitle`),
  QUEST_PROGRESS `CompleteQuest()` when `IsQuestCompletable()`, QUEST_COMPLETE `GetQuestReward(n)`
  only with 0 or 1 reward; **2+ choices = do nothing** (user's rule). Questie itself doesn't pick a
  "recommended" reward either (it skips when choices > 1), so there was nothing to learn there.
- **Never interfere with other addons** (user's rule): `questLog.OtherPickupAddon(kind)` checks
  Questie (`autoAccept.enabled` / `autocomplete`), Leatrix Plus (`LeaPlusDB.AutomateQuests == "On"`),
  QuickQuest and AutoTurnIn (loaded = active), Zygor (setting names guessed). Only LOADED addons
  count. When one does it, ours does nothing and the Gameplay tab shows an orange note.
- Reference used: Questie's `Modules/Auto/AutoQuesting.lua` (works on this client).

## Ideas the user liked, not done yet
- **From the Questie comparison (2026-11-11), not built yet:** icon by objective type (kill / loot /
  interact, from `C_QuestLog.GetQuestObjectives` `type`), skip non-Creature GUIDs before the tooltip.
  Also left for later: build the options window on first open instead of at load (`BuildPanel`).
- **Ideas noted 2026-11-10 (user: "anota mas não execute"):** special glow when a quest has one
  objective left; ~~reddish warning for quests well above your level~~ (DONE 2026-11-11); ~~hide a mob's icon while you
  fight it~~ (DONE 2026-11-11); ground glow around quest items; search
  box in the options; preview scenarios (daily, group, almost done, combat); undo the last change;
  all counts on a mob shared by several quests ("2/8 · 1/5"); translation help link on CurseForge.
- **Ideas reviewed with the user on 2026-11-09 (after v1.2.2):**
  - Next candidate (user: "interessante"): **quest item button**: when you target the mob a quest
    item must be used on, a small button with that item appears (secure action button: combat rules).
  - Future: arrow to the nearest quest mob (own branch, test apart), custom icon colour +
    transparency, show only on target/mouseover, party members' quest mobs (needs the addon on
    their side), colour-blind palette, session stats (`/cqi stats`, "useless but fun"), limit the
    number of icons in crowded areas.
  - CurseForge page (GIF, screenshots of the new window, better description): still to do.
- ~~Separate look for mobs vs items~~ DONE in v1.2.1 (`objectOwnLook`).
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
  3. Separate look for mobs vs items — DONE v1.2.1.
  4. Custom icon color + transparency.
  5. Sound when an objective completes — DONE (sound list picked by ear in v1.2.1).
  6. Small extras, LAST: hide in dungeons/raids, only on target/mouseover. Keybinding: user said NO (2026-11-09).
  - Objective tracker with badges: later, it overlaps Questie.
  - CurseForge page: GIF of the icons, screenshots of the panel/styles, better title/summary/description.
- **Other WoW clients** (Classic Era/Anniversary, Cata/MoP Classic, Retail): user decided 2026-11-09
  to wait until the addon is more mature. Don't push it before then.
