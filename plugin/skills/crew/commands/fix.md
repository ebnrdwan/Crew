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

## Step 4 — Locate + project-wide pattern scan (read-only, code-reviewer)

Dispatch code-reviewer in read-only mode. The agent does TWO things in one pass: locate the primary bug AND scan the rest of the codebase for the same pattern in other places.

```
READ-ONLY MODE — do not modify any files.

Bug: {description}
Reproduction: {repro_steps}
Failing test: .crew/fixes/{bug_id}/repro.test.ts

PART 1 — Locate the primary bug:
  1. The file + function + line where the bug originates
  2. The root cause (one paragraph)
  3. The fix strategy (what change is needed; do not implement yet)
  4. Confidence in the location: high | medium | low

PART 2 — Project-wide pattern scan (CRITICAL):
  Scan the entire codebase (excluding node_modules, vendor, .git,
  generated files) for occurrences of the same bug pattern.

  For each candidate site, classify the match strength:
    - EXACT     — same function/method, same input handling, same risk
    - FUZZY     — similar logic structure (e.g. another `replace(/'/g, ...)`
                  on user input that doesn't escape backticks the same way)
    - LOOSE     — superficially similar but different context; flag for
                  human review, do not assume it's the same bug

  Use the bug's root cause as the search criterion, not just the symptom.
  Example: if the bug is "regex doesn't escape backticks in password
  comparison", scan for ALL regex usage on auth-related fields — not
  just the specific function with the bug.

Output to .crew/fixes/{bug_id}/locate.md with sections:
  ## Primary location
  - file:line
  - root cause (paragraph)
  - fix strategy

  ## Adjacent sites (candidates for the same fix)
  | Site | Match | Confidence | Why similar |
  |---|---|---|---|
  | src/auth/oauth.ts:34 | EXACT | high | same regex pattern in password handler |
  | src/profile/edit.tsx:47 | FUZZY | medium | similar regex but different field; may need same escape |
  | src/api/login.ts:12 | LOOSE | low | uses regex on input but different purpose |

  ## Confidence
  - location: high | medium | low
  - scan completeness: high | medium | low (any directories you couldn't fully scan?)
```

When code-reviewer completes:
- Read `.crew/fixes/{bug_id}/locate.md` and parse the adjacent-sites table
- Update `current-feature.yaml#fix.located_at` and `fix.adjacent_sites`
- If location confidence is `low`, fall back to `/crew investigate` — fix is too risky without better location

---

## Step 4.5 — Confirm fix scope (NEW — adjacent-site decision)

**Skip this step if the adjacent-sites table is empty.**

Otherwise, this is the user-checkpoint that decides whether the fix propagates beyond the primary site. Auto-applying to fuzzy/loose matches can turn one bug into N regressions, so the user picks scope explicitly.

Dispatch `AskUserQuestion`:

```
AskUserQuestion({
  questions: [{
    header: "Adjacent sites found",
    question: "Found {N} adjacent sites with the same bug pattern. {N_exact} EXACT match, {N_fuzzy} FUZZY, {N_loose} LOOSE. How to handle?",
    multiSelect: false,
    options: [
      {label: "★ Fix all EXACT + FUZZY sites (recommended)", description: "Apply the same fix to {N_exact + N_fuzzy} sites. LOOSE matches deferred to a separate review. Test suite must pass for ALL sites."},
      {label: "Show me each — I'll pick", description: "Multi-select review: tick each site to include. Best when scope is sensitive or matches are ambiguous."},
      {label: "Fix only primary site", description: "Treat adjacent sites as out-of-scope. Auto-create a follow-up /crew investigate spike for them so they're not lost."},
      {label: "Fix only EXACT matches", description: "Conservative: skip FUZZY too, those need human review. Creates spike for FUZZY + LOOSE."}
    ]
  }]
})
```

### On "Show me each" — multi-select review

Dispatch a second `AskUserQuestion` with `multiSelect: true`:

```
{
  header: "Pick adjacent sites to include",
  question: "Tick the sites that should also receive this fix.",
  multiSelect: true,
  options: [
    // One option per non-primary site, with match strength + reason
    {label: "src/auth/oauth.ts:34 (EXACT)", description: "same regex pattern in password handler"},
    {label: "src/profile/edit.tsx:47 (FUZZY)", description: "similar regex but different field; may need same escape"},
    {label: "src/api/login.ts:12 (LOOSE)", description: "uses regex on input but different purpose"}
  ]
}
```

### On "Fix only primary site" or "Fix only EXACT matches" — auto-spike for the rest

For sites NOT included in the fix scope, write a follow-up spike to `.crew/investigations/SPK-{date}-{bug_id}-adjacent.yaml`:

```yaml
spike_id: SPK-{date}-{bug_id}-adjacent
type: bug
topic: "Adjacent occurrences of {bug_id} pattern not included in the original fix"
deferred_sites:
  - {file:line, match_strength, reason}
  - ...
parent_bug: {bug_id}
status: pending  # user can run /crew investigate {spike_id} later
```

Also push a spike card to GitHub Projects (if `config.github.enabled`) with status `Planned` so it's visible on the board.

### Record the decision

Write the chosen scope to `current-feature.yaml#fix.scope`:

```yaml
fix:
  scope:
    primary: src/auth/login.ts:42
    adjacent_included:
      - src/auth/oauth.ts:34
    adjacent_deferred:
      - src/profile/edit.tsx:47   # → SPK-{date}-{bug_id}-adjacent
      - src/api/login.ts:12       # → SPK-{date}-{bug_id}-adjacent
    decision: "Fix all EXACT + FUZZY sites"
    decided_at: 2026-05-08T...
```

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

## Step 6 — Fix (apply across all confirmed scope sites)

Dispatch the chosen engineer(s). The prompt now includes the FULL fix scope from Step 4.5 (primary + adjacent_included), so the engineer makes coordinated changes across all sites in one pass:

```
Fix this bug at ALL of the following sites coherently:

Bug:           {description}
Root cause:    {root_cause_from_locate.md}
Fix strategy:  {fix_strategy_from_locate.md}
Failing test:  .crew/fixes/{bug_id}/repro.test.ts

Sites to fix (from .crew/current-feature.yaml#fix.scope.adjacent_included +
              fix.scope.primary):
  1. src/auth/login.ts:42   (PRIMARY)
  2. src/auth/oauth.ts:34   (EXACT match — same fix)
  3. src/profile/edit.tsx:47 (FUZZY match — apply same logic, adjusted for context)

Constraints:
  - The failing test MUST pass after your change
  - Do not modify the test (the test is the spec)
  - Apply the SAME logical fix at each site. The implementation may
    differ slightly (different identifiers, different surrounding code)
    but the behavioral change must be identical.
  - Add a brief code comment near each fix site:
      // BUG-{YYYYMMDD}-{slug}: {one-line cause} (also fixed at: site2, site3)
  - If your change touches a public interface or contract, update
    docs/api-contract.md and the corresponding TypeScript types
  - For each site, write a one-line summary of what you changed there
    to .crew/fixes/{bug_id}/changes-{site_index}.md
  - If a site looks superficially similar to the primary but on closer
    inspection is NOT actually the same bug, leave it untouched and
    record this in .crew/fixes/{bug_id}/scope-adjustments.md with the
    reason — do not silently skip
```

Wait for the engineer to complete. Run `crew-budget-log.sh` with actual tokens (multiplied by site count if multi-site).

**For sequential strategy (Step 5),** dispatch the second agent only after the first completes successfully and the regression test passes. The second agent's prompt should also include the same scope list — they need to know what the first agent already changed.

**For parallel strategy,** all confirmed sites must be in the same agent's scope (don't split sites across agents — that's the failure mode parallel mode is supposed to avoid). Parallel applies to UI-engineer + API-engineer working on different layers, not different sites within the same layer.

After all engineers complete, validate that EVERY site in `fix.scope.adjacent_included` has a corresponding `changes-{N}.md` file. If any site is missing, the engineer skipped it — re-dispatch with that specific site as the only remaining task.

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

## Step 7.5 — Impact report (NEW — written to `.crew/fixes/{bug_id}/IMPACT.md`)

Generate a structured report so the user (and anyone reviewing the PR) can see exactly what changed, what's at risk, and what to monitor. The report is the **written record** of the fix; the user sees it before merge and can attach it to the PR description.

Synthesize from:
- `git diff` of the fix branch (what files / lines changed)
- `locate.md` (root cause + adjacent risk)
- `changes-*.md` (per-site change summary from engineer)
- `verify.md` (test results)
- `current-feature.yaml#fix.scope` (which sites were fixed vs deferred)

### Report structure

Write to `.crew/fixes/{bug_id}/IMPACT.md`:

```markdown
# Impact Report — {bug_id}

> {one-line bug summary}
> Severity: {severity} · Sites fixed: {N} · Tests: {pass_count} / {total_count}

---

## Files modified

| File | Lines | What changed |
|---|---|---|
| src/auth/login.ts | +4 / −2 | Escape backticks before regex compare |
| src/auth/oauth.ts | +4 / −2 | Same fix, OAuth path |
| tests/auth.test.ts | +28 / −0 | Regression test for both paths |
| docs/api-contract.md | +3 / −0 | New error_code field on /auth/login response |

Total: {N files}, +{lines added} / −{lines removed}

## Public interfaces changed

For each change, classify:
- **BREAKING** — consumers must update
- **ADDITIVE** — non-breaking; existing consumers keep working
- **INTERNAL** — no public surface; safe to ignore

| Interface | Kind | Detail |
|---|---|---|
| POST /auth/login response | ADDITIVE | New `error_code` field; existing fields unchanged |
| LoginForm.onSubmit error type | INTERNAL | Type narrowed but not exported |

## Blast radius (who's affected by these changes)

**Direct callers of changed functions:**
- `LoginForm.handleSubmit` → called by `SignInPage.tsx`, `OAuthCallback.tsx`
- `validatePassword` → called by 3 places (all in auth/)

**Test files re-run:**
- 12 test files touched the affected modules; all 12 passing

**Generated/build artifacts that may need refresh:**
- `dist/auth/*` (next build will pick up)
- TypeScript types regenerated for the response change

## Behavior changes

What changed *semantically*, not just syntactically. This is the section the PR reviewer reads first.

- Apostrophes / backticks in passwords are now properly escaped (was: 500 error). Affected users: anyone with these characters in their password (~3% based on prior support tickets).
- `/auth/login` 4xx responses now include `error_code` for programmatic handling. Frontend can switch from string-matching the message to checking the code.

## Risk areas (NOT fixed in this PR — needs human review)

Sites the pattern scan flagged but were NOT included in the fix scope:

| Site | Reason deferred | Tracked as |
|---|---|---|
| src/profile/edit.tsx:47 | FUZZY match; different field context | SPK-2026-05-08-{bug_id}-adjacent |

Also: any code path that depended on the *old* error format (string "Invalid input") will keep working because we added `error_code` rather than replacing the message — but log parsers and analytics that match on the message string should be reviewed.

## Production monitoring

After deploy, watch:

- `auth.login.500_rate` — should drop to ~0 (if it was elevated)
- `auth.error_code` — new metric label; expect it to populate within 5 min of deploy
- `auth.login.success_rate` — should NOT change (we fixed an error path, not a success path)
- Slack channel `#auth-alerts` — page on any new 5xx pattern in the first hour

## Rollback plan

If anything goes wrong post-deploy:

```bash
git revert {merge_commit_sha}
{deploy_command}
```

Reverting is safe because the change is additive (new fields, new error code). No data migration to undo. No DB schema change.

## Test coverage

| Suite | Before | After | Delta |
|---|---|---|---|
| Unit | 87.2% | 89.4% | +2.2% (regression test) |
| Integration | 76.0% | 76.0% | unchanged |
| E2E | (n/a) | (n/a) | (n/a) |

## Sign-off checklist (for human reviewer)

- [ ] Read the Behavior changes section
- [ ] Confirmed the Risk areas list is acceptable (or filed follow-up)
- [ ] Confirmed Production monitoring metrics exist (or filed dashboard ticket)
- [ ] Verified Rollback plan can actually run from current state
```

### Display to the user

After writing the file, print to the user:

```
✓ Impact report ready: .crew/fixes/{bug_id}/IMPACT.md
   {N} files modified · {N_breaking} breaking · {N_additive} additive · {N_internal} internal
   {N_deferred} adjacent sites deferred → {spike_id}
   Coverage: {before}% → {after}% ({+delta}%)

   Read the report before merge. Attach it to the PR description.
```

If `config.github.attach_impact_to_card: true`, append the IMPACT.md content (or a link to it in the repo) to the bug card body via `updateProjectV2DraftIssue` GraphQL mutation. Default `false` — keeps card body lean unless the team wants verbose cards.

---

## Step 8 — Push card update (`In Review`)

```
/crew push   → update-status mode → "In Review"
```

If `config.github.update_body_on_phase_change: true`, also rewrite the bug card body to include the populated Root Cause + Fix Verification sections from `locate.md` and `verify.md`.

---

## Step 9 — Merge + deploy

Same as drive's Completion step, with the impact report referenced in the commit message:

1. Ask user: "Ready to merge `fix/{bug_id}` to main?"
2. Compose the merge commit message including a condensed impact summary:
   ```
   fix({bug_id}): {one-line summary}
   
   Root cause: {root_cause_one_line}
   Sites fixed: {N} ({list of file paths})
   Sites deferred to {spike_id}: {N}
   Public interfaces: {N_breaking} breaking · {N_additive} additive
   Tests: {pass_count}/{total_count} passing · coverage {+delta}%
   
   See .crew/fixes/{bug_id}/IMPACT.md for full report.
   ```
3. Merge feature branch
4. Update `.crew/roadmap.yaml`: bug status → `done`. If a deferred-sites spike was created in Step 4.5, also add a roadmap entry pointing at it.
5. **If `/crew deploy` runs successfully** after merge → push card status → `Shipped`. Otherwise leave at `In Review` so the board shows "merged but not yet in production."

---

## Step 10 — Suggest follow-up (only on PASS verdict)

When the fix lands cleanly, dispatch one short `AskUserQuestion` to capture follow-up. Options adapt based on what happened during the fix:

```
AskUserQuestion({
  questions: [{
    header: "Anything to follow up?",
    question: "Fix verified at {N} sites. Impact report: .crew/fixes/{bug_id}/IMPACT.md. Common follow-ups — pick any:",
    multiSelect: true,
    options: [
      {label: "No, we're done", description: "Close the bug card and move on"},

      // Show only if Step 4.5 deferred any adjacent sites:
      {label: "Investigate the {N} deferred sites", description: "Run /crew investigate {spike_id} for the adjacent sites that weren't included in this fix"},

      // Always show:
      {label: "Add a regression rule to lint config", description: "Prevent this bug class from recurring (manual step; suggest a rule based on the root cause)"},
      {label: "Document the cause in a runbook", description: "Dispatch doc-writer to add a troubleshooting entry referencing IMPACT.md"},

      // Show only if the impact report flagged any BREAKING change:
      {label: "Notify downstream consumers", description: "Generate a heads-up message for teams that depend on the changed interface"}
    ]
  }]
})
```

Single click; default is "No, we're done." If the user picks "Investigate the deferred sites," auto-invoke `/crew investigate {spike_id}` with the deferred-sites context pre-loaded — the spike already exists from Step 4.5; this just kicks off its execution.

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
