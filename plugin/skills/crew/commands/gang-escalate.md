# /crew gang-escalate — Escalate a Crew feature back to Gang for re-evaluation

When the user runs `/crew gang-escalate <feature-id>`, the goal is to
hand a feature **back** to Gang for fresh strategic evaluation — typically
because:

- Phase 2/3 artifacts revealed scope creep that invalidates the original BRD
- A CONDITIONAL-GO condition has changed (e.g. new market data, regulatory shift)
- The feature is stalling and needs an independent committee re-think
- A kill-switch tripped and we need a fresh GO/NO-GO

This is the inverse of `/crew gang-import`. It packages the current Crew
state into a context-brief that Gang's `/gang reinit` can consume.

---

## Steps

### Step 1: Locate the feature

Read `.crew/roadmap.yaml`. Find the entry where `id: <feature-id>` matches.
If not found, list available features and ask the user to pick.

### Step 2: Determine the escalation reason

Use `AskUserQuestion`:

- Header: "Why escalate to Gang?"
- Options:
  - **Scope creep** — "Phase 2/3 surfaced scope the original Gang verdict didn't cover"
  - **Condition change** — "A CONDITIONAL-GO condition assumption no longer holds"
  - **Kill switch tripped** — "A pre-committed kill switch fired; need fresh GO/NO-GO"
  - **Stalled feature** — "Feature blocked for >30 days; want independent re-eval"
  - **Other** — user describes

### Step 3: Gather current state

Collect from `.crew/`:
- The original `roadmap.yaml.features[<id>]` block (full)
- Phase artifacts: any `.crew/features/<id>/phase-N-*.md` files
- Phase status (`phase_status` field) — which phases passed, which are stuck

If a Gang session for this feature already exists at `.gang/features/<id>/`:
- Re-use the same slug for `/gang reinit`
- The escalation packs as **delta context** — what's changed since the original eval

If no prior Gang session:
- Initialise one: this becomes a fresh `/gang init` flow scoped to the escalation reason

### Step 4: Build the escalation context-brief

Write `.gang/features/<id>/escalation-from-crew.md`:

```markdown
# Escalation from Crew — <feature-id>

**Date:** <ISO-8601>
**Reason:** <selected reason from Step 2>
**Original Gang session:** <id if exists, else "none — first evaluation">

---

## What Crew has built

### Original feature spec
<copy roadmap.yaml entry>

### Phase progress
<status of each phase: passed / pending / blocked, with timestamps>

### What changed since the original Gang verdict
<user's free-text input + any concrete artifacts that contradict original assumptions>

---

## What we need from Gang

<framed by the escalation reason>:
- Scope creep → "Re-score the feature with the expanded scope; produce a new GO Package."
- Condition change → "Re-evaluate the CONDITIONAL-GO conditions against current evidence."
- Kill switch → "Fresh GO/NO-GO given the operational data that tripped the switch."
- Stalled → "Independent diagnosis: is this a build problem or a strategic problem?"

---

## Specific questions for the committee

<2-4 user-defined questions OR auto-generated from the escalation reason>
```

### Step 5: Suggest the Gang command

After writing the escalation context, output:

```
✓ Escalation packaged at .gang/features/<id>/escalation-from-crew.md

Next steps:
  1. cd into your project
  2. Run: /gang reinit  (preserves session_id, refreshes context with the escalation)
  3. The committee will re-think with your delta context as primary input
  4. When Gang produces a new verdict, run /crew gang-import <id> again to
     update the Crew roadmap with the fresh GO Package
```

### Step 6: Update Crew state

In `.crew/roadmap.yaml`, mark the feature:
```yaml
features:
  - id: <feature-id>
    escalations:
      - escalated_at: <ISO-8601>
        reason: <reason>
        gang_session_id: <id>
        status: pending-gang-verdict
    phase_status:
      "phase-3-implementation": paused-for-gang-reeval
```

This freezes Crew progression until Gang's new verdict is imported.

---

## Why this command exists

Gang's verdict is a snapshot. Reality moves. When Crew's execution
surfaces new evidence that contradicts Gang's assumptions, the right move
isn't to ignore it OR to make ad-hoc judgment calls — it's to send the
new evidence back to the committee and get a properly-reasoned new verdict.

This keeps the strategic narrative honest. CONDITIONAL-GO is supposed to
become unconditional GO once conditions resolve; if the project drifts
without ever validating those conditions, you end up shipping on a
verdict that no longer applies. `/crew gang-escalate` is the explicit
"the verdict is stale" button.
