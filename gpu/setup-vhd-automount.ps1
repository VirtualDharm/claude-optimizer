# setup-vhd-automount.ps1 — RIGHT-CLICK THIS FILE AND CHOOSE "Run as administrator".
#
# D: is not a real partition. It is C:\VirtualDrives\Data.vhdx attached as a virtual
# disk, which is why File Explorer offers to eject it. Windows does not reattach a VHDX
# after a restart, so without this task D: disappears on the next boot and everything
# stored there becomes unreachable until it is mounted again by hand.
#
# This registers a logon task that reattaches it. Run once.

$vhd = 'C:\VirtualDrives\Data.vhdx'
if (-not (Test-Path $vhd)) { Write-Error "not found: $vhd"; exit 1 }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -Command `"Mount-DiskImage -ImagePath '$vhd' -ErrorAction SilentlyContinue`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName 'Mount Data VHDX' -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force `
    -Description 'Attaches C:\VirtualDrives\Data.vhdx as D: at logon' | Out-Null

Write-Host "Registered. D: will now come back after every restart."
Write-Host "Verify: Task Scheduler > Task Scheduler Library > 'Mount Data VHDX'."
