# PLAN: DOSBTS showcase website (dosbts-web) — v1 + Heritage section

**Linear:** DMNC-1120 (Todo → In Progress). Related: DMNC-972 (upstream etiquette — heritage section partially addresses it; leave the issue open).
**Rank:** 3 of 6. Effort: M (~1 day incl. deploy). Independent of the app plans — can run in parallel.
**Repo: this plan is EXECUTED in `/Users/doke/extracode/dosbts-web`** (sibling repo, remote `git@github.com:CinimoDY/dosbts-web.git`), not in the DOSBTS app repo. The app repo is a read-only content source.

## Goal

Ship v1 of the build-in-public showcase site at `dosbts.dmnc.tech`: a single rich Astro landing page on Cloudflare Pages with a Turnstile-protected, vetted TestFlight request form — implementing the already-approved requirements doc — **plus one requirement the doc doesn't have yet: a Heritage section** telling (a) what GlucoseDirect is and who made it, and (b) what DOSBTS changed since the fork, at both the marketing level (the story) and the feature level (a concrete diff list).

## Preconditions

1. `cd /Users/doke/extracode/dosbts-web && git pull` (currently 1 commit: scaffold + brainstorm).
2. **The spec is `docs/brainstorms/2026-06-18-dosbts-showcase-site-requirements.md` — read it fully and treat R1–R12 + AE1–AE4 as binding.** This plan only adds to it; where this plan and that doc conflict, the doc's medical-boundary rules (R7–R10) win.
3. Content sources (read-only): `../DOSBTS/README.md` (lines ~23–33 already contain the fork story, upstream credit to Reimar Metzen / @creepymonster, and a "What's new in DOSBTS (vs. GlucoseDirect upstream)" section — the heritage copy starts here), `../DOSBTS/CHANGELOG.md` (shipped-build reality check), `../DOSBTS/CLAUDE.md` (feature bullets).
4. Cloudflare account with dmnc.tech managed (assumption A1 in the doc — confirm before the deploy step; if the zone isn't Cloudflare-managed, stop and report).

## Step 0 — extend the requirements doc FIRST

Append to `docs/brainstorms/2026-06-18-dosbts-showcase-site-requirements.md`:

```markdown
**Heritage (added 2026-07-10)**
- R13. A Heritage section explains the GlucoseDirect origin: what the upstream app is, who built it (Reimar Metzen / @creepymonster), a link to https://github.com/creepymonster/GlucoseDirectApp, and a visible nudge to support upstream first (PayPal link as in the app README).
- R14. The same section shows what DOSBTS changed since the fork: the marketing-level story (DOS amber re-skin + "built to see" framing) and a feature-level diff list (inherited-from-upstream vs added-in-DOSBTS), factually consistent with the app README and CHANGELOG.
- AE5. Covers R13, R14. The heritage section names and links GlucoseDirect, credits the author, and every "added in DOSBTS" item corresponds to a shipped CHANGELOG build.

**German-law + privacy compliance (added 2026-07-10)**
- R15. The site carries an Impressum (§5 TMG/DDG legal notice) — reuse/adapt the dmnc.tech Impressum (cross-repo: Linear DMNC-572 tracks Impressum rollout across all public sites; this site is in scope).
- R16. A privacy notice states exactly what the request form stores (email, optional note, timestamp — in Cloudflare KV), the purpose (TestFlight invite interest), and a deletion contact. No cookies/trackers to declare in v1.
- AE6. Covers R15, R16. Impressum and privacy notice are reachable from the footer on every viewport.

**Distribution gate (added 2026-07-10)**
- R17. The vetted-invite CTA assumes Apple **Beta App Review** approves DOSBTS for *external* TestFlight testing. This is validated by a pilot (one build, tiny external group) BEFORE the form backend is built. If the pilot is rejected, the CTA is redesigned (friends-only internal testers or source-build path) before launch.
```

Commit that separately (`docs: add heritage + compliance + distribution-gate requirements (R13–R17)`), then build to the doc.

## Step 0.5 — TestFlight external-review pilot (gates the form backend only)

Decision made 2026-07-10 ("test the water first"): in App Store Connect, create an external tester group with 1–2 known people, add the current TestFlight build to it, and submit for Beta App Review. This is an ASC-web task for the maintainer, not code — prompt Dom to do it at plan start and record the outcome in this file's checkbox:

- [ ] Beta App Review outcome: APPROVED / REJECTED (reason: ______)

**Do not build steps 4 and 6 (form backend, Turnstile/KV) until this box says APPROVED.** Steps 1–3 + 5 (scaffold, tokens, hero/heritage/features/build-story sections, screenshots) proceed in parallel regardless — they are CTA-independent. If REJECTED: replace the form section with the fallback CTA (interest form still fine, but copy promises "friends-and-family invites" via internal testing, ≤100 known testers, no Apple review) and note the pivot in `IMPLEMENTATION_NOTES.md`.

## Exact deliverables / files (all in dosbts-web)

```
astro.config.mjs, package.json, tsconfig.json      # Astro scaffold (npm create astro@latest — minimal/empty template)
src/pages/index.astro                               # the single landing page
src/components/{Hero,Heritage,Features,BuildStory,RequestForm,Disclaimer,Footer}.astro
src/styles/global.css                               # DOS amber tokens (see step 3)
functions/api/request-access.ts                     # Cloudflare Pages Function: Turnstile verify + KV write
public/ (favicon, og image, screenshots/)           # simulator-data screenshots ONLY
wrangler.toml (or Pages dashboard config)           # KV binding + Turnstile secret
README.md                                           # update status from "Planning" once deployed
```

## Implementation steps (in order)

1. **Scaffold Astro** (static output; add `@astrojs/cloudflare` adapter only for the Pages Function route or use Pages Functions directly via `functions/` dir — prefer the plain `functions/` dir: zero adapter complexity, the page itself stays fully static).
2. **Design tokens.** Copy the palette as CSS custom properties into `src/styles/global.css`: `--amber: #ffb000; --amber-dim: #9a5700; --amber-bright: #fdca9f; --bg: #000000; --cga-green: #55ff55; --cga-red: #ff5555; --cga-cyan: #55ffff;` + monospace stack (`ui-monospace, 'JetBrains Mono', 'IBM Plex Mono', monospace`), sharp corners (no border-radius anywhere), 8px spacing grid. The sibling `../eiDotter` package has `src/styles/theme.amber-mono.css` / `tokens.css` / `dos-utilities.css` — you MAY copy specific rules from there (CRT/scanline effects, phosphor glow) but do NOT add eidotter as an npm dependency (it would couple the site to the design-system release cycle for a single page; the brainstorm's outstanding-questions section left this open — this plan decides: inline tokens).
3. **Page sections, top to bottom** (single `index.astro`):
   1. **Hero** — app name, one-liner ("A DOS amber terminal for your glucose."), a simulator screenshot, and the medical disclaimer **visibly adjacent** (AE1 requires above-the-fold or adjacent-to-imagery).
   2. **Heritage** (NEW, R13/R14) — two-part layout:
      - *The origin:* what GlucoseDirect is (SwiftUI CGM app for Libre sensors), credit + link to Reimar Metzen / @creepymonster, "support upstream first" PayPal nudge. Source the copy from `../DOSBTS/README.md:23-31` — it is already written in the right voice; adapt, don't invent.
      - *The fork diff:* two columns — "Inherited from GlucoseDirect" (sensor stack Libre 1/2/3 + Bubble + LibreLinkUp, calibration, Nightscout, HealthKit export, Redux architecture) vs "Added in DOSBTS" (DOS amber CGA aesthetic, AI food logging photo/text/barcode, guided hypo treatment cycle Rule-of-15, IOB decay model, meal impact + PersonalFood scores, Ratio Lab, day/night alarm profiles, daily digest with AI insight, tight-control celebrations, widgets + Live Activity). Cross-check every "added" claim against `../DOSBTS/CHANGELOG.md` before writing it (AE5).
   3. **Feature highlights** — 4–6 cards with simulator screenshots (R2).
   4. **Build story** — milestone strip (fork date → notable builds → current Build 129) + link out to the dmnc.tech devlog (R3/AE4).
   5. **Request access form** — email + optional note + Turnstile widget (R4–R6).
   6. **Disclaimer + footer** — full personal/experimental disclaimer (R7), MIT/upstream credit repeat, DOOMBTS sister-fork mention, GitHub links, **Impressum + privacy notice links (R15/R16)** — Impressum content adapted from dmnc.tech's (DMNC-572); privacy notice is a short static section/page naming the KV-stored fields and a deletion contact email.
4. **Form backend** (`functions/api/request-access.ts`): POST handler — verify Turnstile token server-side (`https://challenges.cloudflare.com/turnstile/v0/siteverify` with `TURNSTILE_SECRET`), validate email shape, then `KV.put("signup:" + crypto.randomUUID(), JSON.stringify({email, note, ts: Date.now(), source: "dosbts-web"}))`. Decision (was an open question in the doc): **KV, not D1** — write-only interest list read manually by the maintainer; D1 is overkill. Inline confirmation on the page (no auto-reply email — second open question, decided: inline only for v1).
5. **Screenshots**: produce from the DOSBTS app on simulator with VirtualConnection ONLY (R8). From `../DOSBTS`: build + run on the iPhone 17 Pro sim, use the xcodebuild-mcp `screenshot` tool or `xcrun simctl io booted screenshot`. Overview, chart, Ratio Lab, digest, treatment banner are the natural five. **Inspect each image before committing: no real glucose history, no personal data in status bars.**
6. **Turnstile + KV provisioning**: use the `turnstile-spin` skill for widget creation; create the KV namespace via wrangler; bind both in the Pages project. Secrets via Cloudflare dashboard/wrangler secret — **never committed** (R12).
7. **Deploy**: create the Cloudflare Pages project (connect the GitHub repo or `wrangler pages deploy`), then add the custom domain `dosbts.dmnc.tech` (CNAME in the dmnc.tech zone). Verify preview URL first, domain second.
8. Update dosbts-web `README.md` status line; close out with a commit series (`feat: v1 landing page`, `feat: request-access function`, `chore: deploy config`).

## Cases a weaker model would miss

1. **The medical boundary is a hard gate, not a style note.** No efficacy/accuracy/health-outcome claims anywhere in copy (R9) — this includes seemingly harmless marketing lines like "keeps you safer at night" (outcome claim — banned) vs "fires an alarm when a low is predicted" (feature description — fine). When in doubt, describe the feature mechanically.
2. **No public TestFlight link.** AE3 explicitly: access is requested via the form and granted manually out-of-band. Do not paste a `testflight.apple.com/join/...` URL anywhere, including the README.
3. **The publishing boundary governs build-story content — with ONE explicit exception.** Only already-public detail (the public GitHub repo, shipped TestFlight builds) may appear; nothing from private planning docs, Linear internals, or third-party personal data. **Exception, decided by Dom on 2026-07-10: the site tells the first-person story — Dom has T1D and dogfoods DOSBTS daily. Write it person-voiced ("I wear the sensor; this is my daily driver").** This was a deliberate one-way-door decision; do not water it down to product voice, and equally do not extend it beyond that fact (no glucose numbers, no treatment history, no other health detail).
4. **Heritage accuracy = fork etiquette.** Credit is generous and specific (Reimar Metzen / @creepymonster, MIT, "support upstream first" with the PayPal link from the app README). Do not present inherited capabilities (sensor stack, Nightscout, calibration) as DOSBTS work — the two-column inherited/added split exists precisely to prevent this. DMNC-972 (asking upstream about etiquette) is still open — the site must be something that conversation can point at proudly.
5. **Screenshots are the highest-risk asset.** A screenshot taken from the developer's real device leaks real glucose data (R8 violation + privacy). Simulator + VirtualConnection only; re-check the final committed PNGs, not just the capture session.
6. **Static-first**: the page must render fully without JS except the Turnstile widget and the form submit. No analytics in v1 (doc scope: "privacy-respecting basics" deferred); no third-party fonts CDN if it means a tracker — self-host or system mono stack.
7. **Don't import the eidotter npm package** — inline the handful of tokens (decision recorded above). But DO keep visual kinship: amber on black, sharp corners, monospace, scanline/phosphor accents.
8. **`functions/` dir vs Astro SSR adapter**: mixing both confuses Pages builds. The decision here is plain `functions/api/request-access.ts` with a fully static Astro build (`output: 'static'`). If the Astro Cloudflare adapter ends up installed anyway, remove it.
9. **Secrets discipline**: `TURNSTILE_SECRET` and any API tokens live in Pages project settings / `wrangler secret`; `.dev.vars` for local testing goes in `.gitignore`. The Turnstile *site key* is public and may be committed.
10. **Domain wiring order**: deploy to the `*.pages.dev` preview and pass acceptance there BEFORE adding the `dosbts.dmnc.tech` custom domain — a broken page on the branded domain is publishing, a broken preview is not.

## Acceptance criteria

1. **AE1:** disclaimer visible above the fold / adjacent to the hero image on a 390px-wide viewport and on desktop.
2. **AE2:** form POST with valid email + passing Turnstile → 200 + KV entry visible via `wrangler kv key list`; POST with missing/invalid Turnstile token → 4xx, no KV write.
3. **AE3:** `grep -ri "testflight.apple.com" src/ public/ functions/` returns nothing.
4. **AE4:** build-story section contains a working link to the dmnc.tech devlog.
5. **AE5 (new):** heritage section links `github.com/creepymonster/GlucoseDirectApp`, credits Reimar Metzen, includes the support-upstream nudge; every "Added in DOSBTS" bullet maps to a `[Build N]` entry in `../DOSBTS/CHANGELOG.md` (spot-check each).
6. All screenshots verifiably simulator/virtual (uniform synthetic curves; no real timestamps/history).
7. `dosbts.dmnc.tech` serves the page over HTTPS after domain wiring; Lighthouse (or PageSpeed) sanity: performance + accessibility ≥ 90 on the static page.
8. Repo contains no secrets (`git grep -iE "secret|api[_-]?key" -- ':!*.md'` reviewed by hand).
9. **AE6 (new):** Impressum and privacy notice reachable from the footer at 390px and desktop widths; privacy notice names email/note/timestamp + Cloudflare KV + deletion contact.
10. **R17 gate honored:** the form backend was only built/deployed after the Beta App Review pilot checkbox in Step 0.5 reads APPROVED (or the fallback CTA was substituted and noted).

## Bookkeeping

- Linear DMNC-1120 → In Progress at start; on deploy, mark Done and drop a comment with the live URL + note that the heritage section also serves DMNC-972 context.
- The maintainer signup-review loop (reading KV, sending invites) is manual by design — document the `wrangler kv key list --namespace-id=...` command in the dosbts-web README.
