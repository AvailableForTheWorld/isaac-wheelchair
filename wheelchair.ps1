param([switch]$NoGui, [switch]$SelfTest)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $root 'Wheelchair.Core.psm1') -Force
if ($NoGui) { return }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies 'System.Windows.Forms','System.Drawing' -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public sealed class WheelchairHotKeyEventArgs : EventArgs {
    public int Id { get; private set; }
    public WheelchairHotKeyEventArgs(int id) { Id = id; }
}

public sealed class WheelchairHotKeyWindow : NativeWindow {
    public event EventHandler<WheelchairHotKeyEventArgs> HotKeyPressed;
    public void Attach(IntPtr handle) { AssignHandle(handle); }
    protected override void WndProc(ref Message message) {
        if (message.Msg == 0x0312 && HotKeyPressed != null)
            HotKeyPressed(this, new WheelchairHotKeyEventArgs(message.WParam.ToInt32()));
        base.WndProc(ref message);
    }
}

[StructLayout(LayoutKind.Sequential)]
public struct WheelchairGamepad {
    public ushort Buttons;
    public byte LeftTrigger;
    public byte RightTrigger;
    public short ThumbLX;
    public short ThumbLY;
    public short ThumbRX;
    public short ThumbRY;
}

[StructLayout(LayoutKind.Sequential)]
public struct WheelchairControllerState {
    public uint PacketNumber;
    public WheelchairGamepad Gamepad;
}

public static class WheelchairNative {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint key);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("xinput1_4.dll")]
    public static extern uint XInputGetState(uint userIndex, out WheelchairControllerState state);
}
'@

[System.Windows.Forms.Application]::EnableVisualStyles()
if ($SelfTest) {
    $testState = New-Object WheelchairControllerState
    $controllerResult = [WheelchairNative]::XInputGetState(0,[ref]$testState)
    $testForm = New-Object Windows.Forms.Form
    $f6Registered = [WheelchairNative]::RegisterHotKey($testForm.Handle,91,0,0x75)
    $f7Registered = [WheelchairNative]::RegisterHotKey($testForm.Handle,92,0,0x76)
    if ($f6Registered) { [void][WheelchairNative]::UnregisterHotKey($testForm.Handle,91) }
    if ($f7Registered) { [void][WheelchairNative]::UnregisterHotKey($testForm.Handle,92) }
    $testForm.Dispose()
    if (-not $f6Registered -or -not $f7Registered) { throw 'F6 or F7 is already registered by another application (possibly another Wheelchair instance).' }
    Write-Output "PASS: UI types, F6/F7 global hotkeys, and XInput bridge loaded (controller result $controllerResult)"
    return
}
$script:busy = $false
$script:treeMode = $true
$script:lastButtons = [uint16]0
$script:lastRightTrigger = $false
$script:lastControllerConnected = $false

$form = New-Object Windows.Forms.Form
$form.Text = 'Wheelchair - Isaac checkpoint tree'
$form.Size = New-Object Drawing.Size(980,650)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI',10)
$form.BackColor = [Drawing.Color]::FromArgb(24,26,32)
$form.ForeColor = [Drawing.Color]::WhiteSmoke

$banner = New-Object Windows.Forms.Label
$banner.SetBounds(15,12,930,50)
$banner.ForeColor = [Drawing.Color]::WhiteSmoke
$banner.Text = 'RT / F6: create exact node (safe close, snapshot, resume)    LB / F7: show tree    Tree: X/Y/A/B = left/up/down/right, RT = restore, Back = close'
$form.Controls.Add($banner)

$tree = New-Object Windows.Forms.TreeView
$tree.SetBounds(15,65,650,490)
$tree.HideSelection = $false
$tree.BackColor = [Drawing.Color]::FromArgb(34,37,45)
$tree.ForeColor = [Drawing.Color]::WhiteSmoke
$tree.LineColor = [Drawing.Color]::SlateGray
$tree.FullRowSelect = $true
$form.Controls.Add($tree)

$status = New-Object Windows.Forms.Label
$status.SetBounds(15,565,930,36)
$status.ForeColor = [Drawing.Color]::LightSkyBlue
$form.Controls.Add($status)

$create = New-Object Windows.Forms.Button
$create.SetBounds(690,75,260,44)
$create.Text = 'Create node + resume (F6 / RT)'
$form.Controls.Add($create)

$restore = New-Object Windows.Forms.Button
$restore.SetBounds(690,132,260,44)
$restore.Text = 'Restore selected + resume (RT)'
$form.Controls.Add($restore)

$launch = New-Object Windows.Forms.Button
$launch.SetBounds(690,189,260,44)
$launch.Text = 'Launch Isaac'
$form.Controls.Add($launch)

