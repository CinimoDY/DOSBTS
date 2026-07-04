# Themes — DMNC-1317

## Labeling a silent feature

The tight-control streak celebration (DMNC-772) fires for 2 continuous hours in the 80–120 mg/dL band. But the only place that stated the band was the toast itself — which you only see after earning one. The statistics card said "2h streaks in range" with no bound, and the celebrations settings toggle footer also omitted it. Dominic discovered this on 2026-07-04 when he concluded the streak was broken (he assumed it used the alarm range 80–180).

Fix was minimal: unit-aware band strings in two UI surfaces + a fixed-by-design comment on the constants so a future session doesn't "helpfully" make the band configurable.

## Unit awareness

The band constants (80, 120 mg/dL) are referenced from `TightControlConfig.default` and formatted via `Int.asGlucose(glucoseUnit:)` — the same path used throughout the statistics view — so mmol/L users see 4.4–6.7.
