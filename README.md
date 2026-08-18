# Copilot Credit Observability

Programmatic visibility over Copilot Studio credit consumption across a Power Platform tenant —
by environment and by agent — with CSV export, threshold alerting and a Power BI model.

Built on the undocumented licensing endpoints the Power Platform admin centre uses itself,
**verified against a live tenant**.

---

## The problem

Organisations are deploying agents faster than they can account for them, and nobody can answer the
question that decides whether the programme continues:

> *"What is this going to cost at scale, and which agent is driving it?"*

The admin centre shows Copilot credit capacity, but only as a screen someone has to remember to
open. There is **no supported API** behind it, so consumption cannot be trended, forecast, alerted
on, or charged back to the business unit that caused it.

The practical consequences are consistent:

- Cost becomes visible when **capacity runs out**, not before.
- Nobody knows which agent is expensive, so nobody can optimise the right one.
- There is no chargeback, so agent cost sits in a central bucket and every team treats it as free.
- Finance asks for a forecast and the honest answer is a screenshot.

Agent rollout ends up governed by surprise rather than by plan.

## What this solves

| Problem | How this repo solves it |
|---|---|
| No supported API for credit consumption | Documents the working licensing endpoints, verified live |
| Wrong token audience returns 401 | Identifies the correct audience — the most common failure |
| Consumption only visible in a portal screen | Collector script exporting CSV/JSON for history |
| Can't tell which agent is expensive | Per-agent consumption with resource names |
| Billable vs non-billable not reported | Derived, since the API returns only the components |
| Capacity exhaustion discovered too late | Threshold checks with Teams alerting |
| No forecast | Power BI model with burn rate and days-to-exhaustion |
| Private endpoints may change | Re-capture guide plus defensive parsing |

---

## Quick start

```powershell
az login

# Console summary
.\scripts\Get-CopilotCreditConsumption.ps1

# Export for reporting
.\scripts\Get-CopilotCreditConsumption.ps1 -OutputPath .\out

# Alert if any environment is at or above 80%
.\scripts\Watch-CopilotCreditThreshold.ps1 -ThresholdPercent 80 -TeamsWebhookUrl $env:TEAMS_WEBHOOK
```

Output:

```
Retrieving environment capacity for MCSMessages...
  4 environment(s).
Retrieving per-agent consumption...
  765 resource record(s).

Allocated 25000 | Consumed 0 | Available 25000
0% of allocated capacity consumed.
```

**Requires:** Azure CLI or Az PowerShell, and a Power Platform administrator role.
All calls are read-only `GET`s.

---

## How it works

```
   az login / Connect-AzAccount
              │
              ▼
   Token for audience
   licensing.powerplatform.microsoft.com          ← not api.powerplatform.com
              │
    ┌─────────┴──────────┐
    ▼                    ▼
 Environment          Resource
 capacity             consumption
 (allocated,          (per agent,
  consumed,            billable vs
  available)           non-billable)
    │                    │
    └─────────┬──────────┘
              ▼
      CSV + JSON export
              │
    ┌─────────┴──────────┐
    ▼                    ▼
 Power BI            Threshold alert
 (trend, forecast,   (Teams webhook)
  chargeback)
```

Full endpoint documentation, schemas and field meanings:
**[docs/api-reference.md](docs/api-reference.md)**

---

## Contents

| Path | Purpose |
|---|---|
| `scripts/Get-CopilotCreditConsumption.ps1` | Collector — environment and agent grain, CSV/JSON export |
| `scripts/Watch-CopilotCreditThreshold.ps1` | Threshold evaluation with optional Teams alerting |
| `docs/api-reference.md` | Verified endpoint reference, schemas, negative findings |
| `docs/devtools-capture.md` | Re-capturing endpoints if they move |
| `powerbi/README.md` | Star schema, DAX measures, suggested report pages |

---

## What is and isn't verified

**Verified against a live tenant (18 August 2026)** — 4 environments, 765 agent records returned:

- Token audience must be `https://licensing.powerplatform.microsoft.com`
- Environment capacity endpoint, with the full response schema documented
- Per-agent resource endpoint, including its array-wrapped response shape
- Entitlement types `MCSMessages`, `MCSSessions`, `SCMessages` and `PowerAutomateProcess` all accepted
- Unused entitlement types return `200` with an empty array, not `404`
- The downloads endpoint returns report availability metadata
- Both scripts run end-to-end

**Verified negative** — worth knowing because it costs time to establish:

- `api.powerplatform.com/analytics/.../copilotInsights/...` returns **404** for both `PowerApps` and
  `CopilotStudio`, despite being recoverable from the admin centre's shipped JavaScript. Do not
  build on it.

**Not verified:**

- Behaviour in a tenant with **non-zero consumption**. The test tenant reported 0 consumed against
  25,000 allocated, so field population under real load — particularly `NonBillableQuantity` and
  pay-as-you-go values — is untested. **This is the most valuable contribution someone can make**;
  see the *Verification result* issue template.
- Report generation and retrieval calls behind the downloads endpoint.
- Paging behaviour beyond `pageSize=5000`.
- `includeFields=users` response shape.

---

## Limitations

- **Undocumented APIs.** They can change without notice. If you get a `404`, the path moved — see
  [docs/devtools-capture.md](docs/devtools-capture.md).
- **Daily snapshot, not live.** `consumptionType` is `Snapshot` and `lastUpdatedOn` ran about a day
  behind collection time. Set alert thresholds with enough headroom to react.
- **Billable consumption is derived,** not returned.
- **No supported alternative exists.** Microsoft documents the admin centre
  [experience](https://learn.microsoft.com/power-platform/admin/manage-copilot-studio-messages-capacity)
  but not the API. Migrate if one ships.

---

## Contributing

Verification results from tenants with real consumption are the most useful contribution here — see
[CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

MIT — see [LICENSE](LICENSE).
