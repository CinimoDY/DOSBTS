# Concepts

Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## Release pipeline

### Always-on changelog
The practice of maintaining one authored changelog as the single source for every release surface: the in-app "What's New" screen and the TestFlight "What to Test" notes are both derived from it, so no per-build release notes are ever written by hand.

The derivation is one-directional — release surfaces are generated from the changelog and never write back to it. A build's notes therefore cannot exist before its changelog block does, which is why Changelog promotion must happen before a deploy, not after.

### Changelog promotion
The release-time step that converts the accumulated unreleased-changes block into a numbered build block (dated with the upload date, not the commit date) and opens a fresh empty unreleased block above it.

Promotion is the gate for shipping: a deploy with nothing to promote means there is nothing user-visible to ship, and the release is aborted rather than published empty. Entries that merged before a promotion but ship only in a later build are moved to the build block that actually ships them.
