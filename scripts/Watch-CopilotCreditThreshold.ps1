<#
.SYNOPSIS
    Checks Copilot credit consumption against a threshold and raises an alert.

.DESCRIPTION
    Wraps Get-CopilotCreditConsumption.ps1 and evaluates each environment against a
    percentage-of-allocated threshold. Optionally posts an Adaptive Card to a Microsoft
    Teams incoming webhook.

    Intended to run on a schedule. Note that the underlying data is a daily snapshot,
    so a breach may be up to 24 hours old by the time it is detected - set the
    threshold low enough to leave room to act.

.PARAMETER ThresholdPercent
    Percentage of allocated capacity that triggers an alert. Default 80.

.PARAMETER TeamsWebhookUrl
    Optional Teams incoming webhook. Omit to report to the console only.

.PARAMETER EntitlementType
    MCSMessages (default), MCSSessions, or SCMessages.

.PARAMETER TenantId
    Tenant GUID. Defaults to the signed-in Azure CLI tenant.

.PARAMETER FailOnBreach
    Exit with code 1 when any environment breaches. Useful in a pipeline.

.EXAMPLE
    .\Watch-CopilotCreditThreshold.ps1 -ThresholdPercent 75

.EXAMPLE
    .\Watch-CopilotCreditThreshold.ps1 -ThresholdPercent 90 -TeamsWebhookUrl $env:TEAMS_WEBHOOK -FailOnBreach
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 100)]
    [int] $ThresholdPercent = 80,

    [string] $TeamsWebhookUrl,

    [ValidateSet('MCSMessages', 'MCSSessions', 'SCMessages')]
    [string] $EntitlementType = 'MCSMessages',

    [string] $TenantId,

    [switch] $FailOnBreach
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$collector = Join-Path $PSScriptRoot 'Get-CopilotCreditConsumption.ps1'
if (-not (Test-Path -LiteralPath $collector)) {
    throw "Collector not found at $collector"
}

$params = @{
    EntitlementType = $EntitlementType
    PassThru        = $true
}
if ($TenantId) { $params['TenantId'] = $TenantId }

$data = & $collector @params

$breaches = @(
    $data.Environments |
        Where-Object { $null -ne $_.PercentConsumed -and $_.PercentConsumed -ge $ThresholdPercent } |
        Sort-Object PercentConsumed -Descending
)

if ($breaches.Count -eq 0) {
    Write-Host "OK - no environment at or above $ThresholdPercent% of allocated $EntitlementType capacity." -ForegroundColor Green
    exit 0
}

Write-Host ''
Write-Host "$($breaches.Count) environment(s) at or above $ThresholdPercent%:" -ForegroundColor Yellow
$breaches |
    Select-Object EnvironmentName, Allocated, Consumed, Available, PercentConsumed, Status |
    Format-Table -AutoSize |
    Out-String |
    Write-Host

if ($TeamsWebhookUrl) {

    $facts = foreach ($b in $breaches) {
        @{
            title = $b.EnvironmentName
            value = "$($b.PercentConsumed)% - $($b.Consumed) of $($b.Allocated) consumed, $($b.Available) remaining"
        }
    }

    $card = @{
        '@type'      = 'MessageCard'
        '@context'   = 'https://schema.org/extensions'
        summary      = "Copilot credit threshold breach"
        themeColor   = 'D93F0B'
        title        = "Copilot credit consumption at or above $ThresholdPercent%"
        text         = "$($breaches.Count) environment(s) breached the $EntitlementType threshold. " +
                       "Consumption data is a daily snapshot and may lag by up to 24 hours."
        sections     = @(@{ facts = $facts })
    }

    try {
        Invoke-RestMethod -Method Post -Uri $TeamsWebhookUrl `
            -ContentType 'application/json' `
            -Body ($card | ConvertTo-Json -Depth 10) | Out-Null
        Write-Host 'Teams notification sent.' -ForegroundColor Cyan
    }
    catch {
        Write-Warning "Failed to post to Teams: $($_.Exception.Message)"
    }
}

if ($FailOnBreach) { exit 1 }
exit 0
