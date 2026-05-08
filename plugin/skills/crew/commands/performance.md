# /crew performance — Measure, recommend, optimise, re-measure

End-to-end performance loop: measure baseline → analyse → recommend prioritised fixes → optionally implement → re-measure → write a numeric impact report.

Performance work is uniquely measurable. Every optimisation can be expressed as a number that moved (TTI: 4.2s → 1.8s, bundle: 540kb → 320kb, p99 latency: 850ms → 220ms). This command leans into that — the deliverable is **before/after metrics**, not just advice.

> **Distinct from `/crew investigate --type perf`:** investigate is read-only and ends with findings. `/crew performance` is the full measure → optimise → re-measure loop in one command, so the before/after comparison stays attached to the same artifacts.

---

## Usage

```
/crew performance                                    → Interactive: ask for target + scope
/crew performance "https://app.example.com/dashboard"  → Frontend perf for a specific URL
/crew performance "POST /api/checkout"                 → Backend perf for an endpoint
/crew performance --type {frontend|backend|mobile|full}
/crew performance --budget {strict|standard|relaxed}   → Web Vitals targets
/crew performance --no-implement                       → Measure + recommend only; never implement
/crew performance --auto-implement-quick-wins          → Implement P1 + P2 without asking
```

---

## Step 0 — Frame the perf concern

Dispatch `AskUserQuestion` if invoked interactively:

```
AskUserQuestion({
  questions: [{
    header: "Performance scope",
    question: "What kind of performance work?",
    multiSelect: false,
    options: [
      {label: "Frontend — page load / Core Web Vitals", description: "TTFB, FCP, LCP, CLS, INP. Bundle size, render time, network waterfall. Uses Chrome DevTools MCP if available."},
      {label: "Backend — API latency / DB queries", description: "Endpoint p50/p95/p99, slow queries, N+1, connection pool. Reads server code + dispatches probes."},
      {label: "Mobile — cold start / memory / battery", description: "App startup time, peak memory, frame rate, battery drain on long sessions."},
      {label: "Full — everything where applicable", description: "Most comprehensive; longest run-time. Right for pre-launch perf audits."}
    ]
  }]
})
```

Then collect:
- **Target** — URL / endpoint / app screen / specific component
- **Symptom** — what's slow? "page takes 4s on mobile" / "checkout 500s under load" / "list scroll janks past 1000 items"
- **Devices/conditions** — desktop / mobile / both; throttled network / fast network
- **Budget profile** — strict / standard / relaxed (controls thresholds; see below)

Write to `.crew/current-feature.yaml`:

```yaml
mode: performance
performance:
  run_id: PERF-{YYYYMMDD}-{slug}
  type: frontend                         # frontend | backend | mobile | full
  target: "https://app.example.com/dashboard"
  symptom: "LCP ~ 4.2s on mobile 3G"
  devices: [desktop, mobile-throttled]
  budget_profile: standard               # strict | standard | relaxed
  started: 2026-05-08T...
```

### Budget profiles (what counts as "good")

| Metric | strict | standard | relaxed |
|---|---|---|---|
| LCP | ≤ 1.5s | ≤ 2.5s | ≤ 4.0s |
| FCP | ≤ 1.0s | ≤ 1.8s | ≤ 3.0s |
| INP | ≤ 100ms | ≤ 200ms | ≤ 500ms |
| CLS | ≤ 0.05 | ≤ 0.10 | ≤ 0.25 |
| Bundle (initial JS) | ≤ 170kb | ≤ 350kb | ≤ 700kb |
| Backend p99 | ≤ 100ms | ≤ 300ms | ≤ 1000ms |

Picked profile becomes the pass/fail oracle for Step 7's re-measurement.

---

## Step 1 — Profile + budget gates (existing patterns)

```bash
bash {plugin_root}/scripts/crew-profile-check.sh \
  --feature-description "performance: {target}"

bash {plugin_root}/scripts/crew-budget-check.sh \
  --op-type performance_optimizer \
  --feature-id {run_id} \
  --phase 4 \
  --next-step measure_baseline
```

Performance work is Phase 4 (Quality) territory. Budget cost is medium — primary load is Chrome DevTools MCP traces (small) + performance-optimizer dispatch (~30K tokens) + optional implementation pass.

---

## Step 2 — Push spike card (`Building` status)

```
/crew push   → create mode, card_type: spike
```

Card body filled from the spike skeleton with these placeholders:

- **Hypothesis** = the symptom from Step 0
- **Research questions** = "Where is time being spent? What is the dominant constraint? What's the highest impact-to-effort fix?"
- **Time-box** = 2h default (perf work usually fits this)
- **Custom field `Source`** = `performance`

