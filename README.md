# Isaac Mods Monorepo

This repository contains independently installable and publishable mods for The Binding of Isaac: Repentance+.

## Mods

| Registry key | Mod | Local package | Steam Workshop |
| --- | --- | --- | --- |
| `opening-presets` | Opening Presets | [Documentation](mods/opening-presets/README.md) | Local-only; first upload pending |
| `sharingan` | Sharingan / 写轮眼 | [Documentation](mods/sharingan/README.md) | Local-only; first upload pending |
| `wheelchair` | Wheelchair Emergency Rewind | [Documentation](mods/wheelchair/README.md) | [Workshop item 3775722454](https://steamcommunity.com/sharedfiles/filedetails/?id=3775722454) |

## Repository layout

```text
mods.json                         Mod registry used by scripts and CI
mods/<key>/content/               Exact directory uploaded to Workshop
mods/<key>/README.md              Mod-specific documentation
mods/<key>/assets/                Repository assets; not uploaded
Install-Mod.ps1                   Installs one registered mod locally
.github/workflows/update-workshop.yml
                                  Publishes one registered mod
```

Keeping Workshop content in a dedicated `content` directory prevents documentation, preview source files, and files belonging to other mods from being uploaded accidentally.

## Install a mod locally

Close Isaac, then run this from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1 -Mod wheelchair
```

The `-Mod` value is a key from [`mods.json`](mods.json). The installer validates the registered content path and Workshop ID before copying that mod into Isaac's `mods` directory.

## Add another mod

1. Create `mods/<key>/content/main.lua` and `mods/<key>/content/metadata.xml`.
2. Keep that mod's README and non-Workshop assets outside its `content` directory.
3. Add an entry to [`mods.json`](mods.json) with a unique key, content path, install directory, and `"workshopId": null` while the mod is still local-only.
4. Install it locally with `Install-Mod.ps1 -Mod <key>` and test it.
5. For a brand-new Workshop item, perform its first upload with Isaac's `ModUploader.exe`. The CI uploader requires an existing Workshop ID. Copy the generated ID into both `metadata.xml` and `mods.json`; subsequent updates can use the shared workflow.

## Update a Workshop item

Open the repository's **Actions** tab, choose **Update Steam Workshop**, and select **Run workflow**. Enter:

- **Mod registry key:** the key from `mods.json`, such as `wheelchair`.
- **Workshop change note:** the note for that mod's update.

The workflow resolves the selected mod's own `workshopContentPath`, requires `main.lua` and `metadata.xml`, and verifies that the ID in `metadata.xml` matches the registry before invoking the uploader. The existing `CONFIG_VDF_CONTENTS` and `STEAM_USERNAME` repository secrets are shared by all registered mods published by the same Steam account.
