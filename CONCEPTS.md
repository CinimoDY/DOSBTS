# Concepts

Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## Release pipeline

### Always-on changelog
The practice of maintaining one authored changelog as the single source for every release surface: the in-app "What's New" screen and the TestFlight "What to Test" notes are both derived from it, so no per-build release notes are ever written by hand.

The derivation is one-directional — release surfaces are generated from the changelog and never write back to it. A build's notes therefore cannot exist before its changelog block does, which is why Changelog promotion must happen before a deploy, not after.

### Changelog promotion
The release-time step that converts the accumulated unreleased-changes block into a numbered build block (dated with the upload date, not the commit date) and opens a fresh empty unreleased block above it.

Promotion is the gate for shipping: a deploy with nothing to promote means there is nothing user-visible to ship, and the release is aborted rather than published empty. Entries that merged before a promotion but ship only in a later build are moved to the build block that actually ships them.

## Design

- OOUX entity map — `docs/ooux/entity-map.html` (objects, relationships, CTAs, attributes, interface-pattern matrix).

## Alarms and treatment

### Prompt currency
Whether a pending treatment prompt is still about a real or imminent low *now*: the latest reading is fresh enough and still below the low threshold (or, for a predictive prompt, still projected to cross it). The flag that requests the prompt can be hours old by the time a presenter acts on it, so every presenter gates on currency and a non-current flag is cleared rather than shown. The gate only ever suppresses what is already over; a genuine fresh low always presents. See `docs/solutions/logic-errors/persisted-intent-flag-needs-currency-gate-stale-treatment-prompt-20261012.md`.
