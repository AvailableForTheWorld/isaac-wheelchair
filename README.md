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
- Rotten hearts, broken hearts, and the exact soul/black-heart pattern.
- Coins, keys, bombs, giga bombs, golden keys, and golden bombs.
- Passive collectibles, both held trinkets, cards/pills, active-item identities, and charges.
- Bethany soul/blood charges and Tainted ??? poop mana.

Player combat values are applied once after the target room loads and verified for two more update frames. This prevents later room-entry processing from restoring the health or resources from the room where RT was pressed.

Wheelchair deliberately does not call Isaac's built-in Glowing Hourglass-style `rewind`. That engine feature owns only one backup and loading it can also roll a mod's Lua state backward, which previously destroyed or desynchronized the remaining timeline after the first step.

Every step now uses the mod-owned 100-room stack and the standard same-floor `Game:ChangeRoom` API, then restores the cached player-focused values. This makes repeated room-by-room steps reliable. Passive items are restored through Isaac's supported add/remove APIs without replaying pickup rewards. The engine still does not expose a complete serializable room snapshot, so Wheelchair cannot perfectly restore every enemy AI frame, pickup, grid change, mod entity, item-pool decision, or hidden RNG value. Cross-floor rewind remains intentionally disabled for stability.

`ChangeRoom` completes asynchronously in Repentance+. Wheelchair waits up to six seconds for the requested room and restores the cached values immediately after the new-room callback confirms the transition; it does not reject a valid transition after an arbitrary short delay.

Rooms are identified by `RoomDescriptor.SafeGridIndex`, unique `ListIndex`, and dimension. `GetCurrentRoomIndex()` is intentionally not used because it can refer to a different quadrant of a large room. Saving the dimension also prevents an index from resolving to the mirror, Mines escape, or Death Certificate dimension.

The last frame in a departing room is normally inside a doorway trigger. When Wheelchair restores that room, it clamps Isaac's saved position 80 units inside the walls and selects a nearby free position. This prevents the same door from immediately returning Isaac to the room he just rewound from.

Before changing rooms, Wheelchair clears `Level.LeaveDoor`. Isaac otherwise uses a stale door slot to calculate a destination relative to the current room and can ignore the requested room index. The stored grid address is also checked against the room's unique `ListIndex`; a mismatch is refused instead of opening an unrelated or hidden room.

The files named `rep+gamestate1.dat`, `rep+gamestate2.dat`, and `rep+gamestate3.dat` belong to Isaac's three selectable save slots. They are not three historical states. Wheelchair's current in-memory timeline works the same on slot 1, 2, or 3 and never reads or writes these files.

## Installation

Run `Install-Mod.ps1`, then enable **Wheelchair 100-State Timeline** in Isaac's Mods menu. The updated mod has already been installed on the development machine.

The old external checkpoint files under the ignored local `data` directory are preserved as recovery backups, but no current Wheelchair code reads or writes them.