---

## Step 3 — Measure baseline

This is the load-bearing step. Without real measurement, every recommendation downstream is a guess. Crew detects which MCP tools are available and adapts.

### Frontend measurement

**Detect Chrome DevTools MCP availability:**

```javascript
// Pseudocode the model executes
const hasChrome = await ToolSearch({ query: "select:mcp__chrome-devtools__lighthouse_audit", max_results: 1 });
```

**If Chrome DevTools MCP available — full measurement path:**

1. **Lighthouse audit** — `mcp__chrome-devtools__lighthouse_audit({ url, throttling: 'mobile' })`
   - Captures Core Web Vitals (LCP, FCP, INP, CLS, TBT)
   - Scores: performance, accessibility, best-practices, SEO
   - Saves report to `.crew/performance/{run_id}/lighthouse-baseline.json`

2. **Performance trace** — `mcp__chrome-devtools__performance_start_trace` → navigate → `performance_stop_trace`
   - Captures full main-thread activity
   - Saves trace JSON to `.crew/performance/{run_id}/trace-baseline.json`
   - Run `performance_analyze_insight` for auto-detected bottlenecks

3. **Network waterfall** — `mcp__chrome-devtools__list_network_requests`
   - Total requests, total bytes, blocking resources, third-party domains
   - Saves to `.crew/performance/{run_id}/network-baseline.json`

4. **Memory snapshot** — `mcp__chrome-devtools__take_memory_snapshot` (only for `mobile` or `full` types, or when symptom mentions memory)
   - Heap composition, retained sizes
   - Saves to `.crew/performance/{run_id}/memory-baseline.heapsnapshot`

5. **Console + errors** — `mcp__chrome-devtools__list_console_messages` to capture any errors / warnings during load.

**If Chrome DevTools MCP unavailable — degraded path:**

- Read `package.json` + `webpack.config.js` / `vite.config.ts` / `next.config.js` to estimate bundle topology
- Ask user to run `lighthouse <url> --output=json --output-path=lighthouse.json` locally and paste the path
- Read static analysis: largest deps, code-split boundaries, route-level splits
- Print clear note: "Chrome DevTools MCP not available — measurements will be static-analysis only. Install the MCP for runtime metrics."

### Backend measurement

For backend, dispatch code-reviewer in **read-only mode**:

```
READ-ONLY MODE — do not modify any files.

Target: {endpoint}
Symptom: {symptom}

Find performance-relevant patterns:
  1. Slow queries — full table scans, missing indexes, N+1 patterns
  2. Synchronous I/O on the hot path (file/network without await)
  3. Missing caching layers (memoization, Redis, CDN)
  4. Connection pool sizing vs concurrency
  5. Response payload size (over-fetching, missing pagination)
  6. Middleware overhead on the hot path
  7. Logging at INFO/DEBUG level inside loops

Output to .crew/performance/{run_id}/backend-baseline.md:
  ## Endpoint topology (file:line of route handler)
  ## Database queries used (with EXPLAIN if available)
  ## Caching surface
  ## Identified issues (severity: blocker / major / minor)
  ## Suggested probes (specific log lines or APM traces to run in production)
```

If the user has APM access (Datadog, Sentry, NewRelic), suggest: "Pull p99 latency for the last 7 days for `{endpoint}` and paste the data so the analysis can ground in production reality."

### Mobile measurement

For React Native / SwiftUI / Compose, the main signals are startup time + memory + frame rate. Without on-device tools, this is mostly static analysis:

- Read native build config for deferred init / lazy modules
- Identify large image assets shipped in the bundle
- Check for synchronous AsyncStorage access on app start
- Verify list virtualisation (FlatList / LazyColumn) is used for long lists

Note: full mobile profiling needs Xcode Instruments / Android Studio Profiler — beyond what the MCP layer can drive. Crew suggests these tools and asks the user to share results.

### Persist all measurements

Write a unified summary to `.crew/performance/{run_id}/baseline-summary.yaml`:

```yaml
captured_at: 2026-05-08T...
target: "https://app.example.com/dashboard"
type: frontend
budget_profile: standard
metrics:
  LCP: { value: 4200, unit: ms, threshold: 2500, status: fail }
  FCP: { value: 2100, unit: ms, threshold: 1800, status: fail }
  INP: { value: 180,  unit: ms, threshold: 200,  status: pass }
  CLS: { value: 0.04, unit: score, threshold: 0.10, status: pass }
  bundle_initial_js_kb: { value: 540, threshold: 350, status: fail }
  total_requests: 87
  blocking_resources: 4
sources:
  lighthouse: lighthouse-baseline.json
  trace:      trace-baseline.json
  network:    network-baseline.json
  memory:     memory-baseline.heapsnapshot
```

