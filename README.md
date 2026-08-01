# Wheelchair Emergency Rewind

Wheelchair is a minimal in-game emergency rewind for The Binding of Isaac: Repentance+.

## Controls

- **F5** on the keyboard.
- **RT** on a controller.

Either input invokes Isaac's built-in `rewind` command. The game restores its own most recent room backup, equivalent to the normal one-step rewind behavior. Isaac decides whether a rewind is currently available.

There is no custom timeline, multi-room cache, state reconstruction, collectible modification, pedestal spawning, room switching, tree interface, save-file access, or companion program. Repeated historical rewinds are not supported because the game exposes only its native last-room backup.

The input has a 45-frame cooldown to prevent one physical button press from invoking the command repeatedly.

## Installation

Run `Install-Mod.ps1`, then enable **Wheelchair Emergency Rewind** in Isaac's Mods menu.

The mod only installs `main.lua` and `metadata.xml` into Isaac's `mods\wheelchair` directory. It never reads or writes Steam userdata or Isaac save files.
