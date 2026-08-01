# Wheelchair

Wheelchair adds a branchable checkpoint tree plus a deliberately separate quick rewind to The Binding of Isaac: Repentance+.

1. **Exact branchable checkpoints:** keep the companion running and press **RT** or global **F6**. Wheelchair closes Isaac normally, waits for cached run state to flush, creates an immutable SHA-256-checked node, and relaunches the game. Restoring an older node preserves the old future and makes the next checkpoint a child on a new branch.
2. **Controller tree:** press **LB** or global **F7** to show the tree over the game. Use **X/Y/A/B** for left/up/down/right, **RT** to restore the highlighted node, and **Back** to hide the tree.
3. **Quick rewind:** press **F5** in a run for Isaac's built-in one-room rewind. It cannot go back multiple rooms; use exact nodes for that.

## Installed paths

- Project: `C:\software\program\project\others\mod\issac\wheelchair`
- Game mod: `C:\Program Files (x86)\Steam\steamapps\common\The Binding of Isaac Rebirth\mods\wheelchair`
- Save input: detected automatically below Steam's `userdata` directory; no account identifier is stored in the repository
- Checkpoint store: `data\nodes` under this project (kept outside Steam Cloud)

## First run

1. Run `Install-Mod.ps1` once (already done by the initial setup).
2. Start `Start-Wheelchair.cmd`.
3. Enable **Wheelchair Quick Rewind** in Isaac's Mods menu.
4. Strongly consider disabling Steam Cloud for Isaac. Cloud synchronization can replace locally restored files.

Wheelchair automatically finds the Isaac save directory when only one local Steam account matches. If several local accounts have matching saves, set `saveDirectory` in your local `config.json` and do not commit that private override.

## Safe checkpoint workflow

1. Keep `Start-Wheelchair.cmd` running while playing.
2. Press **RT** or **F6** to create a node. The close/snapshot/relaunch cycle is automatic because live file replacement is unsafe.
3. Press **LB** or **F7** to open the tree.
4. Navigate with **X/Y/A/B** and press **RT** on any node to restore it.
5. Wheelchair creates an automatic safety node, restores through verified temporary files, starts a new branch at the selected node, and relaunches Isaac.

Do not manually overwrite these files while Isaac is running. `rep+gamestate1.dat` is the current resumable run; `persistentgamedata` files primarily contain profile/unlock progress. The project treats them as opaque binary files and never edits their contents.

## Test

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Core.Tests.ps1`
