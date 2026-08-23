# Eden Mode

Eden Mode gives every playable character an Eden-style start while preserving the character they were designed to be. It targets **The Binding of Isaac: Repentance+**.

## What changes

Each player receives a deterministic profile on a new run:

- **Exactly 0, 1, 2, or 3 passive/familiar collectibles**, independently rolled in either active-item mode and selected from the Treasure (65%), Boss (20%), Shop (10%), and Library (5%) pools. The game's item pool still enforces unlocks and character/run restrictions.
- **Random starting health:** ordinary characters receive one of four equally likely profiles: red hearts, soul hearts only, black hearts only, or mixed red plus soul/black hearts. Red-heart containers and their filled-heart count are rolled separately.
- **Damage:** 0.80x-1.20x.
- **Tears/fire rate:** 0.85x-1.15x.
- **Shot speed:** 0.90x-1.10x.
- **Range:** 0.85x-1.15x.
- **Movement speed:** 0.90x-1.10x.
- **Luck:** -1.00 to +1.00.

The same run seed and player slot produce the same profile. Stat modifiers are applied after vanilla items and effects, so later pickups continue to work naturally.

The six stat rolls and starting health are combined into a weighted power score from -1 (weak) to +1 (strong). Stats contribute 85% of the score, with damage and tears contributing the most; health contributes 15%. Item quality is inversely compensated:

- Progressively weaker profiles move the target toward Quality 4.
- Balanced profiles generally target Quality 2-3.
- Progressively stronger profiles move the target toward Quality 0-1.

Each item receives a small quality jitter, and the nearest pool-valid quality is used when the exact target is unavailable. This keeps the result random while preventing high stats and top-tier items from being the normal combination.

## What stays original

Eden Mode does not change the selected character, innate effects, pocket actives, consumables, or original passive starting items. By default, it replaces only the primary starting active as described below.

Health rolls remain within these limits:

- Red-only: 1-4 containers with a separately rolled 1-to-maximum filled-heart count.
- Soul-only or black-only: 1-4 full hearts.
- Mixed: 1-3 red containers plus 1-3 soul/black hearts; the spirit portion may be soul, black, or both.

Characters that cannot hold red containers, including Blue Baby, Dark/Tainted Judas, Tainted Blue Baby, and Tainted Bethany, roll soul-only, black-only, or soul-and-black profiles instead. Bethany rolls red health only because soul/black pickups are her active-item charges. Lost, Keeper, Forgotten/Soul, their tainted variants, Tainted Jacob's ghost form, and unknown modded character health systems remain unchanged so their core mechanics are not broken.

The passive/familiar count is always rolled independently from 0 through 3. In the default mode, each profile also receives one random active replacement. In Preserve mode, the character keeps its original active and instead has a 40% bonus-active chance that can use only an empty primary or Schoolbag slot.

## Mod Config Menu

With Mod Config Menu - Impure enabled, open **Eden Mode → Starting items**:

Select the **Starting active** row and press **Left / Right** to switch between its two clearly labeled values:

- **Random active (default)** grants one random active in addition to the independently rolled 0-3 passive/familiar items. It removes the existing primary starting active only after a different valid random active has been selected, then equips the replacement in the primary slot.
- **Original active** keeps the character's primary starting active and still grants 0-3 passive/familiar items. The 40% bonus-active roll can use only an empty primary or Schoolbag slot.

The submenu repeats these controls and explains both choices directly below the selector.

Starting health is always randomized automatically for compatible characters; it is independent from the active-item selector. The submenu also calls out the fixed-health character exceptions.

Pocket actives are never replaced. If the primary active cannot be safely removed, Eden Mode preserves it and omits the replacement; it never converts a failed active roll into a fourth passive. The setting is captured when a player profile is created; changing it during a run affects only future profiles or a completely new run.

Co-op players receive independent profiles. Tainted Lazarus's living and dead inventories receive separate profiles when each form first becomes active. Other transformations and temporary forms retain their existing player-slot profile and cannot be used to farm more starting items.

Profiles and their health/item initialization markers are saved immediately. Continuing a run restores the profile without changing health or duplicating items.

## Installation

Close Isaac, then run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1 -Mod eden-mode
```

Enable **Eden Mode** in Isaac's Mods menu. Do not enable both a local copy and a future Workshop-suffixed copy at the same time.

## Suggested in-game checks

1. Start several new runs in both modes and verify the passive/familiar count varies from 0 through 3, never 4. In default Random Active mode, the total bonus count is one active plus those 0-3 passives.
2. Start ordinary red-heart characters repeatedly and verify red-only, soul-only, black-only, and mixed starts appear. Check that red containers and filled red hearts also vary.
3. Check `log.txt` entries beginning with `[Eden Mode]`: negative power scores should trend toward higher displayed `Q` values, while positive scores trend lower. The log lists the health profile and its stat/health score components.
4. In MCM's default **Replace** mode, use characters with native actives (Isaac, Magdalene, Judas, Bethany) and verify the primary active becomes a different random active while pocket actives remain.
5. Select **Original active**, start a new run with those characters, and verify their original primary actives remain equipped while their passive/familiar count still varies from 0 through 3.
6. Start as The Lost, Keeper, Forgotten, and their tainted variants and verify their original health and innate mechanics remain intact.
7. Exit and Continue a run; confirm the same health, stats, and active return without duplicated items or health changes.
8. Add a co-op player and flip Tainted Lazarus; confirm each newly active inventory receives one profile.

## Workshop publishing

This mod is local-only until its first upload establishes a Workshop ID. Perform that first upload with Isaac's `ModUploader.exe`, then place the generated ID in both `content/metadata.xml` and the `eden-mode` entry in `mods.json`. Later releases can use the shared GitHub Actions workflow.