$refresh = New-Object Windows.Forms.Button
$refresh.SetBounds(690,246,260,44)
$refresh.Text = 'Refresh tree'
$form.Controls.Add($refresh)

$hide = New-Object Windows.Forms.Button
$hide.SetBounds(690,303,260,44)
$hide.Text = 'Hide tree (Back)'
$form.Controls.Add($hide)

$help = New-Object Windows.Forms.Label
$help.SetBounds(690,380,260,175)
$help.ForeColor = [Drawing.Color]::Gainsboro
$help.Text = "Every checkpoint is a node.`r`nRestoring an older node moves HEAD there.`r`nYour next checkpoint becomes its child, so the old future remains as another branch.`r`n`r`nF5 still provides Isaac's quick one-room rewind."
$form.Controls.Add($help)

function Set-Status([string]$Text, [Drawing.Color]$Color = [Drawing.Color]::LightSkyBlue) {
    $status.ForeColor = $Color
    $status.Text = $Text
    [Windows.Forms.Application]::DoEvents()
}

function Update-Tree([string]$SelectId = $null) {
    if (-not $SelectId -and $tree.SelectedNode) { $SelectId = [string]$tree.SelectedNode.Tag }
    $tree.BeginUpdate()
    $tree.Nodes.Clear()
    $all = @(Get-WheelchairNodes $root)
    $byId = @{}
    foreach ($n in $all) {
        $isHead = (Get-WheelchairHead $root).nodeId -eq $n.id
        $marker = if ($isHead) { 'HEAD > ' } else { '' }
        $text = '{0}{1}  [{2}]  {3}' -f $marker,([datetime]$n.createdUtc).ToLocalTime().ToString('MM-dd HH:mm:ss'),$n.branch,$n.label
        $item = New-Object Windows.Forms.TreeNode($text)
        $item.Tag = [string]$n.id
        if ($isHead) { $item.ForeColor = [Drawing.Color]::LightGreen }
        $byId[[string]$n.id] = $item
        if ($n.parentId -and $byId.ContainsKey([string]$n.parentId)) { [void]$byId[[string]$n.parentId].Nodes.Add($item) }
        else { [void]$tree.Nodes.Add($item) }
    }
    $tree.ExpandAll()
    if ($SelectId -and $byId.ContainsKey($SelectId)) { $tree.SelectedNode = $byId[$SelectId] }
    elseif ($tree.Nodes.Count -gt 0) { $tree.SelectedNode = $tree.Nodes[0] }
    $tree.EndUpdate()
    $head = Get-WheelchairHead $root
    Set-Status "Nodes: $($all.Count)    HEAD: $($head.branch) / $($head.nodeId)    Isaac running: $(Test-IsaacRunning)"
}

function Show-Tree {
    $script:treeMode = $true
    Update-Tree
    $form.Show()
    $form.WindowState = 'Normal'
    $form.TopMost = $true
    $form.Activate()
    $form.BringToFront()
    [void][WheelchairNative]::SetForegroundWindow($form.Handle)
    $tree.Focus()
}

function Hide-Tree {
    $script:treeMode = $false
    $form.TopMost = $false
    $form.Hide()
}

function Stop-IsaacCleanly {
    $processes = @(Get-Process -Name 'isaac-ng' -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) { return $false }
    Set-Status 'Closing Isaac normally so its cached run state is written to disk...' ([Drawing.Color]::Khaki)
    foreach ($process in $processes) {
        if (-not $process.CloseMainWindow()) { throw 'Isaac did not expose a closable game window. Exit the game normally and try again; Wheelchair will never force-kill it.' }
    }
    $deadline = [datetime]::UtcNow.AddSeconds(20)
    while ((Test-IsaacRunning) -and [datetime]::UtcNow -lt $deadline) {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }
    if (Test-IsaacRunning) { throw 'Isaac did not close within 20 seconds. Close it normally; no checkpoint or restore was performed.' }
    Start-Sleep -Milliseconds 1200
    return $true
}

function Launch-Isaac {
    Set-Status 'Launching Isaac...' ([Drawing.Color]::Khaki)
    Start-Process 'steam://rungameid/250900'
    Hide-Tree
}

