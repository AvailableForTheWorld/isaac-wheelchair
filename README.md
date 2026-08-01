# Wheelchair Emergency Rewind

Wheelchair is a minimal in-game emergency rewind for The Binding of Isaac: Repentance+.

## Default controls

- **G** on the keyboard.
- **Right Trigger** on a controller.

Either input invokes Isaac's built-in `rewind` command. The game restores its own most recent room backup, equivalent to the normal one-step rewind behavior. Isaac decides whether a rewind is currently available.

There is no custom timeline, multi-room cache, state reconstruction, collectible modification, pedestal spawning, room switching, tree interface, or Steam save-file access. Repeated historical rewinds are not supported because the game exposes only its native last-room backup.

The input has a 45-frame cooldown to prevent one physical button press from invoking the command repeatedly.

## Changing the shortcuts

Wheelchair supports [Mod Config Menu - Impure](https://steamcommunity.com/sharedfiles/filedetails/?id=3701683951), the maintained MCM version for Repentance and Repentance+.

1. Install and enable **Mod Config Menu - Impure**. Do not enable another MCM version at the same time.
2. Start or continue a run.
3. Press **L** on the keyboard or press the **right stick** on a controller to open MCM.
4. Open **Wheelchair > Controls**.
5. Select **Keyboard shortcut** or **Controller shortcut**, then press the new key or button.

The two bindings can be changed independently or unbound. MCM stores the selected values. Without MCM, Wheelchair continues to use G and Right Trigger.

Wheelchair ignores its rewind shortcuts while the MCM panel is open, preventing menu navigation or key capture from accidentally triggering rewind.

## Installation

Run `Install-Mod.ps1`, then enable **Wheelchair Emergency Rewind** in Isaac's Mods menu.

The Wheelchair installer only copies `main.lua` and `metadata.xml` into Isaac's `mods\wheelchair` directory. It never reads or writes Steam userdata or Isaac save files.
