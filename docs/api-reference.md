# API reference

Microsoft does not publish a supported REST API for Copilot Studio credit consumption. The
endpoints below are **undocumented** and are the ones the Power Platform admin centre calls itself.
They work today and can change without notice.

Everything on this page was **verified against a live tenant on 18 August 2026** unless explicitly
marked otherwise.

---

## Authentication

| | |
|---|---|
| **Audience / resource** | `https://licensing.powerplatform.microsoft.com` |
| **Method** | Bearer token, `Authorization: Bearer <token>` |
| **Role** | Power Platform administrator |

> **The audience is the trap.** Most guidance points at `https://api.powerplatform.com`, which is
> the correct audience for the *documented* Power Platform APIs. A token for that audience returns
> **401** against the licensing service. It must be `licensing.powerplatform.microsoft.com`.

```powershell
$tenantId = az account show --query tenantId -o tsv
$token = az account get-access-token `
    --resource "https://licensing.powerplatform.microsoft.com" `
    --query accessToken -o tsv

$headers = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
```

Az PowerShell works equally well:

```powershell
$token = (Get-AzAccessToken -ResourceUrl 'https://licensing.powerplatform.microsoft.com').Token
```

---

## Entitlement types

Passed as a path segment. All four were accepted; only types in use return rows.

| Type | Meaning | Verified |
|---|---|---|
| `MCSMessages` | Copilot Studio messages / credits | ✅ returned data |
| `MCSSessions` | Copilot Studio sessions | ✅ accepted, empty in test tenant |
| `SCMessages` | Service Copilot messages | ✅ accepted, empty in test tenant |
| `PowerAutomateProcess` | Power Automate process capacity | ✅ accepted, empty in test tenant |

An unused entitlement type returns `200` with an empty `value` array - not a `404`. Absence of rows
means no capacity of that type, not a bad request.

---

## 1. Environment-level capacity

```http
GET https://licensing.powerplatform.microsoft.com/v2.0/tenants/{tenantId}/environments/entitlementConsumptions/{entitlementType}
```

Returns one object per environment under `value[]`.

### Response

```jsonc
{
  "value": [
    {
      "environmentId": "...",
      "environmentName": "...",
      "environmentType": "Production",
      "location": "...",
      "isManagedEnvironment": false,
      "scenario": "...",
      "disasterRecoveryState": "...",
      "entitlementId": "...",
      "cleanupOpportunitySize": 0,
      "recommendationCount": 0,
      "addons": [],
      "permissions": [],
      "productCategories": [],
      "entitlement": {
        "unit": "Count",
        "capacity": {
          "allocated":         { "value": 25000.0, "autoAllocated": 0.0 },
          "consumed":          { "value": 0.0,
                                 "consumptionType": "Snapshot",
                                 "lastUpdatedOn": "2026-08-17T00:00:00Z",
                                 "writeOff": 0.0 },
          "availableQuantity": 25000.0,
          "status": "WithinCapacity",
          "enforcementRules": []
        },
        "payGo": {
          "entitled": { "value": 0.0 },
          "consumed": { "value": 0.0, "consumptionType": "NotSpecified", "writeOff": 0.0 }
        }
      }
    }
  ]
}
```

### Fields that matter

| Path | Meaning |
|---|---|
| `entitlement.capacity.allocated.value` | Credits allocated to the environment |
| `entitlement.capacity.consumed.value` | Credits consumed |
| `entitlement.capacity.availableQuantity` | Remaining |
| `entitlement.capacity.consumed.writeOff` | Credits written off, not charged |
| `entitlement.capacity.status` | e.g. `WithinCapacity` |
| `entitlement.capacity.consumed.lastUpdatedOn` | **Freshness - see the latency note below** |
| `entitlement.payGo.consumed.value` | Pay-as-you-go overage consumption |

> `consumptionType` is `Snapshot`. The figure is a point-in-time reading, not a live counter, and
> `lastUpdatedOn` was **roughly a day behind** the collection time in testing. Treat this as
> day-grain data. Alerting on it needs headroom - a threshold breach is discovered up to 24 hours
> after it happens.

---

## 2. Resource-level (per-agent) consumption

```http
GET https://licensing.powerplatform.microsoft.com/v2.0/tenants/{tenantId}/entitlements/{entitlementType}/resources
      ?fromDate=2026-07-01
      &toDate=2026-08-18
      &pageSize=5000
      &includeFields=users
```

| Parameter | Notes |
|---|---|
| `fromDate` / `toDate` | `yyyy-MM-dd` |
| `pageSize` | 5000 used successfully |
| `includeFields=users` | Optional, adds user detail |

### Response shape

The response is an **array**, and the collection sits on the first element - not a plain `value`
property. This asymmetry with endpoint 1 is easy to get wrong:

```jsonc
[
  {
    "resources": [
      {
        "environmentId": "...",
        "resourceId": "...",
        "consumed": 0.0,
        "unit": "Messages",
        "asOfDate": "2026-08-18T00:31:49.007",
        "metadata": {
          "ResourceName": "...",
          "NonBillableQuantity": 0
        }
      }
    ]
  }
]
```

| Field | Meaning |
|---|---|
| `resourceId` | The agent |
| `metadata.ResourceName` | Display name - the only human-readable identifier |
| `consumed` | Total credits consumed in the window |
| `metadata.NonBillableQuantity` | Portion not charged |
| `unit` | `Messages` |
| `asOfDate` | Timestamp of the reading |

**Billable consumption is not returned** - derive it as
`consumed - NonBillableQuantity`. This distinction is the single most useful number for
chargeback, and it only exists once you compute it.

`environmentId` is returned but the environment *name* is not. Join to endpoint 1 to resolve it.

---

## 3. Downloadable tenant report

```http
GET https://licensing.powerplatform.microsoft.com/v1.0/tenants/{tenantId}/Downloads/getAll/EntitlementConsumptionTenantDetailsReport
```

Note this one is **`v1.0`**, not `v2.0`.

```json
{ "reportLifetime": "...", "couldGenerateNewReport": true }
```

Returns report availability metadata rather than the report itself. Useful for checking whether a
fresh export can be generated; the generation and retrieval calls have **not** been traced.

---

## Negative findings

Publishing these because they cost time to establish.

### `copilotInsights` analytics family returns 404

The admin centre's `CopilotHub` bundle contains a call to:

```http
GET https://api.powerplatform.com/analytics/tenants/{tenantId}/copilotInsights/resourceType/PowerApps/overall?api-version=1
```

That path is recoverable from the shipped JavaScript, so it is genuinely used by the product. But
when called directly with a valid `api.powerplatform.com` token it returned **404** - for both
`PowerApps` and `CopilotStudio` resource types.

Do not build on this family. The `licensing.powerplatform.microsoft.com` endpoints above are the
ones that actually answer.

### There is no supported alternative

Microsoft documents the admin centre *experience* for Copilot credit capacity
([Learn](https://learn.microsoft.com/power-platform/admin/manage-copilot-studio-messages-capacity))
but publishes no REST endpoint behind it. If a supported API ships, migrate to it.

---

## Stability and risk

These are private endpoints. Reasonable precautions:
- **Treat schema as untrusted.** The collector reads defensively and tolerates missing properties.
- **Version-check on failure.** A `404` means the path moved - re-capture it (see
  [devtools-capture.md](devtools-capture.md)).
- **Read-only.** Every call here is a `GET`. Nothing in this repo writes to the tenant.
- **Don't hardcode the tenant.** Infer it from the signed-in context.
