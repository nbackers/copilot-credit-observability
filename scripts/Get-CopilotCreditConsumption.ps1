<#
.SYNOPSIS
    Collects Copilot Studio credit consumption for a Power Platform tenant.

.DESCRIPTION
    Retrieves entitlement consumption from the Power Platform licensing service - the same data the Power Platform admin centre shows under
    Licensing > Copilot Studio - at two grains:

      Environment level : allocated, consumed, available and pay-as-you-go capacity
      Resource level    : consumption per agent, including non-billable quantity

    Microsoft does not publish a supported REST API for this data. These endpoints
    are undocumented and used by the admin centre itself, so they can change
    without notice. See docs/api-reference.md for verification status.

.PARAMETER TenantId
    Tenant GUID. Defaults to the signed-in Azure CLI tenant.

.PARAMETER EntitlementType
    MCSMessages (Copilot credits), MCSSessions, or SCMessages.

.PARAMETER FromDate
    Start of the resource-level window. Defaults to 30 days ago.

.PARAMETER ToDate
    End of the resource-level window. Defaults to today.

.PARAMETER OutputPath
    Directory for CSV and JSON output. Created if missing. Omit to return objects only.

.PARAMETER IncludeUsers
    Adds user detail to the resource-level query.

.PARAMETER PassThru
    Emits the result object to the pipeline.

.EXAMPLE
    .\Get-CopilotCreditConsumption.ps1 -OutputPath .\out

.EXAMPLE
    .\Get-CopilotCreditConsumption.ps1 -FromDate 2026-07-01 -ToDate 2026-07-31 -PassThru

.NOTES
    Requires Azure CLI (az login) or the Az PowerShell module, with a Power Platform
    administrator role. All calls are read-only GETs.
#>
[CmdletBinding()]
param(
    [string] $TenantId,

    [ValidateSet('MCSMessages', 'MCSSessions', 'SCMessages')]
    [string] $EntitlementType = 'MCSMessages',

    [datetime] $FromDate = (Get-Date).AddDays(-30),

    [datetime] $ToDate = (Get-Date),

    [string] $OutputPath,

    [switch] $IncludeUsers,

    [switch] $PassThru
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$LicensingHost = 'https://licensing.powerplatform.microsoft.com'

function Get-LicensingToken {
    <#
        The token audience is the licensing service, NOT https://api.powerplatform.com.
        Using the wrong audience returns 401.
    #>
    [CmdletBinding()]
    param([string] $Tenant)

    if (Get-Command az -ErrorAction SilentlyContinue) {
        Write-Verbose 'Acquiring token via Azure CLI.'
        $argList = @('account', 'get-access-token', '--resource', $LicensingHost, '--query', 'accessToken', '-o', 'tsv')
        if ($Tenant) { $argList += @('--tenant', $Tenant) }

        $token = & az @argList 2>$null
        if ($LASTEXITCODE -eq 0 -and $token) { return $token.Trim() }
        Write-Verbose 'Azure CLI token acquisition failed, trying Az PowerShell.'
    }

    if (Get-Command Get-AzAccessToken -ErrorAction SilentlyContinue) {
        Write-Verbose 'Acquiring token via Az PowerShell.'
        $t = Get-AzAccessToken -ResourceUrl $LicensingHost
        if ($t.Token -is [System.Security.SecureString]) {
            return [System.Net.NetworkCredential]::new('', $t.Token).Password
        }
        return $t.Token
    }

    throw "Could not acquire a token. Run 'az login' or 'Connect-AzAccount' first."
}

function Invoke-LicensingApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [Parameter(Mandatory)] [hashtable] $Headers,
        [string] $Description = 'request'
    )

    try {
        return Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -ErrorAction Stop
    }
    catch {
        $status = $null
        if ($_.Exception.PSObject.Properties.Name -contains 'Response' -and $_.Exception.Response) {
            $status = $_.Exception.Response.StatusCode.value__
        }

        switch ($status) {
            401 { throw "401 Unauthorized on $Description. The token audience must be $LicensingHost." }
            403 { throw "403 Forbidden on $Description. A Power Platform administrator role is required." }
            404 { throw "404 Not Found on $Description. The endpoint may have changed - see docs/devtools-capture.md." }
            default { throw "Failed $Description ($status): $($_.Exception.Message)" }
        }
    }
}

# ---------------------------------------------------------------------------

if (-not $TenantId) {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'TenantId not supplied and Azure CLI is unavailable to infer it.'
    }
    $TenantId = (& az account show --query tenantId -o tsv 2>$null)
    if (-not $TenantId) { throw "Could not determine tenant. Pass -TenantId or run 'az login'." }
    $TenantId = $TenantId.Trim()
}

Write-Verbose "Tenant: $TenantId"
Write-Verbose "Entitlement: $EntitlementType"

$headers = @{
    Authorization = "Bearer $(Get-LicensingToken -Tenant $TenantId)"
    Accept        = 'application/json'
}

# --- Environment-level capacity -------------------------------------------

Write-Host "Retrieving environment capacity for $EntitlementType..." -ForegroundColor Cyan

$envUri = "$LicensingHost/v2.0/tenants/$TenantId/environments/entitlementConsumptions/$EntitlementType"
$envResponse = Invoke-LicensingApi -Uri $envUri -Headers $headers -Description 'environment consumption'

