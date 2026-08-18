# Power BI report

The collector writes two CSVs that form a simple star schema. This page describes the model and the
measures rather than shipping a `.pbix`, so you can drop it into an existing workspace report.

## Model

```
environments-*.csv  (dimension + capacity facts)
        │ EnvironmentId (1)
        │
        │ (*)
resources-*.csv     (per-agent consumption facts)
```

Create the relationship on `EnvironmentId`, single direction, one-to-many from environments to
resources.

If you collect on a schedule, append each run's CSVs into folders and load with **Get Data →
Folder** so history accumulates. `CollectedOn` in the summary JSON and `AsOfDate` on each resource
row give you the time axis.

## Date table

Consumption is a daily snapshot, so a standard date table joined on `AsOfDate` is enough:

```dax
Dates =
CALENDAR ( MIN ( resources[AsOfDate] ), MAX ( resources[AsOfDate] ) )
```

## Measures

```dax
Total Allocated = SUM ( environments[Allocated] )

Total Consumed = SUM ( environments[Consumed] )

Total Available = SUM ( environments[Available] )

Percent Consumed =
DIVIDE ( [Total Consumed], [Total Allocated] )

Agent Consumed = SUM ( resources[Consumed] )

Agent Billable = SUM ( resources[BillableConsumed] )

Agent Non-Billable = SUM ( resources[NonBillableQuantity] )

Non-Billable Share =
DIVIDE ( [Agent Non-Billable], [Agent Consumed] )
```

### Trend and forecast

Simple linear run-rate projection to capacity exhaustion:

```dax
Daily Burn Rate =
VAR Days = DISTINCTCOUNT ( resources[AsOfDate] )
RETURN DIVIDE ( [Agent Consumed], Days )

Days To Exhaustion =
DIVIDE ( [Total Available], [Daily Burn Rate] )

Projected Month End =
[Total Consumed] + ( [Daily Burn Rate] * ( 30 - DAY ( TODAY () ) ) )
```

`Days To Exhaustion` is the number that gets attention in a governance forum — it converts an
abstract credit balance into a date.

### Status

```dax
Capacity Status =
SWITCH (
    TRUE (),
    [Percent Consumed] >= 0.90, "Critical",
    [Percent Consumed] >= 0.75, "Warning",
    "Healthy"
)
```

## Suggested pages

**1. Tenant summary** — cards for Total Allocated, Total Consumed, Percent Consumed and Days To
Exhaustion; a gauge against allocated capacity; consumption trend line.

**2. By environment** — table of environments with allocated, consumed, available, percent and
status, conditionally formatted on `Capacity Status`. Include `IsManagedEnvironment` — it's a useful
governance cut.

**3. By agent** — `ResourceName` ranked by `Agent Consumed`, with billable versus non-billable
split. This is the chargeback view and usually the first thing a platform owner asks for.

**4. Forecast** — burn rate over time with projection, plus days-to-exhaustion by environment.

## Caveats to put on the report

Worth stating on the page itself, because it prevents misreadings:

- Figures are a **daily snapshot** (`consumptionType: Snapshot`), not live. `LastUpdatedOn` was
  around a day behind collection time in testing.
- **Billable consumption is derived** as `Consumed - NonBillableQuantity`; the API does not return it.
- Environment names come from the environments dataset — the resource dataset returns only
  `EnvironmentId`.
- The underlying APIs are undocumented and may change. See [../docs/api-reference.md](../docs/api-reference.md).
