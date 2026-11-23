# /crew gang-import — Import a Gang evaluation as a Crew feature

When the user runs `/crew gang-import <slug>`, the goal is to read the
GO Package produced by the **Gang multi-agent business committee** and
seed Crew's roadmap with a properly-shaped feature entry.

This is the **Crew ↔ Gang** handoff. Gang answers "should we build it?";
Crew answers "how do we ship it?". The handoff carries forward the BRD,
technical architecture, risk register, and CONDITIONAL-GO conditions.

---

## Prerequisites

1. **Gang plugin installed** and available: the Gang plugin installed in this client, from any marketplace (in Claude Code its agents are named `gang:*`; to find its folder: `find ~/.claude/plugins/cache ~/.copilot/installed-plugins -path '*/skills/gang/SKILL.md' 2>/dev/null`).
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

Confirm both:
- `state.json`: `"advise"` is in `stages_completed` (else suggest the user run `/gang advise` first).
- The verdict, read from **`executive-brief.md`** in the same folder. `state.json` has no verdict field; Gang writes
  the verdict in the brief's verdict section (for example a `## Verdict` heading with a table, or a
  `### Verdict: CONDITIONAL-GO ...` line). It is `GO`, `CONDITIONAL-GO` or `NO-GO`. When the brief splits the decision
  (for example "the validation sprint is CONDITIONAL-GO, the full build is NO-GO"), import only what is GO or
  CONDITIONAL-GO and say which part. Refuse when everything is `NO-GO`. If the brief is missing, or the verdict cannot
  be read from it, stop and ask the user rather than guessing.

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

### Step 4: Build the epic and its stories

`.crew/roadmap.yaml` has `project`, `project_type`, `epics` and `phases` at the top level (schema:
`{crew_root}/skills/crew/schemas/roadmap-schema.yaml`, where `roadmap` only names that root object: the file has no
`roadmap:` key and no `features` list). Each epic holds its `stories[]`. Add **one new epic** for the evaluation,
with the next free epic number, and one story per deliverable the GO Package names (from `go-package/brd.md`
requirements, grouped into stories; without a GO Package, one story per in-scope item of `executive-brief.md`):

```yaml
# appended to the existing top-level list in .crew/roadmap.yaml
epics:
  - id: E<next>                       # next free epic number
    name: <evaluation_name from Gang state.json, prettified>
    scope: <backend|frontend|mobile|both|unknown>   # the work's true scope
    source:                           # Gang provenance (extra field, kept with the epic)
      origin: gang
      slug: <slug>
      session_id: <gang session_id>
      gang_card_url: <state.json.github_push.project_item_url if present>
      verdict: <GO|CONDITIONAL-GO>    # from executive-brief.md
      verdict_score: <weighted_average from scored-plans.md>
      conditions:                     # CONDITIONAL-GO only; [] for GO
        - text: <condition, copied verbatim from the executive brief>
          cleared: false            # true only once the user confirms the evidence
          evidence: null            # what proved it: a link, a test result, a decision
      kill_switches: <kill switches, copied verbatim>
      risks: <top 3 risks from the executive brief>
    stories:
      - id: S<epic number>-01
        title: <short title>
        priority: <Critical|High|Medium|Low>   # from Gang's priority (P1 -> High, P2 -> Medium, P3 -> Low)
        status: backlog
        assigned: <agent that will build it, e.g. ui-engineer, api-engineer>
        description: |
          <what to build, from the GO Package or executive brief>
        acceptance_criteria:
          - text: <criterion from go-package/brd.md, or the executive brief>
            met: false
        subtasks: []
```

Strategy is covered by the Gang evaluation: when the next phase is planned, these stories start at design. While
`source.verdict` is `CONDITIONAL-GO`, every entry in `source.conditions` must have `cleared: true` and its `evidence`
before any of the epic's stories enter `phase-3-implementation` (its pre-flight step 0.5 checks this). A condition is
cleared only when the user confirms the evidence; Crew never clears one by itself.

### Step 5: Append to roadmap & ask for confirmation

Show the user the proposed entry and ask:
> "Add this epic to `.crew/roadmap.yaml` (appended to the top-level `epics` list)? [yes / let me edit / cancel]"

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

### Step 7: Push card to GitHub Projects (auto-trigger)

If `config.github.enabled: true` and at least one board configured, run:

```
/crew push                  # invokes commands/push.md in create mode
```

The pushed card has source-origin metadata set to `gang`, which causes the card body skeleton to inject the `gang_link_line` — a backlink to the source Gang evaluation so the board surfaces provenance:

```markdown
**Gang origin:** [`<slug>`](.gang/features/<slug>/) · verdict <verdict_badge> · imported via gang-bridge
```

If the same Gang evaluation already pushed cards to GitHub Projects from gang's side (`/gang push`), the Crew card is **separate** — they live as parallel cards (Gang's "evaluation result" card + Crew's "live build status" card). This is intentional: gang's cards are point-in-time evaluation snapshots; crew's card is the live build state. They serve different audiences (decision auditors vs build-progress watchers).

Skipped silently if GitHub integration is disabled or no boards are configured.

---

### Step 8: Suggest next action

```
✓ Feature '<slug>' imported from Gang.
  Verdict: <verdict>  ·  Score: <score>/10  ·  Size: <size>
  GitHub card: <created on board #N | skipped>
  
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
