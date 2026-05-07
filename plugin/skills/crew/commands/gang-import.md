# /crew gang-import — Import a Gang evaluation as a Crew feature

When the user runs `/crew gang-import <slug>`, the goal is to read the
GO Package produced by the **Gang multi-agent business committee** and
seed Crew's roadmap with a properly-shaped feature entry.

This is the **Crew ↔ Gang** handoff. Gang answers "should we build it?";
Crew answers "how do we ship it?". The handoff carries forward the BRD,
technical architecture, risk register, and CONDITIONAL-GO conditions.

---

## Prerequisites

1. **Gang plugin installed** and available — `~/.claude/plugins/marketplaces/gang-marketplace/`.
2. **Gang evaluation completed** through at least the `advise` stage. `deliver` is preferred (gives full GO Package).
3. **Crew initialised** in the project — `.crew/roadmap.yaml` exists.

If any prerequisite fails, tell the user exactly which one and stop.

---

## Steps

### Step 1: Locate the Gang evaluation

The argument `<slug>` is the evaluation name. Look in this order:

1. `.gang/features/<slug>/state.json` — feature-scope evaluation (preferred)
2. `.gang/projects/<slug>/state.json` — project-scope evaluation
3. `.gang/state.json` — flat / single-evaluation

If none found, list the available evaluations:
```
ls .gang/features/ .gang/projects/ 2>/dev/null
```
and ask the user to pick.

### Step 2: Verify the evaluation is push-ready

Read `state.json` and confirm:
- `"advise"` is in `stages_completed` (else suggest the user run `/gang advise` first)
- `verdict` is `GO` or `CONDITIONAL-GO` (refuse to import a `NO-GO`)

### Step 3: Read the GO Package (if deliver completed)

If `"deliver"` is in `stages_completed`, read these files and parse them:

| Source file | Crew artifact it seeds |
|-------------|------------------------|
| `go-package/brd.md` | `roadmap.yaml` epic description + acceptance criteria |
| `go-package/project-charter.md` | Phase ownership + timeline |
| `go-package/risk-register.md` | `roadmap.yaml` risks block |
| `go-package/data-model.md` | Phase 2.5 (API Architecture) input |
| `go-package/api-contracts.md` | Phase 2.5 endpoint inventory |
| `go-package/technical-architecture.md` | Phase 3 (Implementation) sequencing |

If `deliver` was NOT run, fall back to:
- `executive-brief.md` for verdict + scope
- `scored-plans.md` for the winning plan's strengths/risks
- `context-brief.md` for the problem statement

Tell the user the package is partial and recommend running `/gang deliver` first for richer import.

### Step 4: Build the feature entry

Use the Gang evaluation to populate a new entry under `roadmap.yaml.features`:

```yaml
features:
  - id: <slug>
    title: <evaluation_name from Gang state.json, prettified>
    source:
      origin: gang
      session_id: <gang session_id>
      gang_card_url: <state.json.github_push.project_item_url if present>
      verdict: <CONDITIONAL-GO|GO>
      verdict_score: <weighted_average from scored-plans.md>
      conditions: <list of CONDITIONAL-GO conditions, copied verbatim>
    epic: <inferred or asked>
    description: |
      <executive summary, 3-4 sentences from executive-brief.md>
    acceptance_criteria:
      - <copy from go-package/brd.md acceptance criteria, or executive brief if no GO Package>
    risks:
      - <top 3 risks, copied from executive brief>
    kill_switches:
      - <kill switches, copied verbatim>
    estimated_size: <S|M|L|XL — pulled from Gang's own scope estimate; check state.json.github_push.fields_applied.size>
    estimated_priority: <P1|P2|P3 — from gang state.json.github_push.fields_applied.priority>
    phase_status:
      "phase-1-strategy": skip   # gang already covered strategy
      "phase-2-design": pending
      "phase-2.5-api": pending
      "phase-3-implementation": pending
      "phase-4-quality": pending
      "phase-5-launch": pending
    notes: |
      Strategy phase covered by Gang evaluation. CONDITIONAL-GO conditions
      (above) MUST be cleared before promoting to phase-3-implementation.
```

### Step 5: Append to roadmap & ask for confirmation

Show the user the proposed entry and ask:
> "Add this to `.crew/roadmap.yaml`? [yes / let me edit / cancel]"

On `yes` → append; on `let me edit` → write to a temp file, open it for review;
on `cancel` → exit cleanly.

### Step 6: Update state

After successful import:

1. Append to `.crew/imports.yaml` (create if missing):
   ```yaml
   imports:
     - feature_id: <slug>
       imported_at: <ISO-8601>
       gang_session_id: <id>
       gang_verdict: <verdict>
   ```

2. If the Gang `state.json` has `github_push.project_item_id`, write back to
   the Gang state.json:
   ```json
   {
     "crew_import": {
       "imported_at": "<ISO-8601>",
       "feature_id": "<slug>"
     }
   }
   ```
   This closes the loop so Gang knows which evaluations have moved into execution.

### Step 7: Suggest next action

```
✓ Feature '<slug>' imported from Gang.
  Verdict: <verdict>  ·  Score: <score>/10  ·  Size: <size>
  
  CONDITIONAL-GO conditions still pending: <count>
  → Resolve conditions before phase-3-implementation activates.
  
  Next: Run /crew feature <slug> to enter phase-2-design.
```

---

## Reverse direction — Crew → Gang

If the user wants to ESCALATE a Crew feature back to Gang (e.g. mid-phase
re-evaluation, scope creep triggered a re-think), use `/crew gang-escalate`
instead. That command emits a context-brief from Crew's roadmap.yaml +
phase artifacts that Gang's `/gang reinit` can pick up.

---

## Why this command exists

Gang and Crew solve adjacent-but-distinct problems:

- **Gang** runs a 6-stage committee: discovery → analysis → debate → score → advise → deliver. Outputs a GO Package: BRD, charter, risk register, data model, API contracts.
- **Crew** runs a 6-phase delivery pipeline: strategy → design → API arch → implementation → quality → launch. Consumes BRDs/charters and orchestrates engineering agents to ship them.

Without this handoff command, you'd manually copy/paste between the two
plugins. With it, Gang's verdict travels intact into Crew's execution
state, including the CONDITIONAL-GO conditions that gate phase-3 activation.
