# LibreTV Launcher
# Start local service -> open Edge app window(s) -> stop service when ALL windows closed
$ErrorActionPreference = 'Stop'

$AppDir   = 'C:\Hack APP\LibreTV'
$Port     = 8080
$Url      = "http://localhost:$Port"
$LogFile  = Join-Path $AppDir 'server.log'
$EdgeCandidates = @(
  'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
  'C:\Program Files\Microsoft\Edge\Application\msedge.exe'
)

# ---------- Win32 window enumeration (reliable multi-window detection) ----------
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WinEnum {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
}
'@ -ErrorAction SilentlyContinue

$script:winList = New-Object System.Collections.ArrayList
$script:winCallback = [WinEnum+EnumWindowsProc]{
  param($h, $l)
  if ([WinEnum]::IsWindowVisible($h)) {
    $len = [WinEnum]::GetWindowTextLength($h)
    if ($len -gt 0) {
      $sb = New-Object System.Text.StringBuilder ($len + 1)
      [WinEnum]::GetWindowText($h, $sb, $sb.Capacity) | Out-Null
      $t = $sb.ToString()
      if ($t -match 'LibreTV') {
        $p = 0
        [WinEnum]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
        $script:winList.Add([pscustomobject]@{ Handle = $h; Title = $t; Pid = $p }) | Out-Null
      }
    }
  }
  return $true
}

function Get-LibreTVWindows {
  $script:winList.Clear() | Out-Null
  [WinEnum]::EnumWindows($script:winCallback, [IntPtr]::Zero) | Out-Null
  return @($script:winList)
}

$Edge = $EdgeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Edge) {
  Write-Host 'Microsoft Edge not found.' -ForegroundColor Red
  Read-Host 'Press Enter to exit'
  exit 1
}

# ---------- 1. Ensure service is running ----------
$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if (-not $listener) {
  Write-Host 'Starting LibreTV service...' -ForegroundColor Cyan
  $node = (Get-Command node).Source
  Start-Process -FilePath $node `
    -ArgumentList 'node_modules\next\dist\bin\next', 'start', '-p', "$Port" `
    -WorkingDirectory $AppDir `
    -WindowStyle Hidden `
    -RedirectStandardOutput $LogFile `
    -RedirectStandardError "$LogFile.err"
  # Wait until ready (max 120s)
  $ready = $false
  for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep -Seconds 1
    try {
      $r = Invoke-WebRequest -Uri "$Url/api/status" -TimeoutSec 3 -UseBasicParsing
      if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch { }
  }
  if (-not $ready) {
    Write-Host 'Service failed to start. Check server.log' -ForegroundColor Red
    Read-Host 'Press Enter to exit'
    exit 1
  }
}
Write-Host 'LibreTV service is ready.' -ForegroundColor Green

# ---------- 2. Open Edge app window ----------
Start-Process -FilePath $Edge -ArgumentList "--app=$Url", '--window-size=1360,900'

# ---------- 3. Wait until ALL LibreTV windows are closed ----------
Write-Host 'Waiting for the LibreTV window to appear...' -ForegroundColor Cyan
$appeared = $false
for ($i = 0; $i -lt 120; $i++) {
  if ((Get-LibreTVWindows).Count -gt 0) { $appeared = $true; break }
  Start-Sleep -Seconds 1
}
if (-not $appeared) {
  Write-Host 'No LibreTV window detected. Check Edge or the service log.' -ForegroundColor Red
} else {
  Write-Host 'LibreTV window opened. The service will stop after ALL LibreTV windows are closed.' -ForegroundColor Green
  while ((Get-LibreTVWindows).Count -gt 0) {
    Start-Sleep -Seconds 2
  }
}

# ---------- 4. Stop service ----------
$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($listener) {
  $pidToStop = $listener | Select-Object -First 1 -ExpandProperty OwningProcess
  Stop-Process -Id $pidToStop -Force -ErrorAction SilentlyContinue
  Write-Host 'LibreTV service stopped.' -ForegroundColor Green
}
