# Chart Lab P2 — implementation notes (DMNC-1501)

Worker notes for the orchestrator. Newest entry on top. Folded into the PR body and
`git rm`'d before merge, per the plan.

---

## Task 0 — test scaffold

`DOSBTSTests/ChartLabMealsTests.swift` added with file ref `C1AB15010000000200A00001` /
build file `C1AB15010000000200A00002`, rows placed immediately after P0's
`ChartLabTests.swift` rows in all four pbxproj sections (PBXBuildFile, PBXFileReference,
the `DOSBTSTests` group, `PBXSourcesBuildPhase`).

P0's own IDs are `C1AB15010000000100A00001/2` — i.e. the plan's `…0200A0000x` pair is the
next one in that family, as intended.
