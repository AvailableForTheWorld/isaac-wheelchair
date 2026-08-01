param([switch]$NoGui)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $root 'Wheelchair.Core.psm1') -Force
if ($NoGui) { return }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object Windows.Forms.Form
$form.Text = 'Wheelchair - Isaac checkpoints'
$form.Size = New-Object Drawing.Size(900,600)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI',10)

$banner = New-Object Windows.Forms.Label
$banner.SetBounds(15,12,850,48)
$banner.Text = 'Exact checkpoints require Isaac to be CLOSED. F5 / controller RT inside the game performs the instant one-room emergency rewind.'
$form.Controls.Add($banner)

$tree = New-Object Windows.Forms.TreeView
$tree.SetBounds(15,65,565,450)
$tree.HideSelection = $false
$form.Controls.Add($tree)

$status = New-Object Windows.Forms.Label
$status.SetBounds(15,525,850,28)
$form.Controls.Add($status)

$create = New-Object Windows.Forms.Button
$create.SetBounds(600,75,260,42)
$create.Text = 'Create checkpoint (F6)'
$form.Controls.Add($create)

$restore = New-Object Windows.Forms.Button
$restore.SetBounds(600,130,260,42)
$restore.Text = 'Restore selected node'
$form.Controls.Add($restore)

$launch = New-Object Windows.Forms.Button
$launch.SetBounds(600,185,260,42)
$launch.Text = 'Launch Isaac'
$form.Controls.Add($launch)

$refresh = New-Object Windows.Forms.Button
$refresh.SetBounds(600,240,260,42)
$refresh.Text = 'Refresh'
$form.Controls.Add($refresh)

$help = New-Object Windows.Forms.Label
$help.SetBounds(600,310,260,170)
$help.Text = "Workflow:`r`n1. Exit Isaac normally.`r`n2. Click Create (or F6 while this window is focused).`r`n3. Select any node and Restore.`r`n4. Relaunch. The next checkpoint becomes a new branch."
$form.Controls.Add($help)

function Update-Tree {
    $tree.Nodes.Clear()
    $all = @(Get-WheelchairNodes $root)
    $byId = @{}
    foreach ($n in $all) {
        $text = '{0}  [{1}]  {2}' -f ([datetime]$n.createdUtc).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss'),$n.branch,$n.label
        $item = New-Object Windows.Forms.TreeNode($text)
        $item.Tag = $n.id
        $byId[$n.id] = $item
        if ($n.parentId -and $byId.ContainsKey([string]$n.parentId)) { [void]$byId[[string]$n.parentId].Nodes.Add($item) } else { [void]$tree.Nodes.Add($item) }
    }
    $tree.ExpandAll()
    $head = Get-WheelchairHead $root
    $status.Text = "HEAD: $($head.branch) / $($head.nodeId)    Isaac running: $(Test-IsaacRunning)"
}

$create.Add_Click({
    try { $n = New-WheelchairNode $root; Update-Tree; [Windows.Forms.MessageBox]::Show("Created $($n.id)",'Wheelchair') | Out-Null }
    catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Wheelchair',0,16) | Out-Null }
})
$restore.Add_Click({
    if (-not $tree.SelectedNode) { [Windows.Forms.MessageBox]::Show('Choose a node first.','Wheelchair') | Out-Null; return }
    if ([Windows.Forms.MessageBox]::Show('Restore this node? A safety checkpoint of the current disk state will be created first.','Wheelchair',4,48) -ne 'Yes') { return }
    try { $r = Restore-WheelchairNode $root ([string]$tree.SelectedNode.Tag); Update-Tree; [Windows.Forms.MessageBox]::Show("Restored. New branch: $($r.branch). You may launch Isaac.",'Wheelchair') | Out-Null }
    catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Wheelchair',0,16) | Out-Null }
})
$launch.Add_Click({ Start-Process 'steam://rungameid/250900' })
$refresh.Add_Click({ Update-Tree })

$form.KeyPreview = $true
$form.Add_KeyDown({ if ($_.KeyCode -eq 'F6') { $create.PerformClick() } })
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 1500
$timer.Add_Tick({ $status.Text = ($status.Text -replace 'Isaac running: (True|False)$',("Isaac running: " + (Test-IsaacRunning))) })
$timer.Start()
Update-Tree
[void]$form.ShowDialog()
