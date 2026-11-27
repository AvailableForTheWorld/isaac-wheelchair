[CmdletBinding()]
param(
    [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
    [string] $Mod = 'wheelchair',

    [string] $GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\The Binding of Isaac Rebirth',

    [switch] $WorkshopCopy
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$registryPath = Join-Path $repoRoot 'mods.json'
$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$modProperty = $registry.mods.PSObject.Properties[$Mod]

if ($null -eq $modProperty) {
    $available = ($registry.mods.PSObject.Properties.Name | Sort-Object) -join ', '
    throw "Unknown mod '$Mod'. Available mods: $available"
}

$entry = $modProperty.Value
if ($entry.installDirectory -notmatch '^[a-z0-9][a-z0-9-]*$') {
    throw "Invalid install directory for mod '$Mod'."
}

$modsRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'mods'))
$contentPath = [IO.Path]::GetFullPath((Join-Path $repoRoot $entry.workshopContentPath))
$modsPrefix = $modsRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $contentPath.StartsWith($modsPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "The registered content path for '$Mod' is outside the repository's mods directory."
}

$mainPath = Join-Path $contentPath 'main.lua'
$metadataPath = Join-Path $contentPath 'metadata.xml'
if (-not (Test-Path -LiteralPath $mainPath -PathType Leaf)) {
    throw "Missing main.lua for mod '$Mod': $mainPath"
}
if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
    throw "Missing metadata.xml for mod '$Mod': $metadataPath"
}

[xml] $metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8
$metadataId = [string] $metadata.metadata.id
$registeredWorkshopId = [string] $entry.workshopId
if (-not [string]::IsNullOrWhiteSpace($registeredWorkshopId) -and $metadataId -ne $registeredWorkshopId) {
    throw "Workshop ID mismatch for '$Mod': metadata.xml has '$metadataId', mods.json has '$($entry.workshopId)'."
}

$gameModsPath = Join-Path $GameRoot 'mods'
if ($WorkshopCopy) {
    if ($registeredWorkshopId -notmatch '^[0-9]+$') {
        throw "Mod '$Mod' has no valid Workshop ID in mods.json."
    }
    if (-not (Test-Path -LiteralPath $gameModsPath -PathType Container)) {
        throw "The game mods directory does not exist at '$gameModsPath'."
    }

    $workshopCopies = @(Get-ChildItem -LiteralPath $gameModsPath -Directory -Force |
        Where-Object Name -Like "*_$registeredWorkshopId")
    if ($workshopCopies.Count -ne 1) {
        throw "Expected one installed Workshop copy ending in '_$registeredWorkshopId' under '$gameModsPath' but found $($workshopCopies.Count)."
    }

    $target = $workshopCopies[0].FullName
    $installedMetadataPath = Join-Path $target 'metadata.xml'
    if (-not (Test-Path -LiteralPath $installedMetadataPath -PathType Leaf)) {
        throw "The installed Workshop copy has no metadata.xml at '$installedMetadataPath'."
    }
    [xml] $installedMetadata = Get-Content -LiteralPath $installedMetadataPath -Raw -Encoding UTF8
    if ([string] $installedMetadata.metadata.id -ne $registeredWorkshopId) {
        throw "The Workshop ID in '$installedMetadataPath' does not match '$registeredWorkshopId'."
    }
} else {
    $target = Join-Path $gameModsPath $entry.installDirectory
    New-Item -ItemType Directory -Force -Path $target | Out-Null
}

Get-ChildItem -LiteralPath $contentPath -Force | Copy-Item -Destination $target -Recurse -Force

Write-Host "Installed $($entry.displayName) to $target"
