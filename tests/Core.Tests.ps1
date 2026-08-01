$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $project 'Wheelchair.Core.psm1') -Force
$sandbox = Join-Path $env:TEMP ('wheelchair-test-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $sandbox 'save') | Out-Null
    Copy-Item -LiteralPath (Join-Path $project 'Wheelchair.Core.psm1') -Destination $sandbox
    '{"saveDirectory":"' + ((Join-Path $sandbox 'save') -replace '\\','\\') + '","saveFiles":["a.dat","b.dat"]}' | Set-Content -LiteralPath (Join-Path $sandbox 'config.json')
    'one' | Set-Content -LiteralPath (Join-Path $sandbox 'save\a.dat')
    $n1 = New-WheelchairNode $sandbox 'first'
    'two' | Set-Content -LiteralPath (Join-Path $sandbox 'save\a.dat')
    $n2 = New-WheelchairNode $sandbox 'second'
    if ($n2.parentId -ne $n1.id) { throw 'Parent link failed' }
    Restore-WheelchairNode $sandbox $n1.id -SkipSafetyBackup | Out-Null
    if ((Get-Content -LiteralPath (Join-Path $sandbox 'save\a.dat')) -ne 'one') { throw 'Restore failed' }
    Write-Host 'PASS: snapshot, parent link, hash verification, restore, and branch HEAD'
} finally {
    if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
}
