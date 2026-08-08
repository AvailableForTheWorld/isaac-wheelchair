# Sharingan / 写轮眼

![A Sharingan containing Isaac's floor map and surrounded by damage items](assets/workshop-cover.png)

Sharingan is an all-seeing, read-only floor-intelligence and combat-analysis overlay for The Binding of Isaac: Repentance+. It reveals the generated floor layout, identifies special rooms, and records non-overlapping item-damage contributions without spawning pickups, changing rooms, modifying player stats, or editing Isaac's save files.

## Interface

- The in-run interface intentionally uses English. Isaac's public Lua font loader did not render Chinese glyphs reliably, so the mod uses readable English instead of broken or missing labels.
- The generated-floor map is the first page. The compact **Combat Report** is right-aligned and vertically centered. The Rooms, Loot, Items, and Machines pages have been removed.
- Statistics use separate rows without cramped `|` separators.

## Controls

- **Configured overlay shortcut:** show or hide Sharingan. The default is **F6** on keyboard and **Left Stick click** on controller.
- **Left:** switch to the generated-floor map while the overlay is open.
- **Right:** switch to the Combat Report while the overlay is open.

Keyboard users can use the left/right arrow keys. Controller users can use D-pad Left/Right. Open **Mod Config Menu → Sharingan → Controls** to change either overlay shortcut. The navigation directions are fixed so they remain discoverable and consistent.

The floor-map overlay blocks normal gameplay input while it is open, but it does not pause combat.

## Combat Report

The report shows:

- Raw loadout DPS, player damage, and tears per second.
- Floor and run damage dealt.
- Unique enemies damaged and damaged enemies killed.
- Floor and run hit counts plus total hearts of damage received.
- The five items with the highest attributed damage in the current run, sorted by damage from highest to lowest.
- The five damage sources that hit the player most often on the current floor, sorted by hit count from highest to lowest. Equal counts are ordered by damage amount and then name.

Item damage is conserved: every recorded enemy-damage amount is split once and the shares add back to the original hit. Direct weapon replacements such as Mom's Knife, Brimstone, Tech X, Ipecac, Technology, Dr. Fetus, and similar weapon types receive the direct remainder. Damage-dealing familiars and active-item effects are attributed when Isaac exposes their source relationship. A passive stat-up item receives only its observed positive raw-DPS delta share; that share is subtracted before the direct weapon receives the remainder, so the same damage is never counted for both items. Unidentified vanilla tears remain `Base attack` and are intentionally excluded from the item top five.

Isaac's Lua API does not expose the originating collectible for every proc or synergy. Consequently, source-specific attribution is exact where the entity/weapon relationship is exposed and otherwise uses the measured DPS-delta split described above; it does not guess an item for an opaque effect.

Damage from projectiles, lasers, bombs, and effects is followed through its spawner/parent chain so that it is attributed to the hostile enemy when the API exposes that relationship. Enemy rows include the entity's numeric `type.variant[.subtype]` identity, and the hit count is shown at the end, for example:

```text
1. Horf [12.0]   x4
2. Pooter [14.0] x2
3. Spikes         x1
```

Environmental damage is labelled separately when Isaac supplies the appropriate damage flag, including Spikes, Cursed Door, Spiked Chest, Red Poop, Fire, Acid/Creep, Explosion, Laser, and Devil Deal. A source that Isaac does not expose is shown as `Unknown source` rather than guessed.

Raw DPS is estimated as `Damage × 30 / (MaxFireDelay + 1)`. It does not model multishot, poison, familiars, lasers, knives, explosions, conditional effects, enemy armor, accuracy, or complex synergies.

## Rewind behavior

When **Wheelchair Emergency Rewind** triggers Isaac's native rewind, Sharingan restores all combat counters, item-damage attribution, and the damage-source ranking to the values captured when the current room was entered. Damage, kills, player hits, received-heart totals, item shares, and attacker counts from the discarded room attempt are removed.

The room-entry snapshot is restored in memory without re-copying its tables. Sharingan also defers its periodic JSON save and limits inventory reconciliation during the rewind transition, avoiding a full-run serialization and full collectible scan on the critical transition frame.

This integration applies to rewinds triggered through Wheelchair. Manually running Isaac's console command bypasses Wheelchair's pre-rewind notification.

## Complete, shape-aware floor map

Opening the overlay, or switching Left, draws every room descriptor generated for the current floor, including rooms that the player has not visited. The map is read-only; mouse marking and numeric marker selection have been removed. The renderer uses each descriptor's real `RoomShape`: vertical 1×2 rooms occupy two cells, horizontal 2×1 rooms occupy two cells, 2×2 rooms occupy four cells, and each L-room leaves the correct corner empty. A large or L-shaped room has one connected outer border rather than several separate `[]` cells. A special-room digit or map-only Boss marker appears only once inside that border. The legend is ranked from most generally practical to least:

1. Secret Room
2. Super Secret Room
3. Treasure Room
4. Shop
5. Devil Room
6. Angel Room
7. Planetarium
8. Ultra Secret Room
9. Sacrifice Room
10. Curse Room
11. Challenge Room
12. Dice Room
13. Library
14. Vault
15. Arcade
16. Boss Rush
17. Black Market
18. Crawl Space
19. Clean Bedroom
20. Dirty Bedroom

Boss Rooms are marked directly on the map with a black `B`; they are intentionally omitted from the numbered right-side legend. Each unvisited special-room type has a saturated color. As soon as that room is visited, its map outline and digit or marker turn neutral gray. An outlined cell is another generated room, `@` is the current non-special room, and `.` is an empty grid cell. Generated special-room numbers are refreshed from the floor data. Crawl Spaces, Black Markets, and other rooms represented by Isaac with negative off-grid indices have no physical 13×13 map cell, so the mod does not assign them a false position.

## Persistence

The mod stores its current run, floor map, combat totals, and damage-source counts through Isaac's normal mod `SaveData` API. It does not read or modify Steam userdata or the game's persistent save files.

## Local installation

If you tested the earlier **Beginner Ledger** build, remove or disable its installed `mods\beginner-ledger` directory first. The installer deliberately does not delete renamed mods automatically, and enabling both copies would load the overlay twice.

Close Isaac, then run these commands from the repository root so both sides of the rewind integration are current:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1 -Mod wheelchair
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1 -Mod sharingan
```

Enable **Wheelchair Emergency Rewind** and **Sharingan / 写轮眼** in Isaac's Mods menu.

## Workshop publishing

This package is registered as local-only until its first Workshop upload. Perform the initial upload with Isaac's bundled `ModUploader.exe`, then put the generated Workshop ID in both `content/metadata.xml` and the `sharingan` entry in the repository's `mods.json`. Subsequent updates can use the shared GitHub Actions workflow.
