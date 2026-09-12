# ram.ps1 — Task-Manager for the Windows terminal. Windows port of the macOS `ram` zsh tool.
#
#   ram                dashboard: memory / commit / disk, top apps, and GPU usage
#   ram -w             live mode, refreshes every 2s (Ctrl-C to exit)
#   ram -c             sort by CPU instead of memory
#   ram -n 25          show N rows (default 15)
#   ram -i             interactive: pick a number to quit that app
#   ram <name>         quit processes matching <name> (graceful, then force)
#   ram gpu            GPU detail: per-adapter load and which processes are on which card
#   ram ports | ram -p list listening ports
#   ram port <n>       free that one port
#   ram clean          trim working sets and purge user temp files
#   ram big [path]     largest files (default: profile + D:\)
#   ram disk           disk view
#
# Never kills Windows-critical processes (see $PROTECTED).
# PowerShell 5.1 compatible: no ternary, no null-coalescing, no pipeline chain operators.

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args_
)

$ESC = [char]27
$R = "$ESC[0m"; $B = "$ESC[1m"; $DIM = "$ESC[2m"
$RED = "$ESC[38;5;203m"; $YEL = "$ESC[38;5;221m"; $GRN = "$ESC[38;5;114m"
$BLU = "$ESC[38;5;75m"; $MAG = "$ESC[38;5;176m"; $GRY = "$ESC[38;5;245m"

# Killing any of these takes the desktop or the session down with it.
$PROTECTED = @(
    'System', 'Idle', 'Registry', 'Memory Compression', 'smss', 'csrss', 'wininit',
    'winlogon', 'services', 'lsass', 'svchost', 'dwm', 'fontdrvhost', 'sihost',
    'ctfmon', 'LsaIso', 'SecurityHealthService', 'MsMpEng', 'WUDFHost', 'audiodg'
)

# ── helpers ──────────────────────────────────────────────────────────────────
function Bar([int]$pct, [int]$width, [string]$color) {
    if ($pct -lt 0) { $pct = 0 }
    if ($pct -gt 100) { $pct = 100 }
    $filled = [math]::Floor($pct * $width / 100)
    $out = ('█' * $filled) + ('·' * ($width - $filled))
    return "$color$out$R"
}

function Heat([int]$pct) {
    if ($pct -ge 85) { return $RED }
    if ($pct -ge 65) { return $YEL }
    return $GRN
}

function HumanMB([double]$mb) {
    if ($mb -ge 1024) { return ('{0:N1} GB' -f ($mb / 1024)) }
    return ('{0:N0} MB' -f $mb)
}