---

## Step 4 — Analyse (performance-optimizer agent)

Dispatch the `performance-optimizer` agent with full context:

```
Analyse the performance baseline at .crew/performance/{run_id}/.

Inputs:
  - baseline-summary.yaml
  - lighthouse-baseline.json (or note if Lighthouse unavailable)
  - trace-baseline.json
  - network-baseline.json
  - backend-baseline.md (if backend mode)

Produce .crew/performance/{run_id}/findings.md with sections:

  ## Top 3 bottlenecks
    For each: name, evidence (specific metric / trace event), impact estimate (ms or kb).

  ## Categorised opportunities
    Grouped by category — Caching / Bundle / Render / Network / Database / Memory / Architecture
    For each opportunity:
      - Root cause (one sentence)
      - Files / endpoints involved
      - Expected delta (e.g. "saves ~600kb initial JS, expected LCP improvement 800-1200ms")
      - Effort estimate: trivial / small / medium / large

  ## Quick wins
    Opportunities that are trivial-to-small effort AND >10% improvement on a failing metric.

  ## Architectural changes
    Opportunities that are medium-to-large effort. Document trade-offs explicitly:
    "Adding Redis caching reduces p99 latency by ~80% but introduces an operational
     dependency, cache invalidation complexity, and ~$50/mo infra cost."

  ## What we cannot fix from inside this codebase
    External constraints (CDN config, third-party SDKs, network conditions). Flag these
    with: "requires {ops/CDN/vendor} action — not in scope for this run."

Confidence in your analysis: high | medium | low.
```

---

## Step 5 — Prioritised recommendations + ask to implement

Read `findings.md`. Compose a prioritised recommendation table using **impact × effort** as the priority metric (RICE-style for perf):

| Priority | Item | Expected delta | Effort | Cost (tokens) |
|---|---|---|---|---|
| P1 | Lazy-load Recharts on dashboard route | LCP -1200ms | Small | ~8K |
| P1 | Add ETag headers to /api/products | p99 -250ms | Trivial | ~3K |
| P2 | Replace bundled lodash with lodash-es + tree-shake | bundle -180kb | Small | ~6K |
| P2 | Add index on orders.user_id | p99 -150ms | Trivial | ~2K |
| P3 | Pre-render product cards | LCP -300ms | Medium | ~25K |

Dispatch `AskUserQuestion`:

```
AskUserQuestion({
  questions: [{
    header: "What to implement",
    question: "Found {N} optimisations across {N_categories} categories. {P1_count} P1 (high impact, low effort), {P2_count} P2, {P3_count} P3. How to proceed?",
    multiSelect: false,
    options: [
      {label: "★ Implement P1 only (recommended)", description: "Quick wins. ~{P1_token_total} tokens. Highest impact-to-effort. Re-measure after."},
      {label: "Implement P1 + P2", description: "More thorough. ~{P1+P2_token_total} tokens. Good for pre-launch audits."},
      {label: "Implement everything", description: "All P1 + P2 + P3. ~{total_tokens} tokens. Includes architectural changes — review the trade-off notes first."},
      {label: "Show me each — I'll pick", description: "Multi-select review. Best when scope is sensitive."},
      {label: "Save report only — don't implement", description: "I'll act on this myself. Spike stays in Building until I close it."}
    ]
  }]
})
```

If `--no-implement` flag was passed at invocation, skip Step 5 entirely and treat as if user picked "Save report only."

If `--auto-implement-quick-wins` flag was passed, skip the question and implement P1 automatically.

### On "Show me each — I'll pick"

Dispatch a multi-select with one option per recommendation:

```
{
  multiSelect: true,
  options: [
    {label: "P1 · Lazy-load Recharts (LCP -1200ms · Small · 8K)", description: "src/Dashboard.tsx"},
    {label: "P1 · ETag for /api/products (p99 -250ms · Trivial · 3K)", description: "src/api/products.ts"},
    {label: "P2 · lodash-es swap (bundle -180kb · Small · 6K)", description: "package.json + 4 imports"},
    // ... one per recommendation
  ]
}
```

Record selected items as `current-feature.yaml#performance.scope.implementing`.

---

## Step 6 — Implement (only if user opted in)

For each item in `performance.scope.implementing`, dispatch the appropriate engineer:

| Recommendation kind | Agent |
|---|---|
| Bundle / code-split / route-level lazy | ui-engineer |
| Image / font / asset optimisation | ui-engineer |
| API caching / response shaping | api-engineer |
| Database index / query rewrite | api-engineer |
| Render path / memo / virtualisation | ui-engineer |
| Architectural (CDN, Redis, sharding) | pm-architect for design + ui/api-engineer for implementation |

The dispatch prompt template:

```
Implement performance optimisation: {item.title}

Source: .crew/performance/{run_id}/findings.md (Section: {item.category})

Expected delta: {item.expected_delta}
Effort estimate: {item.effort}

Constraints:
  - Do not break existing tests
  - If the change touches a public interface or contract, update
    docs/api-contract.md and the corresponding TypeScript types
  - Add a comment near the change referencing the perf run:
      // PERF-{run_id}: {one-line cause}
  - Write a one-line summary of what you did to
    .crew/performance/{run_id}/changes-{item_index}.md

Re-measurement constraints (Step 7 will verify):
  - The targeted metric MUST improve toward the budget threshold
  - No other tracked metric may regress by more than 10%
```

Wait for each engineer to complete. Run `crew-budget-log.sh` per item with actual tokens.

After all items complete, validate that every selected item produced a `changes-{N}.md` file. Re-dispatch any that were skipped.

---

## Step 7 — Re-measure

Re-run **the same measurement protocol from Step 3** with the same target, devices, and budget profile.

Save outputs alongside the baselines with a `-after` suffix:
- `lighthouse-after.json`
- `trace-after.json`
- `network-after.json`
- `memory-after.heapsnapshot` (if relevant)
- `baseline-summary-after.yaml`

Compare baseline vs after for each tracked metric:

```yaml
# .crew/performance/{run_id}/comparison.yaml
metrics:
  LCP:
    baseline: 4200ms
    after:    2100ms
    delta:    -2100ms (-50%)
    status:   improved (now within standard budget)
  FCP:
    baseline: 2100ms
    after:    1500ms
    delta:    -600ms (-29%)
    status:   improved (now within standard budget)
  bundle_initial_js_kb:
    baseline: 540
    after:    320
    delta:    -220 (-41%)
    status:   improved (now within standard budget)
  INP:
    baseline: 180ms
    after:    192ms
    delta:    +12ms (+7%)
    status:   regressed_within_tolerance (still passing)
```

**If any metric regressed beyond the 10% tolerance**, halt and surface to user:

```
⚠ Re-measurement found a regression that breaks the constraint:
    {metric}: {before} → {after} ({+delta}%)

Options:
  1. Roll back the optimisation that caused it
  2. Investigate further (run /crew investigate --type perf)
  3. Accept the regression with explicit override
```

---

## Step 7.5 — Performance impact report

Write `.crew/performance/{run_id}/IMPACT.md`. Different shape from bug-flavored IMPACT.md — this one is **numeric-first**:

```markdown
# Performance Impact Report — {run_id}

> {target} · {budget_profile} budget · {N_implemented}/{N_recommended} optimisations applied

---

## Headline numbers

| Metric | Before | After | Delta | Status |
|---|---|---|---|---|
| LCP | 4200ms | 2100ms | **−2100ms (−50%)** | ✅ now within budget |
| FCP | 2100ms | 1500ms | **−600ms (−29%)** | ✅ now within budget |
| Bundle (initial JS) | 540kb | 320kb | **−220kb (−41%)** | ✅ now within budget |
| INP | 180ms | 192ms | +12ms (+7%) | ⚠️ regressed within tolerance |
| CLS | 0.04 | 0.04 | 0 | — |

**Lighthouse performance score:** 47 → 89 (+42)

## What was done

| # | Optimisation | Files | Token cost |
|---|---|---|---|
| 1 | Lazy-load Recharts on dashboard route | src/Dashboard.tsx | 7800 |
| 2 | ETag headers for /api/products | src/api/products.ts | 2900 |
| 3 | lodash → lodash-es with tree-shake | package.json + 4 imports | 5400 |

Total token cost: 16,100

## What was deferred

Items in findings.md but not implemented this run:

| # | Optimisation | Reason | Tracked as |
|---|---|---|---|
| P3-1 | Pre-render product cards | Architectural change; needs design review | Spike: PERF-...-deferred |
| P3-2 | Add CDN at edge | External infra change; not codebase work | Ops ticket {needed} |

Deferred items auto-spawn a follow-up `PERF-{run_id}-deferred` spike, pushed as a Planned card. Never silently lost.

## Trade-offs accepted

For each architectural change implemented, document explicitly what was given up:

- **Lodash-es swap** — slightly larger compile-time graph (build is ~2s slower) in exchange for 180kb bundle reduction. Worth it for users; mildly slower CI.

## Production validation

After deploy, watch:

- `web_vitals.LCP` p75 — should drop from ~4.2s → ~2.1s within 24h of deploy
- `bundle.initial_js_kb` — captured by RUM; should reflect new value immediately
- `web_vitals.INP` p75 — should NOT increase beyond 7% (regression threshold)

If real-user metrics don't match the lab measurement after 7 days, run `/crew investigate --type perf` with the gap as the topic.

## Rollback

Each optimisation is a separate commit. Revert individual commits if any one optimisation regresses in production:

```bash
git log --oneline --grep="PERF-{run_id}"
git revert {commit_sha}
```

## Methodology / reproducibility

- Tool: Chrome DevTools MCP (Lighthouse + perf trace)
- Throttling: mobile (4G, 4× CPU slowdown)
- Runs: 3 per measurement; median reported
- Re-measure: same conditions, same date

## Sign-off checklist

- [ ] Headline numbers reviewed; deltas match expectations
- [ ] Trade-offs accepted (or filed follow-up to revisit)
- [ ] Production validation metrics exist (or filed dashboard ticket)
- [ ] Rollback path verified (each optimisation is a separate revertable commit)
```

