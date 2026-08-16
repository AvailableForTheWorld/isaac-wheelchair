# Opening Presets

![Opening Presets Workshop cover](assets/workshop-cover.png)

Opening Presets displays one centered custom-loadout screen at the beginning of each new run in The Binding of Isaac: Repentance+. It does not reopen automatically when continuing a saved run, so items cannot be granted twice accidentally.

## One-screen layout

The bordered chooser is exactly 60% of Isaac's logical HUD width. The complete border is centered, leaving the game's side information panels visible. Items use three columns and are grouped by their real `ItemConfig.Quality` in descending order: **Quality 4, 3, 2, 1, and 0**.

Only one quality and one 15-item page are displayed at a time, preventing overflow. Each cell puts the item ID and selection state on the first line and its localized item name on a separate second line. Within each quality, transformative and broadly powerful items are manually prioritized; remaining items are alphabetical.

When External Item Descriptions is active in Chinese, the chooser reads Chinese item names from EID's `zh_cn` collectible table and renders the interface with EID's Unicode-capable font at its native 1:1 pixel size. Fractional scaling and duplicate shadow passes are deliberately avoided to keep Chinese strokes crisp. English names and the normal Isaac font remain the fallback for other languages or when EID is unavailable.

## Controls

- **Up / Down:** move between Quality, Current page, item rows, and actions.
- **Left / Right:** change the focused quality, current page, item column, or action.
- **Enter / controller A:** add one configured copy of the focused item, up to 99.
- **Backspace / controller Y:** subtract one configured copy of the focused item.
- **Escape / controller menu back:** close without applying.
- **Configured panel shortcut:** reopen during a run, including a continued run.

The footer automatically changes between keyboard help and controller help after the user presses either input type.
It is rendered below the bottom border so it cannot cover the framed controls.

## Mod Config Menu

With Mod Config Menu - Impure enabled, open **Opening Presets → Controls** to configure the panel shortcut independently for keyboard and controller. Defaults are **F7** for keyboard and **Back/View** for controller. Opening Presets ignores both shortcuts while MCM itself is visible, preventing shortcut capture from opening this panel.

The chooser does not pause the game or disable movement. It briefly ignores startup menu input so the button used to confirm a character cannot activate an item immediately.

## Universal counts and live removal

There is one universal loadout for every character. Each row displays its configured quantity as `[x0]`, `[x1]`, `[x2]`, and so on. Applying `[x2] Mom's Knife`, for example, grants two copies to every active player. Reapplying the same configuration during that run does not duplicate copies that the mod already granted.

**Clear + remove** does two things: it resets every configured count and immediately removes the copies that Opening Presets granted to every active player. It deliberately preserves items that the character started with or acquired through normal gameplay. Granted-copy tracking is stored with the run seed, so removal continues to work after leaving and continuing the run.

Active collectibles still follow Isaac's normal active-slot behavior when several copies or different active items are granted.
Active items granted by Opening Presets begin at their configured maximum charge, matching a normal in-game pickup. Active items that naturally require no charge remain unchanged.

## Installation

Close Isaac, then run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1 -Mod opening-presets
```

Enable **Opening Presets** in Isaac's Mods menu. Do not enable both a local copy and a future Workshop-suffixed copy at the same time.

## Workshop publishing

This mod is local-only until its first upload establishes a Workshop ID. Perform that first upload with Isaac's `ModUploader.exe`, then place the resulting ID in both `content/metadata.xml` and the `opening-presets` entry in `mods.json`. Later releases can use the shared GitHub Actions workflow.