function Get-MemStat {
    $os = Get-CimInstance Win32_OperatingSystem
    $totalMB = $os.TotalVisibleMemorySize / 1KB
    $freeMB = $os.FreePhysicalMemory / 1KB
    $commitMB = ($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / 1KB
    $commitLimitMB = $os.TotalVirtualMemorySize / 1KB
    return [pscustomobject]@{
        TotalMB       = $totalMB
        FreeMB        = $freeMB
        UsedPct       = [math]::Round((($totalMB - $freeMB) / $totalMB) * 100)
        CommitMB      = $commitMB
        CommitLimitMB = $commitLimitMB
        CommitPct     = [math]::Round(($commitMB / $commitLimitMB) * 100)
    }
}

# Group helper processes under one name, the way the macOS version collapses .app bundles.
function Get-AppRows {
    $cpuCount = [Environment]::ProcessorCount
    Get-Process -ErrorAction SilentlyContinue | Group-Object ProcessName | ForEach-Object {
        $mem = ($_.Group | Measure-Object PrivateMemorySize64 -Sum).Sum / 1MB
        $cpuSec = ($_.Group | Measure-Object CPU -Sum).Sum
        $started = ($_.Group | Where-Object { $_.StartTime } | Sort-Object StartTime | Select-Object -First 1).StartTime
        $cpuPct = 0.0
        if ($started) {
            $elapsed = ((Get-Date) - $started).TotalSeconds
            if ($elapsed -gt 1) { $cpuPct = [math]::Round(($cpuSec / $elapsed / $cpuCount) * 100, 1) }
        }
        [pscustomobject]@{
            Name   = $_.Name
            Count  = $_.Count
            MemMB  = [math]::Round($mem)
            CpuPct = $cpuPct
            Ids    = $_.Group.Id
        }
    }
}

# ── GPU ──────────────────────────────────────────────────────────────────────
# Windows exposes GPU work per process through counters keyed by pid and adapter LUID.
# The adapter holding dedicated memory is the discrete card; integrated graphics report 0.
function Get-GpuAdapters {
    $adapters = @{}
    $ded = (Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction SilentlyContinue).CounterSamples
    foreach ($s in $ded) {
        if ($s.InstanceName -match 'luid_0x[0-9a-fA-F]+_0x([0-9a-fA-F]+)') {
            $luid = $matches[1]
            if (-not $adapters.ContainsKey($luid)) { $adapters[$luid] = 0 }
            $adapters[$luid] += $s.CookedValue
        }
    }
    return $adapters
}

function Get-GpuRows {
    $adapters = Get-GpuAdapters
    # Highest dedicated memory wins: that is the discrete GPU.
    $discrete = $null
    $best = -1
    foreach ($k in $adapters.Keys) { if ($adapters[$k] -gt $best) { $best = $adapters[$k]; $discrete = $k } }
    if ($best -le 0) { $discrete = $null }

    $rows = @{}
    $eng = (Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction SilentlyContinue).CounterSamples
    foreach ($s in $eng) {
        if ($s.CookedValue -le 0) { continue }
        if ($s.InstanceName -notmatch 'pid_(\d+)') { continue }
        $procId = $matches[1]
        $luid = ''
        if ($s.InstanceName -match 'luid_0x[0-9a-fA-F]+_0x([0-9a-fA-F]+)') { $luid = $matches[1] }
        $card = 'Integrated'
        if ($discrete -and $luid -eq $discrete) { $card = 'Discrete' }
        $key = "$procId|$card"
        if (-not $rows.ContainsKey($key)) {
            $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
            $pname = '(gone)'
            if ($p) { $pname = $p.ProcessName }
            $rows[$key] = [pscustomobject]@{ Name = $pname; PID = $procId; Card = $card; Pct = 0.0; VramMB = 0; SharedMB = 0 }
        }
        $rows[$key].Pct += $s.CookedValue
    }

    # Per-process graphics memory, same LUID rule.
    #   Dedicated = on the card's own chips. Not system RAM, so it never appears in the
    #               app table above.
    #   Shared    = system RAM the GPU borrows. This IS part of the process's RAM figure,
    #               so it is the only number that appears in both tables.
    foreach ($kind in @('Dedicated Usage', 'Shared Usage')) {
        $pm = (Get-Counter "\GPU Process Memory(*)\$kind" -ErrorAction SilentlyContinue).CounterSamples
        foreach ($s in $pm) {
            if ($s.CookedValue -le 0) { continue }
            if ($s.InstanceName -notmatch 'pid_(\d+)') { continue }
            $procId = $matches[1]
            $luid = ''
            if ($s.InstanceName -match 'luid_0x[0-9a-fA-F]+_0x([0-9a-fA-F]+)') { $luid = $matches[1] }
            $card = 'Integrated'
            if ($discrete -and $luid -eq $discrete) { $card = 'Discrete' }
            $key = "$procId|$card"
            if (-not $rows.ContainsKey($key)) {
                $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
                $pname = '(gone)'
                if ($p) { $pname = $p.ProcessName }
                $rows[$key] = [pscustomobject]@{ Name = $pname; PID = $procId; Card = $card; Pct = 0.0; VramMB = 0; SharedMB = 0 }
            }
            if ($kind -eq 'Dedicated Usage') { $rows[$key].VramMB += [math]::Round($s.CookedValue / 1MB) }
            else { $rows[$key].SharedMB += [math]::Round($s.CookedValue / 1MB) }
        }
    }

    return $rows.Values | Sort-Object Pct, VramMB -Descending
}

function Show-Gpu([int]$rows = 10) {
    Write-Host ""
    Write-Host "  $B$BLU▍GPU$R"
    Write-Host ""

    foreach ($c in (Get-CimInstance Win32_VideoController)) {
        $label = $c.Name
        $detail = ''
        if ($label -match 'NVIDIA') {
            $smi = "$env:SystemRoot\System32\nvidia-smi.exe"
            if (Test-Path $smi) {
                $q = (& $smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader) 2>$null
                if ($q) { $detail = "  $DIM$q$R" }
            }
        }
        Write-Host ("  {0,-28}{1}" -f $label, $detail)
    }

    $gpuRows = Get-GpuRows
    Write-Host ""
    if (-not $gpuRows -or $gpuRows.Count -eq 0) {
        Write-Host "  ${DIM}no GPU activity right now — both cards idle$R"
        return
    }
    Write-Host ("  $B{0,-22} {1,-7} {2,8} {3,9} {4,9}$R" -f 'PROCESS', 'PID', 'GPU%', 'VRAM', 'SHARED')
    foreach ($g in ($gpuRows | Select-Object -First $rows)) {
        $col = $GRY
        if ($g.Card -eq 'Discrete') { $col = $GRN }
        $cardTag = 'iGPU'
        if ($g.Card -eq 'Discrete') { $cardTag = 'dGPU' }
        $name = $g.Name.PadRight(22)
        $procId = ([string]$g.PID).PadRight(7)
        $pct = ('{0:N1}%' -f $g.Pct).PadLeft(8)
        $vram = (HumanMB $g.VramMB).PadLeft(9)
        $shared = (HumanMB $g.SharedMB).PadLeft(9)
        Write-Host ('  ' + $col + $name + $R + ' ' + $procId + ' ' + $pct + ' ' + $vram + ' ' + $shared + '  ' + $col + $cardTag + $R)
    }
}

# ── dashboard ────────────────────────────────────────────────────────────────
function Show-Dashboard([int]$rows, [string]$sort) {
    $m = Get-MemStat
    $disk = Get-PSDrive -Name C
    $diskFreeGB = [math]::Round($disk.Free / 1GB)
    $diskUsedPct = [math]::Round(($disk.Used / ($disk.Used + $disk.Free)) * 100)

    Write-Host ""
    Write-Host ("  $B$BLU▍SYSTEM$R  $DIM{0}$R" -f (Get-Date -Format 'HH:mm:ss'))
    Write-Host ""

    $h = Heat $m.UsedPct
    Write-Host ("  {0,-7}{1}  {2}{3}%$R used of {4:N1}GB   ${DIM}free {5:N0}MB$R" -f `
            'RAM', (Bar $m.UsedPct 24 $h), $h, $m.UsedPct, ($m.TotalMB / 1024), $m.FreeMB)

    $hc = Heat $m.CommitPct
    Write-Host ("  {0,-7}{1}  {2}{3:N1}GB$R of {4:N1}GB" -f `
            'COMMIT', (Bar $m.CommitPct 24 $hc), $hc, ($m.CommitMB / 1024), ($m.CommitLimitMB / 1024))

    $hd = Heat $diskUsedPct
    Write-Host ("  {0,-7}{1}  {2}{3}%$R used   ${DIM}{4}GB free$R" -f `
            'DISK', (Bar $diskUsedPct 24 $hd), $hd, $diskUsedPct, $diskFreeGB)

    Write-Host ""
    if ($m.UsedPct -ge 88) {
        Write-Host "  $RED$B⚠  CRITICAL$R $RED— quit a top app now:  ram <name>$R"
    }
    elseif ($m.UsedPct -ge 70) {
        Write-Host "  $YEL⚠  tight$R ${DIM}— paging to disk; close what you are not using$R"
    }
    else {
        Write-Host "  $GRN✓  healthy$R"
    }

    $all = Get-AppRows
    if ($sort -eq 'cpu') { $all = $all | Sort-Object CpuPct -Descending }
    else { $all = $all | Sort-Object MemMB -Descending }
    $totalMem = ($all | Measure-Object MemMB -Sum).Sum

    Write-Host ""
    Write-Host ("  $B{0,-3} {1,-24} {2,10} {3,7} {4,4}   {5}$R" -f '#', 'APP', 'MEMORY', 'CPU', 'N', 'SHARE')
    $i = 0
    foreach ($a in ($all | Select-Object -First $rows)) {
        $i++
        $share = 0
        if ($totalMem -gt 0) { $share = [math]::Round(($a.MemMB / $totalMem) * 100) }
        $col = $GRY
        if ($a.MemMB -ge 500) { $col = $RED }
        elseif ($a.MemMB -ge 200) { $col = $YEL }
        Write-Host ("  {0,-3} {1}{2,-24}$R {3,10} {4,6:N1}% {5,4}   {6}" -f `
                $i, $col, $a.Name, (HumanMB $a.MemMB), $a.CpuPct, $a.Count, (Bar $share 12 $col))
    }

    Show-Gpu 8
    Write-Host ""
    Write-Host "  ${DIM}ram -w live · ram -i pick one to quit · ram gpu · ram ports · ram clean$R"
    Write-Host ""
}

