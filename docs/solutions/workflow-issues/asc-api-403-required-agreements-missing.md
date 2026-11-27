---
title: "App Store Connect API 403 REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED — a pending App Store Connect declaration, not only the developer.apple.com licence"
date: 2026-11-27
category: workflow-issues
module: deploy
problem_type: workflow_issue
component: deploy
severity: medium
applies_when:
  - "Any App Store Connect API call (scripts/asc-jwt.py + curl, deploy.sh pre-flight, scripts/asc-release-notes.sh) returns HTTP 403"
  - "The 403 body's error code is FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED"
  - "Apple has just published a new Program License Agreement or compliance declaration"
tags:
  - deploy
  - testflight
  - app-store-connect
  - asc-api
  - agreements
---

# ASC API 403: required agreements missing or expired

## Context

Before Build 140 (2026-11-27), every App Store Connect API call failed with
HTTP 403 and the error code `FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED`.
The failing call was `GET /v1/builds?filter[app]=6759833209`.

Two things broke without making the deploy fail:

- **`deploy.sh` pre-flight.** On any failed query it prints `WARN: could not read the latest TestFlight build (creds/network?); proceeding without the guard.` and then archives anyway. This switches off the build-number drift guard (see `asc-auto-managed-build-numbers-drift-20260621.md`).
- **`scripts/asc-release-notes.sh`.** It treats 401 and 403 as fatal (`check ASC credentials/permissions`). The upload succeeds, but the build gets no "What to Test" notes.

The key and the JWT were not the problem.

## What fixed it

1. **The developer.apple.com Program License Agreement was not enough.** After it was accepted, two rechecks still returned the same 403.
2. **The 403 cleared after a second agreement was accepted in App Store Connect.** This was the EU Digital Services Act trader-status declaration, answered "not a trader". The next `/v1/builds` call returned 200. Dom only reported accepting "another agreement" there, so it is not certain that this one declaration was the one blocking the API.

Background on "trader": under the DSA, a trader acts for purposes of their trade, business or profession. That includes digital services, not only physical goods. A free, unmonetised app published by an individual fits "not a trader". Revisit the answer if DOSBTS ever charges money, shows ads, or ships under a company.

## Guidance

When the ASC API returns this 403:

1. **Check App Store Connect, not only developer.apple.com.** Look at Business → Agreements, and at any banner asking for a compliance declaration (trader status, export compliance and similar).
2. **Recheck before deploying.** Run:
   ```bash
   J="$(python3 scripts/asc-jwt.py "$HOME/.private_keys/AuthKey_2CY3778TFY.p8" 2CY3778TFY 69a6de7d-b4e1-47e3-e053-5b8c7c11a4d1 300)"
   curl -sS -H "Authorization: Bearer $J" "https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=6759833209&sort=-uploadedDate&limit=1"
   ```
   Run `./deploy.sh` only once this returns a build. If you deploy while the 403 persists, the pre-flight guard is skipped and the notes push fails.
3. **Allow for propagation.** Recheck a few minutes after accepting.

## Prevention (proposed, not written)

The pre-flight in `deploy.sh` could detect `REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED` in the response and abort with a pointer to App Store Connect → Business. Today it degrades to a WARN and proceeds. This would be a change to the deploy script. The capture step did not make it.
