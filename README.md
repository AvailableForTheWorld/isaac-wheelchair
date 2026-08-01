# Wheelchair

Wheelchair adds two deliberately separate kinds of undo to The Binding of Isaac: Repentance+.

1. **Emergency rewind:** while a run is active, press **F5** or **controller RT**. The Lua mod invokes Isaac's built-in `rewind`, equivalent to a Glowing Hourglass: it forgets changes in the current room and returns to the previous room. This is fast, but it is not an arbitrary historical checkpoint.
2. **Exact branchable checkpoints:** close Isaac normally so it flushes its cached run state, then use the companion window to copy the five configured Steam save files into immutable, SHA-256-checked nodes. Restoring a node creates a new branch; the next checkpoint is its child.

## Installed paths

- Project: `C:\software\program\project\others\mod\issac\wheelchair`
- Game mod: `C:\Program Files (x86)\Steam\steamapps\common\The Binding of Isaac Rebirth\mods\wheelchair`
- Save input: detected automatically below Steam's `userdata` directory; no account identifier is stored in the repository
- Checkpoint store: `data\nodes` under this project (kept outside Steam Cloud)

## First run

1. Run `Install-Mod.ps1` once (already done by the initial setup).
2. Start `Start-Wheelchair.cmd`.
3. Enable **Wheelchair Emergency Rewind** in Isaac's Mods menu.
4. Strongly consider disabling Steam Cloud for Isaac. Cloud synchronization can replace locally restored files.

Wheelchair automatically finds the Isaac save directory when only one local Steam account matches. If several local accounts have matching saves, set `saveDirectory` in your local `config.json` and do not commit that private override.

## Safe checkpoint workflow

1. In Isaac, exit the run to the main menu, then close the game normally.
2. In Wheelchair, choose **Create checkpoint** (F6 while its window is focused).
3. To go back, keep Isaac closed, choose a node, and click **Restore selected node**.
4. Wheelchair first snapshots the current disk state as an automatic safety node, restores via temporary files, verifies SHA-256 hashes, and moves HEAD to a newly named branch.
5. Launch Isaac from the button.

Do not manually overwrite these files while Isaac is running. `rep+gamestate1.dat` is the current resumable run; `persistentgamedata` files primarily contain profile/unlock progress. The project treats them as opaque binary files and never edits their contents.

## Test

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Core.Tests.ps1`
