@echo off
rem Manually stop LibreTV service (backup)
powershell.exe -NoProfile -Command "$l = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue; if ($l) { Stop-Process -Id $l[0].OwningProcess -Force; Write-Host 'LibreTV service stopped.' } else { Write-Host 'Service is not running.' }"
