# /crew fix — Reproduce, locate, fix, verify

Used when **a bug is known**. Produces a `bug` card on the GitHub Projects board and runs through reproduce → locate → fix → verify. Skips Crew Phase 1 (Strategy) and Phase 2 (Design) entirely — for known bugs, the scope is the symptom.

If the bug isn't reproducible or the cause is unclear, run `/crew investigate` first and let it suggest `/crew fix` when confidence is high.

---

## Usage

```
/crew fix                                   → Interactive: ask for bug details
/crew fix "issue description"               → Quick-start with description
/crew fix S2-04                             → Fix a story already in roadmap.yaml
/crew fix --severity {critical|high|medium|low} "..."
/crew fix --from-spike SPK-{date}-{slug}    → Continue from /crew investigate
```

---

## Step 0 — Intake

If invoked from `/crew investigate` (Step 5 high-confidence path), most of intake is pre-populated. Skip directly to Step 2.

Otherwise dispatch `AskUserQuestion`:

```
AskUserQuestion({
  questions: [{
    header: "Severity",
    question: "How severe is this bug? (Drives priority on the board.)",
    multiSelect: false,
    options: [
      {label: "Critical — blocking shipping or data loss", description: "P1, drop everything. Rollback may be required."},
      {label: "High — frequent / user-visible failure", description: "P1, fix this sprint."},
      {label: "Medium — sometimes-reproduces / cosmetic", description: "P2, fix when convenient."},
      {label: "Low — edge case / minor", description: "P3, backlog."}
    ]
  }]
})
```

Then ask for:
- **Description** — 1–2 sentences
- **Steps to reproduce** — concrete, testable
- **Expected** — what should happen
- **Actual** — what happens instead
- **Affected platforms** — web / iOS / Android / API / all

Write to `.crew/current-feature.yaml`:

```yaml
mode: fix
fix:
  bug_id:    BUG-{YYYYMMDD}-{slug}     # auto-generated
  severity:  high
  priority:  P1                         # derived from severity
  description: "Login form crashes on Safari iOS when password contains apostrophe"
  reproduction:
    - "Open /login in Safari iOS"
    - "Enter password 'abc'def'"
    - "Tap Sign In"
  expected: "Form submits, user logged in or sees auth error"
  actual:   "JS error 'Unexpected token'; form does not submit"
  platforms: [ios-safari]
  source_spike: null                    # set if --from-spike used
  located_at: null                      # set after Step 4
  started: 2026-05-08T...
```

---

## Step 1 — Profile + budget check

```bash
bash {plugin_root}/scripts/crew-profile-check.sh \
  --feature-description "fix: {description}"

bash {plugin_root}/scripts/crew-budget-check.sh \
  --op-type code_reviewer \
  --feature-id {bug_id} \
  --phase 3 \
  --next-step locate_root_cause
```

If budget check returns `stop` → write checkpoint, schedule resume, exit. Same pattern as drive.

---

## Step 2 — Push bug card (`Building` status)

```
/crew push   → create mode, card_type: bug
```

Card body filled from the `bug` skeleton in `references/card-skeletons.md`:

- Reproduction steps (from intake)
- Expected / Actual
- Root cause section (📝 Live — populated after Step 4)
- Fix verification plan (Step 7)
- Regression risk areas (✏️ Manual — team fills)

Custom fields set on the card:
- `Priority` — derived from severity (Critical/High → P1, Medium → P2, Low → P3)
- `Source` — `manual` (or `investigation` if `--from-spike` was used)
- Status field → `Building`

Cache `item_id` in `.crew/github-cards.yaml#features.{bug_id}.boards[*]`.

---

## Step 3 — Reproduce (verify the bug exists)

**Skip if `--from-spike` was used and the spike's repro status was `verified`.**

Otherwise:

1. Apply the reproduction steps from intake. If automated possible, write a failing test that captures the bug:
   ```javascript
   // .crew/fixes/{bug_id}/repro.test.ts
   it('should not crash on password with apostrophe', () => {
     // ... reproduction in test form
   });
   ```
2. Run the test — confirm it fails with the expected symptom.
3. **If repro fails (test passes when it shouldn't, or symptom doesn't reproduce)** → halt fix, suggest:
   ```
   Bug not reproducible from given steps. Either:
     - Refine reproduction steps and re-run /crew fix
     - Run /crew investigate first to locate the trigger
   ```
   Update bug card status to `In Review` (waiting on better repro), exit.

If repro succeeds, save the failing test as the **regression guard**.

---

## Step 4 — Locate (read-only, code-reviewer)

Dispatch code-reviewer in read-only mode:

```
READ-ONLY MODE — do not modify any files.

Bug: {description}
Reproduction: {repro_steps}
Failing test: .crew/fixes/{bug_id}/repro.test.ts

Find:
  1. The file + function + line where the bug originates
  2. The root cause (one paragraph)
  3. The fix strategy (what change is needed; do not implement yet)
  4. Risk: are there other call sites with the same bug?

Output to .crew/fixes/{bug_id}/locate.md with sections:
  ## Root cause
  ## Fix strategy
  ## Located at: file:line
  ## Adjacent risk
  ## Confidence: high | medium | low
```

When code-reviewer completes:
- Update `current-feature.yaml#fix.located_at` from the report
- If confidence is `low`, fall back to `/crew investigate` — fix is too risky without better location

---

## Step 5 — Choose fix dispatch strategy (CRITICAL — user decision)

Read `locate.md` to determine if the bug spans layers:

```
- UI only          → ui-engineer
- API only         → api-engineer
- Both UI + API    → ASK USER
```

If both layers are involved, dispatch `AskUserQuestion`:

