# helpwatch Discord relay.
# Tails the addon's alerts.log (this folder only - never the game's files)
# and POSTs each new line to the Discord webhook. Keep this window open.
$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

# Webhook URL is set in-game via the [HW] button and saved to helpwatch_settings.txt.
# First-time setup: copy helpwatch.cfg.example to helpwatch_settings.txt and set your webhook.
$cfgPath = Join-Path $PSScriptRoot "helpwatch_settings.txt"
if (-not (Test-Path $cfgPath)) {
    Write-Host "helpwatch: missing helpwatch_settings.txt - copy helpwatch.cfg.example, rename it, and set your Discord webhook URL. Then configure everything else in-game via the [HW] button."
    pause
    exit 1
}
$webhook = (Get-Content $cfgPath | Where-Object { $_ -match "^WEBHOOK=" }) -replace "^WEBHOOK=", ""
if (-not $webhook) { Write-Host "helpwatch: WEBHOOK not set in helpwatch_settings.txt"; pause; exit 1 }
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
