Set-StrictMode -Version Latest

function Get-WheelchairConfig {
    param([string]$ProjectRoot)
    $path = Join-Path $ProjectRoot 'config.json'
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing config: $path" }
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Test-IsaacRunning {
    [bool](Get-Process -Name 'isaac-ng' -ErrorAction SilentlyContinue)
}

function Resolve-WheelchairSaveDirectory {
    param([string]$ProjectRoot)
    $config = Get-WheelchairConfig $ProjectRoot
    if ($config.saveDirectory -and (Test-Path -LiteralPath $config.saveDirectory -PathType Container)) {
        return [string]$config.saveDirectory
    }
    $userdata = 'C:\Program Files (x86)\Steam\userdata'
    if (-not (Test-Path -LiteralPath $userdata -PathType Container)) {
        throw 'Steam userdata folder was not found. Set saveDirectory in config.json manually.'
    }
    $candidates = @(Get-ChildItem -LiteralPath $userdata -Directory | ForEach-Object {
        $remote = Join-Path $_.FullName '250900\remote'
        if (Test-Path -LiteralPath $remote -PathType Container) {
            $matches = @($config.saveFiles | Where-Object { Test-Path -LiteralPath (Join-Path $remote $_) -PathType Leaf })
            if ($matches.Count -gt 0) { [pscustomobject]@{ path=$remote; matchCount=$matches.Count } }
        }
    } | Sort-Object matchCount -Descending)
    if ($candidates.Count -eq 1) { return [string]$candidates[0].path }
    if ($candidates.Count -gt 1 -and $candidates[0].matchCount -gt $candidates[1].matchCount) { return [string]$candidates[0].path }
    if ($candidates.Count -eq 0) { throw 'No Isaac Steam Cloud save directory was detected. Set saveDirectory in config.json manually.' }
    throw 'Multiple Steam accounts have Isaac saves. Set saveDirectory in your uncommitted config.json before continuing.'
}

function Get-WheelchairNodes {
    param([string]$ProjectRoot)
    $nodesRoot = Join-Path $ProjectRoot 'data\nodes'
    if (-not (Test-Path -LiteralPath $nodesRoot)) { return @() }
    @(Get-ChildItem -LiteralPath $nodesRoot -Directory | ForEach-Object {
        $meta = Join-Path $_.FullName 'node.json'
        if (Test-Path -LiteralPath $meta) { Get-Content -LiteralPath $meta -Raw | ConvertFrom-Json }
    } | Sort-Object createdUtc)
}

function Get-WheelchairHead {
    param([string]$ProjectRoot)
    $path = Join-Path $ProjectRoot 'data\HEAD.json'
    if (Test-Path -LiteralPath $path) { return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json) }
    [pscustomobject]@{ nodeId = $null; branch = 'main' }
}

function Set-WheelchairHead {
    param([string]$ProjectRoot, [AllowNull()][string]$NodeId, [string]$Branch)
    $data = Join-Path $ProjectRoot 'data'
    New-Item -ItemType Directory -Force -Path $data | Out-Null
    [ordered]@{ nodeId=$NodeId; branch=$Branch } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $data 'HEAD.json') -Encoding UTF8
}

function New-WheelchairNode {
    param([string]$ProjectRoot, [string]$Label = 'checkpoint', [switch]$AllowWhileRunning)
    if ((Test-IsaacRunning) -and -not $AllowWhileRunning) { throw 'Isaac is running. Exit to the title/menu, close the game normally, then create the checkpoint so cached state is flushed.' }
    $config = Get-WheelchairConfig $ProjectRoot
    $saveDirectory = Resolve-WheelchairSaveDirectory $ProjectRoot
    $head = Get-WheelchairHead $ProjectRoot
    $id = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
    $folder = Join-Path $ProjectRoot ("data\nodes\$id")
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $files = @()
    foreach ($name in $config.saveFiles) {
        $source = Join-Path $saveDirectory $name
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $folder $name)
            $files += [ordered]@{ name=$name; length=(Get-Item -LiteralPath $source).Length; sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash }
        }
    }
    if ($files.Count -eq 0) { Remove-Item -LiteralPath $folder -Force; throw 'None of the configured save files exist.' }
    $meta = [ordered]@{ id=$id; parentId=$head.nodeId; branch=$head.branch; label=$Label; createdUtc=(Get-Date).ToUniversalTime().ToString('o'); files=$files }
    $meta | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $folder 'node.json') -Encoding UTF8
    Set-WheelchairHead $ProjectRoot $id $head.branch
    [pscustomobject]$meta
}

function Restore-WheelchairNode {
    param([string]$ProjectRoot, [string]$NodeId, [switch]$SkipSafetyBackup)
    if (Test-IsaacRunning) { throw 'Isaac is running. Close it normally before restoring; live overwrite is unsafe because the game caches save state.' }
    $config = Get-WheelchairConfig $ProjectRoot
    $saveDirectory = Resolve-WheelchairSaveDirectory $ProjectRoot
    $nodeFolder = Join-Path $ProjectRoot ("data\nodes\$NodeId")
    $metaPath = Join-Path $nodeFolder 'node.json'
    if (-not (Test-Path -LiteralPath $metaPath)) { throw "Unknown node: $NodeId" }
    if (-not $SkipSafetyBackup) { New-WheelchairNode $ProjectRoot "automatic backup before restoring $NodeId" | Out-Null }
    $meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
    foreach ($entry in $meta.files) {
        $source = Join-Path $nodeFolder $entry.name
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $entry.sha256) { throw "Checkpoint file failed integrity check: $($entry.name)" }
    }
    foreach ($entry in $meta.files) {
        $destination = Join-Path $saveDirectory $entry.name
        $temp = "$destination.wheelchair.tmp"
        Copy-Item -LiteralPath (Join-Path $nodeFolder $entry.name) -Destination $temp -Force
        Move-Item -LiteralPath $temp -Destination $destination -Force
    }
    $newBranch = 'branch-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Set-WheelchairHead $ProjectRoot $NodeId $newBranch
    [pscustomobject]@{ node=$meta; branch=$newBranch }
}

Export-ModuleMember -Function *-Wheelchair*,Test-IsaacRunning
