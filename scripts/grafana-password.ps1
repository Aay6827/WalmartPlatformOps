# Kept for compatibility: the password now goes to the clipboard instead of the terminal.
#   .\scripts\grafana-password.ps1          (same as .\scripts\show-credentials.ps1 -Service grafana)
& (Join-Path $PSScriptRoot "show-credentials.ps1") -Service grafana @args