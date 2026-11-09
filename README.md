<p align="center"><img src="media/logo.png" width="200" alt="CS.Coder - Quest Indicator"></p>

# CS.Coder - Quest Indicator

A floating, animated **"!"** over the mobs and items you still need for your quests. No more hovering every mob to find out which one drops your quest item.

## Features

- **Quest mobs:** a "!" floats above the nameplate of every mob you still need for an active quest. It disappears once the objective is done.
- **Quest items:** herbs, crates, sprouts and other quest items on the ground get a "!" too, on the nearest one in front of you.
- **5 icon styles:** Gold, Blue, Red, Badge and Pixel.

  ![Icon styles](media/icon_styles.png)
- **Color by quest type:** daily and repeatable quests in blue, group and elite quests in red.
- **Float and glow:** adjustable float height and duration, optional glow with adjustable intensity.
- **Size and position:** separate size and height for mobs and items, plus horizontal offset for mobs.
- **In combat:** keep, fade or hide the icons.
- **Live preview** in the options, next to every setting.
- **Profiles:** create, copy, rename and delete; each character remembers its profile.
- **Minimap button:** left-click opens the options, right-click turns the addon on or off, drag to move.
- **Languages:** English, Português (Brasil), Español, Deutsch, Français, Italiano. Other game languages use English.

## How to use

1. Turn on enemy nameplates (default key **V**).
2. Open the options at **Options > AddOns > CS.Coder > Quest Indicator**, click the minimap button, or type **/cqi**.

| Command | What it does |
|---|---|
| `/cqi` | Opens the options |
| `/cqi toggle` | Turns the addon on or off |

## Notes

- Quest items use the game's interact soft target, so only one item (the nearest in front of you) shows the icon at a time.
- Game settings can't be changed in combat, so a quest item you face mid-fight may only show its icon after combat.
- Works alongside ForeverLootSparkles.

## Install

Copy the `CSCoder_QuestIndicator` folder into `World of Warcraft\<version>\Interface\AddOns\`, or install it from CurseForge.

## Releasing (maintainers)

Push a version tag (for example `v1.1.0`). The GitHub Action packages the addon and uploads it to CurseForge (WoW Forever) and GitHub Releases. Plain commits publish nothing.

## License

MIT, see [LICENSE](LICENSE).