# ── actions ──────────────────────────────────────────────────────────────────
function Stop-Match([string]$pattern) {
    $hits = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "*$pattern*" }
    if (-not $hits) { Write-Host "  ${YEL}nothing matching '$pattern'$R"; return }
    foreach ($p in ($hits | Group-Object ProcessName)) {
        if ($PROTECTED -contains $p.Name) { Write-Host "  ${RED}refusing: $($p.Name) is system-critical$R"; continue }
        $mb = [math]::Round((($p.Group | Measure-Object PrivateMemorySize64 -Sum).Sum) / 1MB)
        foreach ($proc in $p.Group) {
            $proc.CloseMainWindow() | Out-Null
        }
        Start-Sleep -Milliseconds 800
        foreach ($proc in $p.Group) {
            if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
        }
        Write-Host "  ${GRN}quit $($p.Name) ($($p.Count) procs, freed ~$mb MB)$R"
    }
}

function Show-Ports([int]$portFilter = 0) {
    $conns = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
    if ($portFilter -gt 0) { $conns = $conns | Where-Object { $_.LocalPort -eq $portFilter } }
    if (-not $conns) {
        if ($portFilter -gt 0) { Write-Host "  ${DIM}nothing listening on $portFilter$R" }
        else { Write-Host "  ${DIM}nothing listening$R" }
        return $null
    }
    Write-Host ""
    Write-Host ("  $B{0,-8} {1,-24} {2,-8} {3}$R" -f 'PORT', 'PROCESS', 'PID', 'ADDRESS')
    $seen = @{}
    foreach ($c in ($conns | Sort-Object LocalPort)) {
        $key = "$($c.LocalPort)|$($c.OwningProcess)"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
        $pname = '(unknown)'
        if ($p) { $pname = $p.ProcessName }
        Write-Host ("  {0,-8} {1,-24} {2,-8} {3}" -f $c.LocalPort, $pname, $c.OwningProcess, $c.LocalAddress)
    }
    Write-Host ""
    return $conns
}

