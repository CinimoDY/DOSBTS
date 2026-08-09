# Food Logging 2026 Vision

Reference for long-term DOSBTS food logging direction. Maps the evolution from manual logging to AI-native, low-friction food tracking.

## Core Principle

> In 2026, we don't design for "Total Accuracy" (which is stressful); we design for **"Total Consistency"** (which is sustainable).

## 1. Multimodal Entry: "See it, Say it, Log it"

- **Computer Vision (Snapshot):** Photo → LMM identifies ingredients → depth sensing estimates portion size
- **Voice Side-Car Logging:** If AI misses something in photo, user says it. AI merges visual + verbal context in real-time
- **Correction UX (Confidence Heatmap):** AI shows confidence on the photo itself. Low-confidence items pulse. Tap to correct, calories update instantly

### DOSBTS Status
- Photo analysis: DONE (Claude Haiku, staging plate)
- Voice side-car: IN PROGRESS (in-app on-device dictation, DMNC-1486; NL text parsing DMNC-558 shipped)
- Confidence heatmap on photo: FUTURE (aspirational, not yet planned)

## 2. Agentic UX: The Proactive Partner

- **Restaurant Prep Nudge:** GPS detects restaurant arrival → AI scans menu → suggests items fitting remaining macros
- **Predictive/Zero-Click Logging:** "Logged your usual morning shake. Swipe to dismiss if you skipped it"
- **Fridge-to-Goal:** Photo of refrigerator → AI generates recipe fitting remaining daily macros

### DOSBTS Status
- All items: FUTURE (not yet planned, would require background location + menu database + recipe generation)

## 3. The "Invisible" UI (Context & Sensors)

- **Biometric Sync (CGM):** Show "Glucose Impact Score" next to each meal — this is DOSBTS's core differentiator
- **AR Overlays:** Smart glasses show floating nutritional breakdown over food
- **Environmental Awareness:** Stress-aware coaching based on calendar + heart rate

### DOSBTS Status
- CGM glucose correlation with meals: CORE FEATURE (glucose chart + meal markers exist)
- Glucose Impact Score per meal: FUTURE (DMNC-532 references Phase 8: glucose correlation analysis)
- AR/smart glasses: FUTURE (aspirational)

## 4. Spatial UI for Photo Analysis

Instead of a static list, overlay data on the photo:

- **Segmented Outlays:** Soft glowing lasso around each food item with confidence-colored outlines
- **Scale Reference:** Fork/hand detected for volume estimation
- **Intelligence Drawer:** Bottom sheet with real-time macro ticker + AI reasoning explanation
- **Direct Manipulation:** Tap item → quick-toggle options. Long press → adjust. Swipe → remove. Double-tap empty → add missing item

### DOSBTS Status
- Current: Form-based staging plate with inline expand/collapse (functional, not spatial)
- Future: Overlay-based photo annotation would be a major UI evolution

## 5. The "Empathy Layer"

- **Forgiveness-First Design:** No shame notifications. AI estimates gaps in logging automatically
- **Non-Linear Progress:** Show trends, not single days. Smoothing algorithms show consistency
- **Guided Recovery:** When AI is confused, show "Explode View" of likely ingredients, ask one clarifying question

### DOSBTS Status
- Guided recovery maps to: DMNC-560 (conversational follow-up)
- Trend views: FUTURE (statistics view exists but is glucose-focused, not meal-trend-focused)

## Design Comparison

| Feature | Old UX (Manual) | 2026 AI UX |
|---------|-----------------|------------|
| Adding a Meal | Search → Select → Adjust Grams | Photo + voice clip |
| Portion Control | "Is this 1 cup?" (guessing) | AR/depth estimation |
| Guidance | Static calorie bars | Dynamic empathetic coaching |
| Database | User-submitted (often wrong) | AI-verified, cross-referenced |

## Mapping to DOSBTS Phases

| Vision Feature | DOSBTS Issue | Status |
|----------------|-------------|--------|
| Photo analysis | DMNC-427 | Done |
| Editable AI results (staging plate) | DMNC-553 | Done |
| NL text parsing | DMNC-558 | Planned |
| Voice (in-app, on-device) | DMNC-1486 | In progress (supersedes the canceled Wispr/external plan, DMNC-559) |
| Conversational follow-up | DMNC-560 | Backlog |
| Barcode scanning | DMNC-561 | Backlog |
| Portion presets | DMNC-562 | Backlog |
| Glucose Impact Score | Phase 8 | Future |
| Confidence heatmap on photo | — | Future |
| Predictive/zero-click logging | — | Future |
| Restaurant GPS nudges | — | Future |
| AR overlays | — | Future |