function Invoke-CreateNode {
    if ($script:busy) { return }
    $script:busy = $true
    try {
        $resume = Stop-IsaacCleanly
        $node = New-WheelchairNode $root ('controller checkpoint ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
        Update-Tree ([string]$node.id)
        Set-Status "Created node $($node.id)" ([Drawing.Color]::LightGreen)
        if ($resume) { Launch-Isaac }
    } catch { Set-Status $_.Exception.Message ([Drawing.Color]::Salmon); [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Wheelchair',0,16) | Out-Null }
    finally { $script:busy = $false }
}

function Invoke-RestoreSelected {
    if ($script:busy) { return }
    if (-not $tree.SelectedNode) { Set-Status 'Choose a node first.' ([Drawing.Color]::Salmon); return }
    $script:busy = $true
    try {
        [void](Stop-IsaacCleanly)
        $result = Restore-WheelchairNode $root ([string]$tree.SelectedNode.Tag)
        Update-Tree ([string]$result.node.id)
        Set-Status "Restored node. Continuing on $($result.branch)." ([Drawing.Color]::LightGreen)
        Launch-Isaac
    } catch { Set-Status $_.Exception.Message ([Drawing.Color]::Salmon); [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Wheelchair',0,16) | Out-Null }
    finally { $script:busy = $false }
}

function Move-TreeLeft {
    $node = $tree.SelectedNode
    if (-not $node) { return }
    if ($node.IsExpanded -and $node.Nodes.Count -gt 0) { $node.Collapse() }
    elseif ($node.Parent) { $tree.SelectedNode = $node.Parent }
}
function Move-TreeRight {
    $node = $tree.SelectedNode
    if (-not $node -or $node.Nodes.Count -eq 0) { return }
    $node.Expand()
    $tree.SelectedNode = $node.Nodes[0]
    $tree.SelectedNode.EnsureVisible()
}
function Move-TreeUp { if ($tree.SelectedNode -and $tree.SelectedNode.PrevVisibleNode) { $tree.SelectedNode = $tree.SelectedNode.PrevVisibleNode; $tree.SelectedNode.EnsureVisible() } }
function Move-TreeDown { if ($tree.SelectedNode -and $tree.SelectedNode.NextVisibleNode) { $tree.SelectedNode = $tree.SelectedNode.NextVisibleNode; $tree.SelectedNode.EnsureVisible() } }

$create.Add_Click({ Invoke-CreateNode })
$restore.Add_Click({ Invoke-RestoreSelected })
$launch.Add_Click({ Launch-Isaac })
$refresh.Add_Click({ Update-Tree })
$hide.Add_Click({ Hide-Tree })

# Global keyboard shortcuts: F6 checkpoint and F7 tree, even while Isaac has focus.
$hotKeyWindow = New-Object WheelchairHotKeyWindow
$hotKeyWindow.Attach($form.Handle)
if (-not [WheelchairNative]::RegisterHotKey($form.Handle,1,0,0x75)) { Set-Status 'Warning: global F6 could not be registered.' ([Drawing.Color]::Khaki) }
if (-not [WheelchairNative]::RegisterHotKey($form.Handle,2,0,0x76)) { Set-Status 'Warning: global F7 could not be registered.' ([Drawing.Color]::Khaki) }
$hotKeyWindow.add_HotKeyPressed({
    param($sender,$eventArgs)
    if ($eventArgs.Id -eq 1) { Invoke-CreateNode }
    elseif ($eventArgs.Id -eq 2) { Show-Tree }
})

# XInput mapping: X/Y/A/B = left/up/down/right, LB = tree, RT = checkpoint/restore, Back = close tree.
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 60
$timer.Add_Tick({
    $state = New-Object WheelchairControllerState
    try { $connected = ([WheelchairNative]::XInputGetState(0,[ref]$state) -eq 0) } catch { $connected = $false }
    if ($connected) {
        $buttons = [uint16]$state.Gamepad.Buttons
        $pressed = [uint16]($buttons -band (-bnot $script:lastButtons))
        $rt = $state.Gamepad.RightTrigger -ge 180
        $rtPressed = $rt -and -not $script:lastRightTrigger
        if (($pressed -band 0x0100) -ne 0) { Show-Tree }
        elseif ($script:treeMode) {
            if (($pressed -band 0x4000) -ne 0) { Move-TreeLeft }
            if (($pressed -band 0x8000) -ne 0) { Move-TreeUp }
            if (($pressed -band 0x1000) -ne 0) { Move-TreeDown }
            if (($pressed -band 0x2000) -ne 0) { Move-TreeRight }
            if (($pressed -band 0x0020) -ne 0) { Hide-Tree }
            if ($rtPressed) { Invoke-RestoreSelected }
        } elseif ($rtPressed) { Invoke-CreateNode }
        $script:lastButtons = $buttons
        $script:lastRightTrigger = $rt
        $script:lastControllerConnected = $true
    } else {
        $script:lastButtons = [uint16]0
        $script:lastRightTrigger = $false
        $script:lastControllerConnected = $false
    }
})
$timer.Start()

$form.Add_FormClosing({
    [void][WheelchairNative]::UnregisterHotKey($form.Handle,1)
    [void][WheelchairNative]::UnregisterHotKey($form.Handle,2)
})
Update-Tree
[void]$form.ShowDialog()
