# Sharingan / 写轮眼

![Sharingan floor-map cover](assets/workshop-cover.png)

Sharingan is now a focused, read-only floor-map overlay for The Binding of Isaac: Repentance+. It displays the complete generated floor and identifies special rooms without tracking combat, pickups, items, DPS, machines, or player damage.

## Interface and controls

- The in-run interface intentionally uses English. Isaac's public Lua font loader did not render Chinese glyphs reliably, so the mod uses readable English instead of broken labels.
- Press the configured shortcut to open or close the floor map.
- Defaults: **F6** on keyboard and **Left Stick click** on controller.
- Open **Mod Config Menu → Sharingan → Controls** to change either shortcut.
- The map does not pause or filter normal gameplay input.

There is no Combat page and no Left/Right page navigation.

## Complete, shape-aware floor map

Opening the overlay draws every room descriptor generated for the current floor, including rooms that the player has not visited. The renderer uses each descriptor's real `RoomShape`: vertical 1×2 rooms occupy two cells, horizontal 2×1 rooms occupy two cells, 2×2 rooms occupy four cells, and each L-room leaves the correct corner empty. A large or L-shaped room has one connected outer border. A special-room digit or map-only Boss marker appears only once inside that border.

The legend is ranked from most generally practical to least:

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

Boss Rooms are marked directly on the map with a black `B` and are omitted from the numbered legend. Unvisited special rooms use saturated colors. A marker turns neutral gray only after Sharingan observes the player physically entering that room. An outlined cell is another generated room, `@` is the current non-special room, and `.` is an empty grid cell. Off-grid rooms such as Crawl Spaces and Black Markets are not assigned false 13×13 map positions.

## Performance and persistence

Sharingan registers no combat, damage, kill, pickup, item-use, pedestal, or gameplay-input callbacks. Its per-frame update only checks the configurable overlay shortcut. Room entry only records the current room ID and refreshes the small generated-floor descriptor list when its size changes.

Save schema 3 retains only the overlay preference and floor-map visit state. Loading this version migrates an older save and permanently drops all legacy combat and statistical history on the next save. Sharingan does not read or modify Steam userdata or Isaac's persistent game-save files.

## Local installation

Close Isaac, then run this command from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1 -Mod sharingan
```

Do not enable a local copy and the Workshop-suffixed copy simultaneously.

## Workshop publishing

The Workshop item ID is stored in `content/metadata.xml` and the `sharingan` entry in the repository's `mods.json`. Subsequent updates use the shared GitHub Actions workflow.