$environments = foreach ($e in $envResponse.value) {

    $capacity = $e.entitlement.capacity
    $allocated = [double] $capacity.allocated.value
    $consumed = [double] $capacity.consumed.value

    [pscustomobject]@{
        EnvironmentId        = $e.environmentId
        EnvironmentName      = $e.environmentName
        EnvironmentType      = $e.environmentType
        Location             = $e.location
        IsManagedEnvironment = $e.isManagedEnvironment
        EntitlementType      = $EntitlementType
        Unit                 = $e.entitlement.unit
        Allocated            = $allocated
        AutoAllocated        = [double] $capacity.allocated.autoAllocated
        Consumed             = $consumed
        WriteOff             = [double] $capacity.consumed.writeOff
        Available            = [double] $capacity.availableQuantity
        # Guard against divide-by-zero when no capacity is allocated.
        PercentConsumed      = if ($allocated -gt 0) { [math]::Round(($consumed / $allocated) * 100, 2) } else { $null }
        Status               = $capacity.status
        ConsumptionType      = $capacity.consumed.consumptionType
        LastUpdatedOn        = $capacity.consumed.lastUpdatedOn
        PayGoEntitled        = [double] $e.entitlement.payGo.entitled.value
        PayGoConsumed        = [double] $e.entitlement.payGo.consumed.value
    }
}

Write-Host "  $($environments.Count) environment(s)." -ForegroundColor Gray

# --- Resource (agent) level consumption -----------------------------------

Write-Host "Retrieving per-agent consumption..." -ForegroundColor Cyan

$from = $FromDate.ToString('yyyy-MM-dd')
$to = $ToDate.ToString('yyyy-MM-dd')

$resourceUri = "$LicensingHost/v2.0/tenants/$TenantId/entitlements/$EntitlementType/resources" +
               "?fromDate=$from&toDate=$to&pageSize=5000"
if ($IncludeUsers) { $resourceUri += '&includeFields=users' }

$resourceResponse = Invoke-LicensingApi -Uri $resourceUri -Headers $headers -Description 'resource consumption'

# The response is an array whose first element carries the resources collection.
$rawResources = @()
foreach ($block in $resourceResponse) {
    if ($block.PSObject.Properties.Name -contains 'resources' -and $block.resources) {
        $rawResources += $block.resources
    }
}

$envLookup = @{}
foreach ($e in $environments) { $envLookup[$e.EnvironmentId] = $e.EnvironmentName }

$resources = foreach ($r in $rawResources) {

    $name = $null
    $nonBillable = 0
    if ($r.PSObject.Properties.Name -contains 'metadata' -and $r.metadata) {
        if ($r.metadata.PSObject.Properties.Name -contains 'ResourceName') { $name = $r.metadata.ResourceName }
        if ($r.metadata.PSObject.Properties.Name -contains 'NonBillableQuantity') { $nonBillable = [double] $r.metadata.NonBillableQuantity }
    }

    $consumed = [double] $r.consumed

    [pscustomobject]@{
        EnvironmentId       = $r.environmentId
        EnvironmentName     = if ($envLookup.ContainsKey($r.environmentId)) { $envLookup[$r.environmentId] } else { $null }
        ResourceId          = $r.resourceId
        ResourceName        = $name
        EntitlementType     = $EntitlementType
        Consumed            = $consumed
        NonBillableQuantity = $nonBillable
        # Non-billable credits still consume capacity but are not charged.
        BillableConsumed    = [math]::Max(0, $consumed - $nonBillable)
        Unit                = $r.unit
        AsOfDate            = $r.asOfDate
        FromDate            = $from
        ToDate              = $to
    }
}

Write-Host "  $($resources.Count) resource record(s)." -ForegroundColor Gray

# --- Summary ---------------------------------------------------------------

$totalAllocated = ($environments | Measure-Object -Property Allocated -Sum).Sum
$totalConsumed = ($environments | Measure-Object -Property Consumed -Sum).Sum

$summary = [pscustomobject]@{
    TenantId         = $TenantId
    EntitlementType  = $EntitlementType
    CollectedOn      = (Get-Date).ToString('o')
    FromDate         = $from
    ToDate           = $to
    EnvironmentCount = $environments.Count
    ResourceCount    = $resources.Count
    TotalAllocated   = $totalAllocated
    TotalConsumed    = $totalConsumed
    TotalAvailable   = ($environments | Measure-Object -Property Available -Sum).Sum
    PercentConsumed  = if ($totalAllocated -gt 0) { [math]::Round(($totalConsumed / $totalAllocated) * 100, 2) } else { $null }
}

Write-Host ''
Write-Host "Allocated $($summary.TotalAllocated) | Consumed $($summary.TotalConsumed) | Available $($summary.TotalAvailable)" -ForegroundColor Green
if ($null -ne $summary.PercentConsumed) {
    Write-Host "$($summary.PercentConsumed)% of allocated capacity consumed." -ForegroundColor Green
}
Write-Host ''

# --- Output ----------------------------------------------------------------

if ($OutputPath) {
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    $envCsv = Join-Path $OutputPath "environments-$EntitlementType-$stamp.csv"
    $resCsv = Join-Path $OutputPath "resources-$EntitlementType-$stamp.csv"
    $sumJson = Join-Path $OutputPath "summary-$EntitlementType-$stamp.json"

    $environments | Export-Csv -Path $envCsv -NoTypeInformation -Encoding UTF8
    if ($resources) { $resources | Export-Csv -Path $resCsv -NoTypeInformation -Encoding UTF8 }
    $summary | ConvertTo-Json -Depth 5 | Set-Content -Path $sumJson -Encoding UTF8

    Write-Host "Written to $OutputPath" -ForegroundColor Cyan
}

if ($PassThru -or -not $OutputPath) {
    [pscustomobject]@{
        Summary      = $summary
        Environments = $environments
        Resources    = $resources
    }
}