function Free-Port([int]$port) {
    $conns = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
    if (-not $conns) { Write-Host "  ${DIM}port $port is already free$R"; return }
    foreach ($procId in ($conns.OwningProcess | Sort-Object -Unique)) {
        $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        if ($PROTECTED -contains $p.ProcessName) { Write-Host "  ${RED}refusing: port $port is held by $($p.ProcessName), which is system-critical$R"; continue }
        Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        Write-Host "  ${GRN}freed port $port (killed $($p.ProcessName), pid $procId)$R"
    }
}

function Invoke-Clean {
    Write-Host ""
    $before = (Get-MemStat).FreeMB
    # Ask Windows to trim each process working set back to its minimum.
    $sig = @'
using System;
using System.Runtime.InteropServices;
public class Trim {
    [DllImport("psapi.dll")] public static extern int EmptyWorkingSet(IntPtr hProcess);
}
'@
    if (-not ('Trim' -as [type])) { Add-Type -TypeDefinition $sig -ErrorAction SilentlyContinue }
    $trimmed = 0
    foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
        if ($PROTECTED -contains $p.ProcessName) { continue }
        try { [Trim]::EmptyWorkingSet($p.Handle) | Out-Null; $trimmed++ } catch { }
    }
    Write-Host "  ${GRN}trimmed working sets of $trimmed processes$R"

    $freedMB = 0
    foreach ($dir in @($env:TEMP, "$env:LOCALAPPDATA\Temp", "$env:LOCALAPPDATA\Microsoft\Windows\INetCache")) {
        if (-not (Test-Path $dir)) { continue }
        $old = Get-ChildItem $dir -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) }
        foreach ($f in $old) {
            $size = $f.Length
            try { Remove-Item $f.FullName -Force -ErrorAction Stop; $freedMB += $size / 1MB } catch { }
        }
    }
    Write-Host ("  ${GRN}purged {0:N0} MB of temp files older than a day$R" -f $freedMB)
    Start-Sleep -Seconds 1
    $after = (Get-MemStat).FreeMB
    Write-Host ("  ${DIM}free RAM {0:N0} MB -> {1:N0} MB$R" -f $before, $after)
    Write-Host ""
}

