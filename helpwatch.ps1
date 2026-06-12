# helpwatch Discord relay.
# Tails the addon's alerts.log (this folder only - never the game's files)
# and POSTs each new line to the Discord webhook. Keep this window open.
$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

# Set your webhook URL in helpwatch.cfg (copy helpwatch.cfg.example and fill it in)
$cfgPath = Join-Path $PSScriptRoot "helpwatch.cfg"
if (-not (Test-Path $cfgPath)) {
    Write-Host "helpwatch: missing helpwatch.cfg - copy helpwatch.cfg.example and set your webhook URL."
    exit 1
}
$webhook = (Get-Content $cfgPath | Where-Object { $_ -match "^WEBHOOK=" }) -replace "^WEBHOOK=", ""
if (-not $webhook) { Write-Host "helpwatch: WEBHOOK not set in helpwatch.cfg"; exit 1 }
$alerts  = Join-Path $PSScriptRoot "alerts.log"

if (-not (Test-Path $alerts)) { New-Item -ItemType File -Path $alerts | Out-Null }
Write-Host "helpwatch: relaying $alerts -> Discord. Keep this window open. Ctrl+C to stop."

Get-Content -Path $alerts -Wait -Tail 0 -Encoding UTF8 | ForEach-Object {
    $line = $_.Trim()
    if ($line -ne "") {
        $body = @{ content = $line.Substring(0, [Math]::Min(2000, $line.Length)) } | ConvertTo-Json -Compress
        try {
            Invoke-RestMethod -Uri $webhook -Method Post -ContentType "application/json" `
                -Body $body -Headers @{ "User-Agent" = "helpwatch" } | Out-Null
            Write-Host ("sent: " + $line)
        } catch {
            Write-Host ("post failed: " + $_)
        }
    }
}
