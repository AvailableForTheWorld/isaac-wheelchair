$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = 'C:\Program Files (x86)\Steam\steamapps\common\The Binding of Isaac Rebirth\mods\wheelchair'
New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'mod\main.lua') -Destination $target -Force
Copy-Item -LiteralPath (Join-Path $root 'mod\metadata.xml') -Destination $target -Force
Write-Host "Installed to $target"
