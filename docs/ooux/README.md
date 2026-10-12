# OOUX entity map

`entity-map.html` is a single, self-contained page (no external requests) that maps DOSBTS the Object-Oriented UX way: an object map with typed link kinds, per-object attribute and CTA cards, a relationship table, an interface-pattern matrix that highlights gaps in red, and a cyan-framed "session deltas" block for in-flight changes. Tracked in DMNC-1563.

Open it: [`entity-map.html`](entity-map.html) (any browser; amber-on-black, light/print fallback).

## Regenerate

All content lives in the `<script type="application/json" id="model">` block inside the HTML. Edit the JSON (objects, `rels`, `mapNodes` coordinates, `matrix`, `deltas`, `unverified`) and reload; an inline script renders the cards, tables and SVG. Verify names against `Library/Content/*.swift` and `Library/DirectAction.swift` before committing. Keep it free of `http(s)://` URLs and under 300 KB.

## ORCA glossary

- **Objects**: the nouns users search, edit and think about (core), plus derived/system nouns (supporting).
- **Relationships**: how objects connect, with cardinality and a link kind: `typed`, `uuid`, `factory`, `derived`.
- **CTAs**: the actions on each object; here the `DirectAction` names.
- **Attributes**: the fields of each object, taken from the Swift declarations.

## See also

- Superseded: [`docs/brainstorms/2026-04-23-ooux-catalog-and-entry-patterns-requirements.md`](../brainstorms/2026-04-23-ooux-catalog-and-entry-patterns-requirements.md) (its object map and link-kind rule are the foundation of this map).

## Figma

The same model is laid out as a page **"OOUX — Entity map"** in the DOSBTS Design file (`figma.com/design/RJuK2lEGCmVBWEHn2hMaAm`, section `11:380`): object map with link-kind-styled lines, legend, session deltas, object cards, and the interface-pattern matrix. It was generated with the Figma MCP `use_figma` tool from the JSON model embedded in `entity-map.html`; regenerate the page from that model rather than editing it by hand.
