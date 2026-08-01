# Wheelchair Timeline

Wheelchair is now an in-game, linear safety timeline for The Binding of Isaac: Repentance+.

There is no companion window, global hotkey, controller panel, process-closing automation, save-file overwrite, relaunch, node tree, or branching logic.

## Controls

- **F5** on the keyboard: return to the previous cached room.
- **RT** on the controller: return to the previous cached room.

The mod records exactly one timeline entry per room transition and keeps at most 100 rooms. Player movement inside a room only refreshes a temporary working snapshot; it never creates another step. When Isaac enters the next room, Wheelchair commits the previous room's final state—the state immediately before entering the new room.

Each F5/RT press pops one room from the linear timeline. Repeated presses therefore go room-by-room into the past. After normal play resumes and another room is entered, the timeline continues from that restored route; there are no branches.

The cache is held only in memory. It resets on a new run, game restart, or floor change and never writes Isaac's Steam save files.

## What a cached state contains

- Current-floor room index.
- Player position and velocity reset.
- Red-heart containers, red hearts, soul/black-heart quantity, bone-heart containers, eternal hearts, and golden hearts.
- Coins, keys, bombs, and the primary active-item charge.

Wheelchair deliberately does not call Isaac's built-in Glowing Hourglass-style `rewind`. That engine feature owns only one backup and loading it can also roll a mod's Lua state backward, which previously destroyed or desynchronized the remaining timeline after the first step.

Every step now uses the mod-owned 100-room stack and the standard same-floor `Game:ChangeRoom` API, then restores the cached player-focused values. This makes repeated room-by-room steps reliable, but it cannot perfectly serialize every enemy, pickup, grid change, mod entity, item-pool decision, or hidden engine value. Cross-floor rewind remains intentionally disabled for stability.

## Installation

Run `Install-Mod.ps1`, then enable **Wheelchair 100-State Timeline** in Isaac's Mods menu. The updated mod has already been installed on the development machine.

The old external checkpoint files under the ignored local `data` directory are preserved as recovery backups, but no current Wheelchair code reads or writes them.
