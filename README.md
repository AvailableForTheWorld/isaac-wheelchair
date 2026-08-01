# Wheelchair Timeline

Wheelchair is now an in-game, linear safety timeline for The Binding of Isaac: Repentance+.

There is no companion window, global hotkey, controller panel, process-closing automation, save-file overwrite, relaunch, node tree, or branching logic.

## Controls

- **F5** on the keyboard: move backward one cached state.
- **RT** on the controller: move backward one cached state.

The mod records a small player-focused state approximately once per second and keeps at most 100 states. Rewinding repeatedly within three seconds continues farther backward. After normal play resumes, newer history is discarded and the linear timeline continues from the restored state.

The cache is held only in memory. It resets on a new run, game restart, or floor change and never writes Isaac's Steam save files.

## What a cached state contains

- Current-floor room index.
- Player position and velocity reset.
- Red-heart containers, red hearts, soul/black-heart quantity, bone-heart containers, eternal hearts, and golden hearts.
- Coins, keys, bombs, and the primary active-item charge.

For the immediately previous room, Wheelchair uses Isaac's built-in Glowing Hourglass-style rewind so the room is restored by the engine. For older points on the same floor, the standard API can safely return to the cached room and restore the player-focused values above, but it cannot perfectly serialize every enemy, pickup, grid change, mod entity, item-pool decision, or hidden engine value. Cross-floor deep rewind is intentionally refused for stability.

## Installation

Run `Install-Mod.ps1`, then enable **Wheelchair 100-State Timeline** in Isaac's Mods menu. The updated mod has already been installed on the development machine.

The old external checkpoint files under the ignored local `data` directory are preserved as recovery backups, but no current Wheelchair code reads or writes them.