### Display to user

```
✓ Performance impact report ready: .crew/performance/{run_id}/IMPACT.md
   {N_improved} metrics improved · {N_regressed_tolerance} regressed (within tolerance) · {N_deferred} deferred
   Lighthouse score: {before} → {after} ({+delta})

   Read the report before merge. Attach to the PR description.
```

---

## Step 8 — Push card update

```
/crew push   → update-status mode
```

- If implementations succeeded **and** budget passed: status → `In Review`
- If implementations succeeded but **deferred items remain**: status → `In Review`; the deferred-items spike is a separate `Planned` card
- If user picked "Save report only": status → `Shipped` (consumed; user takes over)

If `config.github.update_body_on_phase_change: true`, rewrite the spike card body with the comparison table from `comparison.yaml` so the board surfaces the headline numbers.

---

## Step 9 — Suggest follow-up

Adaptive options based on what happened:

```
AskUserQuestion({
  questions: [{
    header: "Next perf step",
    question: "Performance run complete. Lighthouse score: {before} → {after}. Common follow-ups:",
    multiSelect: true,
    options: [
      {label: "No, we're done", description: "Close the spike card and move on"},

      // Show only if items were deferred:
      {label: "Implement the {N} deferred items", description: "Run /crew performance again on the same target with --auto-implement-quick-wins"},

      // Show only if a metric regressed (even within tolerance):
      {label: "Investigate the {metric} regression", description: "Run /crew investigate --type perf {metric}"},

      // Always show:
      {label: "Set up perf budget in CI", description: "Add a Lighthouse CI check that fails the build on regression"},
      {label: "Document the run in a runbook", description: "Dispatch doc-writer to add a perf-tuning entry referencing IMPACT.md"}
    ]
  }]
})
```

---

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Chrome DevTools MCP not available | Plugin not installed / not authenticated | Static-analysis fallback; print install instructions |
| Lighthouse audit times out | Page hangs or never reaches LCP | Increase timeout; check console errors first |
| Re-measurement shows no improvement | Cache wasn't busted between runs | Force hard reload; verify deployed code matches expected change |
| Regression > 10% on adjacent metric | Optimisation traded one metric for another | Halt; user picks rollback / investigate / accept |
| performance-optimizer suggests architectural changes user can't approve | Recommendations are infra-level | Defer to spike; don't implement; print the trade-off note |
| Lighthouse score improves but real users don't see it | RUM ≠ lab; geographic / device skew | Run `/crew investigate --type perf` with the lab-vs-RUM gap as the topic |

---

## What this command does NOT do

- **Run load tests.** That's a separate concern (k6 / Locust / artillery). Crew can scaffold a load-test config but doesn't run them.
- **Modify infrastructure.** No CDN config, no Kubernetes resource adjustments, no DNS changes. Flags these as deferred to ops.
- **Compare across deploys.** A single run captures one before/after comparison. For longitudinal tracking, integrate with your APM.
- **Replace your APM.** This is project-level, on-demand. Production observability lives in Datadog / Sentry / NewRelic — Crew suggests probes for those tools but doesn't replace them.
