# Crew ↔ Gang Integration Guide

Crew and Gang are two complementary plugins. Each does one thing well; together they form an evidence-backed pipeline from "should we build it?" through to "did we ship it?".

---

## Conceptual model

```
┌──────────────┐                 ┌──────────────┐
│              │   /crew gang-   │              │
│     Gang     │──── import ────▶│     Crew     │
│              │                 │              │
│ "Should we   │                 │ "How do we   │
│  build it?"  │                 │   ship it?"  │
│              │◀── /crew gang ──│              │
│              │   -escalate     │              │
└──────────────┘                 └──────────────┘
       │                                │
       │ 6 stages:                      │ 6 phases:
       │ init → think → debate          │ strategy → design → API arch
       │ → score → advise → deliver     │ → implementation → quality → launch
       │                                │
       ▼                                ▼
   GO Package                       Shipped feature
   (BRD, charter, risk register,    (running in production,
    data model, API contracts)       monitored, supported)
```

**Key insight:** Gang's `deliver` stage produces exactly the artifacts Crew's `phase-1-strategy` and `phase-2-design` *consume*. Without integration you'd manually re-key a BRD into a roadmap; with integration the verdict, scope, risks, and CONDITIONAL-GO conditions travel intact.

---

## Lifecycle states

| Where | What lives there |
|-------|------------------|
| `.gang/features/<slug>/` | Gang evaluation: state.json, evidence.json, assumptions.json, position-papers/, debate/, scored-plans.md, executive-brief.md, go-package/ |
| `.gang/features/<slug>/state.json#github_push` | Where the Gang verdict was published (project board) |
| `.gang/features/<slug>/state.json#crew_import` | (NEW) Set when `/crew gang-import` consumes the evaluation |
| `.crew/roadmap.yaml` | Crew's master feature backlog |
| `.crew/roadmap.yaml#features[].source.origin` | Set to `gang` for imported features |
| `.crew/imports.yaml` | Audit log of all Gang→Crew handoffs |
| `.crew/features/<slug>/` | Crew's per-feature execution artifacts (phase outputs) |
| `.gang/features/<slug>/escalation-from-crew.md` | (NEW) Set when `/crew gang-escalate` sends a feature back to Gang |

---

## When to use Gang vs Crew

### Use **Gang** when:
- You don't yet know if you should build the thing
- The decision involves market/competitive analysis, regulatory exposure, or financial viability
- You need an independent multi-expert committee to stress-test assumptions
- You want a published GO/NO-GO with reasoning that can be shown to investors or stakeholders

### Use **Crew** when:
- The "should we" question is already answered (or it's small enough to skip Gang)
- You need to break work into engineering phases and dispatch specialised agents
- You need roadmap tracking, branching strategy, MCP server setup, and phase gates
- You're shipping the feature and tracking progress through implementation, QA, launch

### Use **both** (recommended for non-trivial features):
1. **Gang** evaluates the feature → produces GO Package (or CONDITIONAL-GO with conditions)
2. **`/crew gang-import <slug>`** ingests the GO Package → seeds roadmap.yaml entry
3. **Crew** drives the feature through phases 2 → 5
4. **`/crew gang-escalate <slug>`** if execution reveals the verdict needs revisiting

---

## Skipping Gang

For small features where a full Gang run is overkill, use `/crew feature` directly. You'll skip the strategic evaluation entirely. Crew's `phase-1-strategy` will still ask you to articulate the problem, but it won't produce evidence/assumption ledgers, scored plans, or an advisor-vetted verdict.

**Rule of thumb:** if a feature would take more than 2 weeks of engineering, run it through Gang first. The cost of a 30-minute Gang evaluation ($1–$20 depending on quality mode) is trivial compared to the cost of building the wrong thing for a sprint.

---

## CONDITIONAL-GO conditions

Gang very often returns CONDITIONAL-GO rather than unconditional GO. The conditions are *gating assumptions* — claims the committee couldn't verify before recommending the build.

When Crew imports a CONDITIONAL-GO feature, it copies the conditions verbatim into `roadmap.yaml.features[<slug>].source.conditions`. **Crew's `phase-3-implementation` MUST NOT activate until those conditions are validated.**

Treat CONDITIONAL-GO conditions like compile errors: they block the build. Each one needs:
1. A named owner
2. A validation method (survey, backtest, legal review, etc.)
3. A pass/fail outcome recorded back in `assumptions.json`
4. A flip from `unvalidated` → `validated` before phase-3 unlocks

If a condition cannot be validated and the feature must ship anyway, that's a strategic decision — escalate to Gang via `/crew gang-escalate`.

---

## Versioning & compatibility

Crew tracks the Gang plugin version it was developed against. See `plugin/.claude-plugin/plugin.json`:

```json
"upstream": {
  "name": "archflow",
  "url": "https://github.com/azidan/archflow",
  "version_at_fork": "1.2.3"
}
```

Crew handoff commands target Gang **v1.3.x and later** (the version that introduced GO Package generation, `github_push` state recording, and `default_card_type` in config). Earlier Gang versions don't produce the artifacts Crew expects to consume.

If your Gang plugin is older than v1.3.0, run:
```
/gang config
# or upgrade the plugin clone, then:
gh project list --owner <you>  # to confirm v1.3.x features available
```

---

## Future integration ideas

Not yet implemented — listed here so the design intent is clear:

- **`/crew gang-status`** — show all Crew features that originated from Gang, with the current verdict status of their CONDITIONAL conditions
- **Auto-escalate hook** — when a Crew kill-switch trips, automatically queue a Gang re-evaluation
- **Shared schemas** — Crew's roadmap-schema.yaml and Gang's evidence.schema.json are currently independent; could share an `assumption_id` namespace
- **Joint dashboards** — single board view: Gang verdicts + Crew phase status side by side

Contributions welcome.