```
AskUserQuestion({
  questions: [{
    header: "Fix dispatch strategy",
    question: "This bug spans both UI ({ui_file}) and API ({api_file}). Two agents fighting over related files is a common failure mode. How to dispatch?",
    multiSelect: false,
    options: [
      {label: "Sequential — UI first, then API", description: "Safer. UI fix may reveal API requires changes too. Default."},
      {label: "Sequential — API first, then UI", description: "Safer. API change may inform UI behavior. Choose when API contract is the actual bug."},
      {label: "Parallel — both at once", description: "Faster but risky. Only choose when scope is genuinely independent (different files, no contract overlap)."},
      {label: "API only — UI symptom is downstream", description: "Locate report says fix is API-side; UI behavior is correct given current API."}
    ]
  }]
})
```

Record the choice in `current-feature.yaml#fix.dispatch_strategy`.

---

## Step 6 — Fix (the actual code change)

Dispatch the chosen engineer(s) with this prompt:

```
Fix this bug:

Bug:           {description}
Located at:    {file:line}
Root cause:    {root_cause_from_locate.md}
Fix strategy:  {fix_strategy_from_locate.md}
Failing test:  .crew/fixes/{bug_id}/repro.test.ts

Constraints:
  - The failing test MUST pass after your change
  - Do not modify the test (the test is the spec)
  - Add a brief code comment near the fix referencing the bug ID:
      // BUG-{YYYYMMDD}-{slug}: {one-line cause}
  - If your change touches a public interface or contract, update
    docs/api-contract.md and the corresponding TypeScript types
```

Wait for the engineer to complete. Run `crew-budget-log.sh` with actual tokens.

For sequential strategy (Step 5), dispatch the second agent only after the first completes successfully and the regression test passes from the first agent's output.

---

## Step 7 — Verify (qa-engineer)

```bash
bash {plugin_root}/scripts/crew-budget-check.sh \
  --op-type qa_engineer \
  --feature-id {bug_id} \
  --phase 4 \
  --next-step verify_fix
```

Then dispatch qa-engineer:

```
Verify the fix for {bug_id}:

  1. Run the regression test at .crew/fixes/{bug_id}/repro.test.ts — must pass
  2. Run the full unit test suite — no new failures
  3. Run integration tests covering the affected files
  4. Run e2e on the affected user flow if exists
  5. Check adjacent risk areas from .crew/fixes/{bug_id}/locate.md

Output to .crew/fixes/{bug_id}/verify.md:
  ## Regression test result
  ## Full suite result
  ## Adjacent area test results
  ## Verdict: PASS | FAIL | PARTIAL
  ## Coverage of fix: percentage
```

If **verdict ≠ PASS**, do not advance. Surface the failure to the user via `AskUserQuestion`:
- "Tests are failing. Re-dispatch engineer with the failure log? / Halt and let me look? / Mark as accepted-with-known-issues?"

---

## Step 8 — Push card update (`In Review`)

```
/crew push   → update-status mode → "In Review"
```

If `config.github.update_body_on_phase_change: true`, also rewrite the bug card body to include the populated Root Cause + Fix Verification sections from `locate.md` and `verify.md`.

---

## Step 9 — Merge + deploy

Same as drive's Completion step:

1. Ask user: "Ready to merge `fix/{bug_id}` to main?"
2. Merge feature branch
3. Update `.crew/roadmap.yaml`: bug status → `done`
4. **If `/crew deploy` runs successfully** after merge → push card status → `Shipped`. Otherwise leave at `In Review` so the board shows "merged but not yet in production."

---

## Step 10 — Suggest follow-up (only on PASS verdict)

When the fix lands cleanly, dispatch one short `AskUserQuestion` to capture follow-up:

```
AskUserQuestion({
  questions: [{
    header: "Anything to follow up?",
    question: "Fix verified. Common follow-ups for this kind of bug — pick any:",
    multiSelect: true,
    options: [
      {label: "No, we're done", description: "Close the bug card and move on"},
      {label: "Audit adjacent files for the same pattern", description: "Dispatch /crew investigate --type bug 'same pattern in adjacent files'"},
      {label: "Add a regression rule to lint config", description: "Prevent this bug class from recurring (manual step)"},
      {label: "Document the cause in a runbook", description: "Dispatch doc-writer to add a troubleshooting entry"}
    ]
  }]
})
```

Single click; default is "No, we're done."

---

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Repro test passes when it shouldn't | Reproduction steps don't match the actual bug trigger | Run `/crew investigate` first; better repro |
| code-reviewer locate confidence = low | Bug is in code the agent can't easily read (compiled, obfuscated, vendor) | Manual locate; restart fix from Step 5 with `located_at` set |
| Engineer's fix breaks the regression test | Engineer changed the test file (forbidden) | Re-dispatch with stronger constraint; revert their test edit |
| qa-engineer verdict = FAIL | Fix is incomplete or wrong | User picks: re-dispatch with logs / halt / accept with known-issues |
| Sequential dispatch — second agent contradicts first | Layers actually were independent; first agent's interpretation was wrong | User reverts second agent, switches to "API only" dispatch and re-runs |
| Two agents in parallel mode wrote conflicting changes | Race on related files | Halt; rebase one branch; sequential next time |

---

## What this command does NOT do

- **Investigate unknown bugs.** That's `/crew investigate`. Run it first if location is unclear.
- **Auto-route to Gang.** Strategic decisions about whether a bug is worth fixing live with the user / Gang.
- **Skip the regression test.** No fix lands without a failing-then-passing test.
- **Modify the failing test.** The test is the spec. Engineer fixes the code, not the test.