function Show-Big([string]$path) {
    if (-not $path) { $path = $env:USERPROFILE }
    Write-Host ""
    Write-Host "  $B$BLU▍LARGEST FILES$R  ${DIM}$path$R"
    Write-Host ""
    Get-ChildItem $path -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object Length -Descending | Select-Object -First 20 | ForEach-Object {
            Write-Host ("  {0,10}  {1}" -f (HumanMB ($_.Length / 1MB)), $_.FullName)
        }
    Write-Host ""
}

function Show-Disk {
    Write-Host ""
    Write-Host "  $B$BLU▍DISK$R"
    Write-Host ""
    foreach ($d in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null })) {
        $total = $d.Used + $d.Free
        if ($total -le 0) { continue }
        $pct = [math]::Round(($d.Used / $total) * 100)
        $h = Heat $pct
        Write-Host ("  {0,-4}{1}  {2}{3}%$R   ${DIM}{4:N1}GB free of {5:N1}GB$R" -f `
                "$($d.Name):", (Bar $pct 24 $h), $h, $pct, ($d.Free / 1GB), ($total / 1GB))
    }
    Write-Host ""
}

function Invoke-Interactive([int]$rows) {
    $all = Get-AppRows | Sort-Object MemMB -Descending | Select-Object -First $rows
    Write-Host ""
    $i = 0
    foreach ($a in $all) {
        $i++
        Write-Host ("  {0,-3} {1,-24} {2,10}  {3} procs" -f $i, $a.Name, (HumanMB $a.MemMB), $a.Count)
    }
    Write-Host ""
    $pick = Read-Host "  number to quit (Enter to cancel)"
    if (-not $pick) { Write-Host "  ${DIM}cancelled$R"; return }
    $n = 0
    if (-not [int]::TryParse($pick, [ref]$n)) { Write-Host "  ${YEL}not a number$R"; return }
    if ($n -lt 1 -or $n -gt $all.Count) { Write-Host "  ${YEL}out of range$R"; return }
    Stop-Match $all[$n - 1].Name
}

# ── argument handling ────────────────────────────────────────────────────────
$rows = 15
$sort = 'mem'
$mode = 'dashboard'
$target = ''

$i = 0
while ($i -lt $Args_.Count) {
    $a = $Args_[$i]
    switch -Regex ($a) {
        '^-w$' { $mode = 'watch' }
        '^-c$' { $sort = 'cpu' }
        '^-i$' { $mode = 'interactive' }
        '^-n$' { $i++; $rows = [int]$Args_[$i] }
        '^(-p|ports)$' { $mode = 'ports' }
        '^port$' { $mode = 'freeport'; $i++; $target = $Args_[$i] }
        '^gpu$' { $mode = 'gpu' }
        '^clean$' { $mode = 'clean' }
        '^big$' { $mode = 'big'; if ($i + 1 -lt $Args_.Count) { $i++; $target = $Args_[$i] } }
        '^disk$' { $mode = 'disk' }
        '^-h$|^--help$|^help$' { $mode = 'help' }
        default { $mode = 'kill'; $target = $a }
    }
    $i++
}

switch ($mode) {
    'dashboard' { Show-Dashboard $rows $sort }
    'watch' {
        try {
            while ($true) {
                Clear-Host
                Show-Dashboard $rows $sort
                Write-Host "  ${DIM}live — Ctrl-C to exit$R"
                Start-Sleep -Seconds 2
            }
        }
        catch [System.Management.Automation.PipelineStoppedException] { }
    }
    'interactive' { Invoke-Interactive $rows }
    'ports' { Show-Ports | Out-Null }
    'freeport' { Free-Port ([int]$target) }
    'gpu' { Show-Gpu 20; Write-Host "" }
    'clean' { Invoke-Clean }
    'big' { Show-Big $target }
    'disk' { Show-Disk }
    'kill' { Stop-Match $target }
    'help' {
        Write-Host ""
        Write-Host "  ram              dashboard: memory, commit, disk, top apps, GPU"
        Write-Host "  ram -w           live refresh every 2s"
        Write-Host "  ram -c           sort by CPU"
        Write-Host "  ram -n 25        show N rows"
        Write-Host "  ram -i           pick a number to quit that app"
        Write-Host "  ram <name>       quit apps matching <name>"
        Write-Host "  ram gpu          which process is on which GPU"
        Write-Host "  ram ports        list listening ports"
        Write-Host "  ram port 3000    free that port"
        Write-Host "  ram clean        trim working sets, purge old temp files"
        Write-Host "  ram big [path]   largest files"
        Write-Host "  ram disk         disk view"
        Write-Host ""
    }
}
