# helpwatch Discord relay.
# Tails alerts.log and routes each alert to the right webhook based on tier.
# Per-type webhooks: WEBHOOK_HELP, WEBHOOK_DEFENSE, WEBHOOK_PVP, WEBHOOK_PVPRAID
# WEBHOOK_DEFAULT is the fallback when a type-specific one is not set.
$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

$cfgPath = Join-Path $PSScriptRoot "helpwatch_settings.txt"
if (-not (Test-Path $cfgPath)) {
    Write-Host "helpwatch: missing helpwatch_settings.txt"
    Write-Host "Copy helpwatch.cfg.example -> helpwatch_settings.txt and set your webhook URL."
    Write-Host "Then configure everything else in-game via the [HW] button."
    pause
    exit 1
}

# Read all WEBHOOK_* keys from settings
$webhooks = @{}
foreach ($line in (Get-Content $cfgPath)) {
    if ($line -match "^WEBHOOK_([^=]+)=(.+)$") {
        $key = $Matches[1].ToLower()
        $val = $Matches[2].Trim()
        if ($val) { $webhooks[$key] = $val }
    }
    # Legacy single-key support: WEBHOOK= -> default
    if ($line -match "^WEBHOOK=(.+)$") {
        $val = $Matches[1].Trim()
        if ($val -and -not $webhooks.ContainsKey("default")) {
            $webhooks["default"] = $val
        }
    }
}

if ($webhooks.Count -eq 0) {
    Write-Host "helpwatch: no WEBHOOK_DEFAULT or WEBHOOK= found in helpwatch_settings.txt"
    pause
    exit 1
}

$alerts = Join-Path $PSScriptRoot "alerts.log"
if (-not (Test-Path $alerts)) { New-Item -ItemType File -Path $alerts | Out-Null }

Write-Host "helpwatch relay started. Webhooks loaded:"
foreach ($k in $webhooks.Keys) { Write-Host "  $k -> $($webhooks[$k].Substring(0,[Math]::Min(60,$webhooks[$k].Length)))..." }
Write-Host "Watching $alerts  |  Ctrl+C to stop."

# Map log tier labels to webhook keys
$tierMap = @{
    "Help"     = "help"
    "Defense"  = "defense"
    "PvP"      = "pvp"
    "PvP-Raid" = "pvpraid"
}

Get-Content -Path $alerts -Wait -Tail 0 -Encoding UTF8 | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "") { return }

    # Determine which webhook to use: check tier then fall back to default
    $webhook = $null
    if ($line -match "^\[([^\]]+)\]") {
        $tier    = $Matches[1]
        $whKey   = $tierMap[$tier]
        if ($whKey -and $webhooks.ContainsKey($whKey)) {
            $webhook = $webhooks[$whKey]
        }
    }
    if (-not $webhook) {
        $webhook = $webhooks["default"]
    }
    if (-not $webhook) {
        Write-Host ("no webhook for: " + $line)
        return
    }

    $body = @{ content = $line.Substring(0, [Math]::Min(2000, $line.Length)) } | ConvertTo-Json -Compress
    try {
        Invoke-RestMethod -Uri $webhook -Method Post -ContentType "application/json" `
            -Body $body -Headers @{ "User-Agent" = "helpwatch" } | Out-Null
        Write-Host ("sent: " + $line)
    } catch {
        Write-Host ("post failed: " + $_)
    }
}
