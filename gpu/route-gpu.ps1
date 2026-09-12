# route-gpu.ps1 — assign the GPU-drawing apps on this laptop to the NVIDIA MX130.
#
# Windows stores these choices in HKCU\Software\Microsoft\DirectX\UserGpuPreferences,
# one value per app: full exe path for desktop apps, "PackageFamilyName!App" for Store
# apps. GpuPreference=2 means high performance (the MX130); 1 is power saving (Intel).
#
# Re-run this after a WebView2, Brave, Edge or VS Code update: those installers land in
# version-stamped folders, and a changed path silently reverts the app to Intel.
# Never create the key with New-Item -Force — that wipes every existing assignment.

$key = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
if (-not (Test-Path $key)) { New-Item -Path $key | Out-Null }

$targets = [System.Collections.Generic.List[string]]::new()

# Desktop apps at fixed paths
foreach ($p in @(
    "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe",
    "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Windows Media Player\wmplayer.exe",
    "${env:ProgramFiles(x86)}\Windows Media Player\wmplayer.exe"
)) { if (Test-Path $p) { $targets.Add($p) } }

# WebView2 runtime: hosts WhatsApp and every other WebView2 app, in a versioned folder
Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView\Application" -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d+\.' } |
    ForEach-Object { $exe = Join-Path $_.FullName 'msedgewebview2.exe'; if (Test-Path $exe) { $targets.Add($exe) } }

# Store apps, addressed by app user model id
foreach ($id in @(
    '5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App',
    'Microsoft.Windows.Photos_8wekyb3d8bbwe!App',
    'Microsoft.Paint_8wekyb3d8bbwe!App',
    'Microsoft.WindowsCamera_8wekyb3d8bbwe!App'
)) { $targets.Add($id) }

foreach ($t in $targets) {
    New-ItemProperty -Path $key -Name $t -Value 'GpuPreference=2;' -PropertyType String -Force | Out-Null
    Write-Host "routed  $t"
}

Write-Host ""
Write-Host "$($targets.Count) apps assigned to the MX130. Restart each app to apply."
Write-Host "Verify: Task Manager > Details > right-click columns > add 'GPU engine' (expect GPU 1)."
