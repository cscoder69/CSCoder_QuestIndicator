# CS.Coder - Quest Indicator

## v1.2.5

- New **Gameplay** tab in the options.
- **Quest pickup** (off by default): accepts the quests NPCs offer. Two modes:
  - **Automatic on talk**: talking to an NPC accepts all its quests.
  - **Button on the window**: an NPC with a list of quests gets an **Accept all** button; an NPC with a single quest is accepted at once.
  - Dailies and repeatables can be included or left out.
- **Auto turn-in** (off by default, separate switch): hands in finished quests. When you must choose a reward, nothing is done — you pick it.
- Hold **Shift** when you click an NPC to do everything by hand that time.
- Only NPCs: quests shared by players or started from items are never accepted by themselves.
- Never gets in the way of another addon that already does this (Questie's auto-accept / auto-complete, Leatrix Plus, QuickQuest, AutoTurnIn): the Gameplay tab tells you when one is active.
- Quest pickup is also on the setup guide's Extras page.

## v1.2.4

- **Level alert** (on by default): the icon turns red for quests above your level — light red at 2 levels above, red at 3, full red at 4 or more.
- **Hide during the fight** (off by default): a mob that is fighting you loses its icon; it comes back if the mob survives.
- **Questie as a helper**: when Questie is active, its data fills in the count for quest drops the game doesn't show. Without Questie (or with it disabled) nothing changes, and the game's own answer always comes first.
- Icons are now **always off in dungeons, raids and other instances**: WoW Forever locks nameplates and quest information there for every addon (Questie does the same). The options explain it next to an info icon.
- New setup guide page, **Extras**, with the two new options.
- **Fix:** in a group, a party member's unfinished objectives no longer mark mobs for you.
- **Fix:** no more errors when the game hides quest data from addons (for example a quest item's tooltip during combat); the icon simply stays as it was.
- **Lighter**: quest log updates are handled once per burst, nameplate changes are batched, sliders only redraw the look, and nothing runs while the addon is switched off.

## v1.2.3

- **Fix:** a mob needed by two quests kept no icon once one quest was done (for example 3/3 done, the other still at 2/8). It is marked again, with the count of the quest that still needs it when that quest names the mob.
- **Report a bug** button in the options window, with the link to the issues page.
- **/cqi debug**: a short report to copy (versions, client, language, main settings, place, other nameplate and quest addons, the addon's last errors), ready to paste in a bug report.
- Lighter with a full quest log and crowded areas (mob names are looked up once per quest log change).
- Every release is now checked automatically before it is published.

## v1.2.2

- **A new look**: the options open in their own window, with switches, gold buttons and sliders. The game's AddOns options keep a short page with an "Open settings" button.
- A green **check mark** when a mob is no longer needed.
- The **count pulses** when it goes up and turns gold when one is left.
- A chat line when a quest is **ready to turn in**.
- **Quest summary** on the minimap button.
- **Quick themes**: Classic, Subtle and Flashy.
- A play button next to each sound, and a **volume** slider.
- Icons **hide in instanced content** (dungeons and raids) by default.
- Safer with the nameplates dungeons hand out.

## v1.2.1

- A **setup guide** for new characters (`/cqi setup`).
- **Icon anchor**: top, bottom, left or right of the nameplate.
- Quest items can have their **own icon, float and glow**, and show the **count** too.
- Sharper, centred icons; new sounds; profile **export and import**; help on hover; what's new window.

## v1.2.0

- Progress text with fonts, formats, outline, colour and shadow; sound when an objective completes.
- 37 icons in 3 categories, picked from an icon window; one scrolling settings page; preview window.

## v1.1.0

- Profiles, 6 languages, colour by quest type, combat fade/hide, minimap button, smooth float.

## v1.0.0

- First release: quest mob icons, quest item icon, options panel.
