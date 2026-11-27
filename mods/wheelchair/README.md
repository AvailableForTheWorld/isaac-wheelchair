# Wheelchair Emergency Rewind

![Isaac wheeling himself in a wheelchair](assets/workshop-cover.png)

Wheelchair is a minimal in-game emergency rewind for The Binding of Isaac: Repentance+.

## Repentance+ 1.9.7.19 compatibility

Version **3.2.4** supports the input-device changes in Repentance+ **1.9.7.19** (including build J511). That update moved the keyboard index from `0` to `-2` and made physical controller indexes start at `0`. Wheelchair now reads the dedicated keyboard index first, retains the legacy keyboard fallback, and uses each player's actual controller index. See the [Input API documentation](https://wofsauge.github.io/IsaacDocs/rep/Input.html).

The default **G / Right Trigger** shortcuts work without Mod Config Menu. MCM Impure's author has [reported input problems in the Repentance+ full release](https://github.com/piber20/Mod-Config-Menu-Impure/issues/8); its configuration menu may remain unavailable until MCM is updated. Wheelchair does not modify MCM or the game's global input functions.

## Default controls

- **G** on the keyboard.
- **Right Trigger** on a controller.

Either input invokes Isaac's built-in `rewind` command. The game restores its own most recent room backup, equivalent to the normal one-step rewind behavior. Isaac decides whether a rewind is currently available.

There is no custom timeline, multi-room cache, state reconstruction, collectible modification, pedestal spawning, room switching, tree interface, or Steam save-file access. Repeated historical rewinds are not supported because the game exposes only its native last-room backup.

Wheelchair tracks the keyboard and controller buttons' pressed states every update to detect one reliable rising edge per physical press, including analog triggers such as RT. It invokes `rewind` immediately. There is no timer, hold duration, or input cooldown in the mod.

Version **3.2.5** improves RT detection for Repentance+ **1.9.7.20**. If the raw button check misses the press, Wheelchair also reads the trigger's analog value. For controller indexes above zero it can also read Isaac's **Menu RT** action, which uses RT by default. These readings share one pressed state, so holding the trigger still sends one rewind request.

## Changing the shortcuts

Wheelchair integrates with [Mod Config Menu - Impure](https://steamcommunity.com/sharedfiles/filedetails/?id=3701683951). The steps below require an MCM version compatible with your game build; see the compatibility note above for Repentance+ 1.9.7.19.

1. Install and enable **Mod Config Menu - Impure**. Do not enable another MCM version at the same time.
2. Start or continue a run.
3. Press **L** on the keyboard or press the **right stick** on a controller to open MCM.
4. Open **Wheelchair > Controls**.
5. Select **Keyboard shortcut** or **Controller shortcut**, then press the new key or button.

The two bindings can be changed independently or unbound. MCM stores the selected values. Without MCM, Wheelchair continues to use G and Right Trigger.

Wheelchair ignores its rewind shortcuts while the MCM panel is open, preventing menu navigation or key capture from accidentally triggering rewind.

## Languages

Wheelchair supports English and Simplified Chinese. Its MCM labels and help text follow Isaac's language setting: Chinese is used when the game language is Simplified Chinese, and English is the fallback for every other language. The mod name and description in `metadata.xml` contain both languages for the Steam Workshop and Isaac's Mods menu.

## Installation

From the repository root, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1 -Mod wheelchair
```

Then enable **Wheelchair Emergency Rewind** in Isaac's Mods menu.

The Wheelchair installer only copies `main.lua` and `metadata.xml` into Isaac's `mods\wheelchair` directory. It never reads or writes Steam userdata or Isaac save files.

## Validation

From the repository root, run `lua tests/wheelchair_spec.lua` with Lua 5.3 or newer. These checks simulate the old and new input layouts, controller aliases, held buttons, custom bindings, and pause/MCM suppression. Physical G / RT input and the game's room-backup restoration still require an in-game check.
