# /crew gaps — Gap-Finder Audit & Fix Pipeline

Audit a live application for UI gaps, analyze findings, create fix requirements, implement fixes, and verify.

## Usage
```
/crew gaps                      → Interactive: ask for URL
/crew gaps [url]                → Audit the given URL
/crew gaps [url] --quick        → Quick scan: buttons + links only
/crew gaps [url] --a11y         → Accessibility audit only
/crew gaps [url] --responsive   → Responsive audit only
/crew gaps [url] --compare [competitor-url]  → Audit + competitor comparison
```

## Prerequisites
- `.crew/current-phase.yaml` must exist
- `.crew/roadmap.yaml` must exist
- Claude in Chrome MCP must be configured (required for gap-finder agent)
- Target URL must be accessible

## Design Context (Impeccable Integration)

The gaps pipeline reads `.impeccable.md` from the project root and uses design principles as additional audit criteria:

- **Phase 1 (Gap Audit):** gap-finder evaluates UI against design principles in addition to functional gaps
  - Semantic color violations (e.g., decorative use of green/red/blue/yellow)
  - Missing states that break "confidence through clarity" (no loading, empty, or error states)
  - Useless widgets that violate "earned simplicity"
  - Spacing/alignment issues that break "professional craft" (4px grid)
  - Hierarchy problems that violate "data density with hierarchy"
  - Design principle violations are classified as **P2 Medium** gaps
- **Phase 2 (Gap Analysis):** pm-architect creates fix requirements referencing the specific design principle violated
- **Phase 4 (Fix Implementation):** ui-engineer receives `.impeccable.md` context for all UI fixes

---

## Flow

### Step 0: Prerequisites Check

1. **Crew initialized?**
   ```
   Check: .crew/current-phase.yaml exists
   If missing → HALT: "Run /crew init or /crew onboard first."
   ```

2. **Roadmap exists?**
   ```
   Check: .crew/roadmap.yaml exists
   If missing → HALT: "Roadmap required. Run /crew onboard to generate one."
   ```

3. **Claude in Chrome MCP?**
   ```
   Check: Search for Chrome MCP tools (navigate, read_page, computer)
   If not found → HALT:
     "Gap-finder requires Claude in Chrome MCP to interact with web pages.
      Please connect Claude in Chrome from the MCP tools menu, then try again."
   ```

All checks passed → proceed to Step 1.

---

### Step 1: URL Input

#### If URL provided as argument
Validate the URL:
- Must be a valid URL (http:// or https://)
- Test accessibility: `curl -s -o /dev/null -w "%{http_code}" {url}`
- If not reachable → "URL not reachable. Is the app running? Check the URL and try again."

#### If no URL provided (interactive mode)
```
Enter the URL to audit:

Suggestions:
  - http://localhost:3000 (common dev server)
  - http://localhost:5173 (Vite dev server)
  - http://localhost:4173 (Vite preview)
  - http://localhost:8080 (common backend)

Or enter a deployed preview URL.
```

Auto-detect: Check common ports and show which ones are responding.

#### Parse flags
- `--quick` → Set audit mode to "quick" (buttons + links only)
- `--a11y` → Set audit mode to "accessibility"
- `--responsive` → Set audit mode to "responsive"
- `--compare {url}` → Set competitor URL for Phase 4 comparison

---

### Phase 1: Gap Audit — gap-finder agent

**Dispatch:** Launch `gap-finder` agent with prompt:

```
Audit the web application for UI gaps:

URL: {url}
Mode: {full / quick / a11y / responsive}
{If compare flag}: Also audit competitor: {competitor-url}

Project context:
  - Roadmap: [Read .crew/roadmap.yaml for acceptance criteria]
  - Current feature: [Read .crew/current-feature.yaml if exists]
  - Design principles: [Read .impeccable.md for brand and design guidelines]

Run the audit pipeline:
  1. INVENTORY: Map all interactive elements
  2. INTERACT: Test every element (click, form, navigation, state)
  3. INSPECT: Accessibility (WCAG 2.1 AA) + responsive checks
  4. DESIGN AUDIT: Evaluate against .impeccable.md design principles:
     - Semantic color compliance (green=gains, red=losses, blue=action, yellow=warning — no decorative use)
     - Data density with hierarchy (is the most important info visually prominent?)
     - Earned simplicity (any useless/decorative elements that don't earn their place?)
     - Professional craft (4px grid spacing, smooth transitions, pixel-perfect alignment)
     - Confidence through clarity (are all states clear? loading/empty/error handled?)
     Flag violations as P2 Medium with category "Design Principle Violation"
  {5. COMPARE: If competitor URL provided, run comparison}
  6. REPORT: Generate prioritized gap report with a separate "Design Compliance" section

Output: Save report to docs/gap-reports/{YYYY-MM-DD}-gap-report.md
```

**Wait for agent to complete.**

#### Present Results
```
Gap Audit Complete

URL: {url}
Elements Tested: {N}

Summary:
  P0 Critical: {N} — {brief description of worst one}
  P1 High:     {N}
  P2 Medium:   {N}
  P3 Low:      {N}

Top Findings:
  1. {GAP-001}: {title} (P0)
  2. {GAP-002}: {title} (P1)
  3. {GAP-003}: {title} (P1)

Full report: docs/gap-reports/{date}-gap-report.md
```

**>>> USER APPROVAL GATE**
```
Review the gap audit findings above.

Options:
  1. Analyze gaps and create fix requirements (proceed to Phase 2)
  2. View full report details
  3. Re-run audit with different options
  4. Stop (keep report only)

Select:
```

If user selects 4 (stop), commit the report and end:
```bash
git add docs/gap-reports/
git commit -m "docs(gap-finder): gap audit report - {N} findings"
```

---

### Phase 2: Gap Analysis — pm-architect agent

**Dispatch:** Launch `pm-architect` agent with prompt:

```
Analyze the gap audit findings and create fix requirements:
Design context: [Read .impeccable.md for design principles]

Gap report: [Read docs/gap-reports/{date}-gap-report.md]
Roadmap: [Read .crew/roadmap.yaml]
Project context: [Read .crew/project-context.md]

Tasks:
1. For each P0 and P1 gap: Create a fix requirement with:
   - Description of the issue
   - User story (As a user, I expect... so that...)
   - Acceptance criteria (GIVEN/WHEN/THEN)
   - Effort estimate (S/M/L)
2. For P2 gaps: Group into themes and create summary requirements
   - Group "Design Principle Violation" gaps by principle (semantic color, earned simplicity, etc.)
   - Reference the specific .impeccable.md principle in each fix requirement
3. RICE score each fix requirement
4. Recommend implementation order

Output: Save to docs/pm-architect/gap-fixes/{date}-fix-requirements.md
```

**Wait for agent to complete.**

#### Present Results
```
Fix Requirements Created

P0/P1 fixes (individual stories):
  1. FIX-001: {title} — RICE: {score}, Effort: {S/M/L}
  2. FIX-002: {title} — RICE: {score}, Effort: {S/M/L}
  ...

P2 themes (grouped):
  1. {theme}: {N} issues — Effort: {estimate}
  ...

Total fix stories proposed: {N}
Estimated total effort: {sum}

Full requirements: docs/pm-architect/gap-fixes/{date}-fix-requirements.md
```

**>>> USER APPROVAL GATE**
```
Review the fix requirements above.

Options:
  1. Add all to roadmap (proceed to Phase 3)
  2. Select which fixes to include
  3. Request changes to requirements
  4. Stop (keep requirements only)

Select:
```

---

### Phase 3: Roadmap Integration

This phase runs inline (no agent dispatch).

1. **Read** `.crew/roadmap.yaml`

2. **Epic Management:**
   ```
   Add fix stories to:
     1. Existing epic: {list epics}
     2. New epic: "Gap Fixes — {date}"

   Select:
   ```

3. **Create Stories** from fix requirements:
   - Each P0/P1 fix → individual story with acceptance criteria
   - P2 theme groups → one story per theme
   - Set `priority` from RICE analysis
   - Set `status: backlog`
   - Set `assigned` based on gap type:
     - UI gaps → `ui-engineer`
     - API/backend gaps → `api-engineer`
     - Both → `both`

4. **Update** `.crew/roadmap.yaml`

5. **Create tracking state:**
   ```yaml
   # .crew/current-feature.yaml (or update existing)
   feature: gap-fixes-{date}
   branch: fix/gap-fixes-{date}
   gaps_phase: roadmap_integrated
   original_report: docs/gap-reports/{date}-gap-report.md
   fix_stories: [S{epic}-{seq}, ...]
   started: {ISO date}
   ```

6. **Create branch:**
   ```bash
   git checkout -b fix/gap-fixes-{date}
   ```

7. **Commit:**
   ```bash
   git add .crew/roadmap.yaml .crew/current-feature.yaml docs/pm-architect/gap-fixes/
   git commit -m "docs(gaps): add {N} fix stories from gap audit"
   ```

8. **Push enhancement cards to GitHub Projects** (auto-trigger; skipped if `config.github.enabled: false` or no boards configured):

   Gaps produce **enhancement** cards, not feature cards — they're improvements to existing functionality, not new builds. Card type is locked to `enhancement` regardless of `current-feature.yaml#card_type`.

   **Card-per-fix vs card-per-batch — pick one strategy via `AskUserQuestion`:**

   ```
   AskUserQuestion({
     questions: [{
       header: "Card granularity",
       question: "How to surface the {N} fix stories on GitHub Projects?",
       multiSelect: false,
       options: [
         {label: "One card per fix story", description: "Each P0/P1 fix becomes its own card. Best when fixes will be assigned to different engineers"},
         {label: "One card for the batch", description: "Single 'Gap Fixes — {date}' card listing all fixes in body. Best for small batches or when one engineer owns the cleanup"},
         {label: "Skip — manage on roadmap only", description: "Do not push to GitHub Projects; track in .crew/roadmap.yaml only"}
       ]
     }]
   })
   ```

   **Per-fix mode:** for each fix story, set:
   ```yaml
   # in .crew/current-feature.yaml temporarily, then loop /crew push per story
   feature_id: {story_id}
   card_type: enhancement
   ```
   Run `/crew push` once per story. Each card starts with status `Building` (not `Planned`) because gap-fixes skip Phase 1–2.5 — they go straight to implementation. Card body uses the `enhancement` skeleton from `references/card-skeletons.md`, populated from the fix story's RICE/acceptance data.

   **Batch mode:** set `feature_id: gap-fixes-{date}`, `card_type: enhancement`, run `/crew push` once. Card body lists all fix stories with checkboxes; status starts at `Building`.

   **Source linkage:** every card body includes the link to `docs/gap-reports/{date}-gap-report.md` so reviewers can trace back to which audit produced the fix.

**>>> USER APPROVAL GATE**
```
Roadmap updated:
  - Epic: {epic name}
  - Fix stories: {N} stories added
  - Branch: fix/gap-fixes-{date}
  - GitHub cards: {pushed | skipped}

→ Ready to implement fixes? [Yes / Edit stories / Stop]
```

---

### Phase 4: Fix Implementation — engineers

**For each fix story**, dispatch the appropriate engineer based on `assigned` field:

| Gap Type | Agent | Example |
|----------|-------|---------|
| Dead button, missing state, UI | `ui-engineer` | Button doesn't respond to click |
| API error, missing endpoint | `api-engineer` | Form submit returns 500 |
| Both UI + API | Dispatch both sequentially | Form validation + backend validation |

**When dispatching `ui-engineer` for UI fixes, always include:**
```
Design context: Read .impeccable.md for brand personality, aesthetic direction, and design principles.
All UI fixes MUST comply with the 5 design principles:
  1. Data density with hierarchy  2. Semantic color is law
  3. Earned simplicity  4. Professional craft  5. Confidence through clarity
Use CSS variable tokens from index.css. Dark theme only.
```

**For each story:**
1. Create task branch: `fix/gap-fixes-{date}/{story-id}-{description}`
2. Fix the issue per acceptance criteria
3. Commit with: `fix: {GAP-ID} {description}`
4. Merge task branch back to fix branch

**Wait for all fixes to complete.**

**Update state:**
```yaml
gaps_phase: fixes_implemented
```

**>>> USER APPROVAL GATE**
```
Fixes implemented:
  - {N} stories completed
  - Files changed: {summary}

→ Ready for verification re-audit? [Yes / Continue fixing / Stop]
```

---

### Phase 5: Verification Re-audit — gap-finder agent

**Dispatch:** Launch `gap-finder` agent with prompt:

```
Verification re-audit after implementing fixes:

URL: {same URL from Phase 1}
Original gap report: [Read docs/gap-reports/{original-date}-gap-report.md]

Tasks:
1. Run full audit pipeline on the same URL
2. For each original P0/P1 gap: Verify it's now fixed
3. Note any NEW gaps introduced by fixes
4. Compare original vs current state

Output: Save to docs/gap-reports/{date}-verification-report.md
```

**Wait for agent to complete.**

#### Present Comparison
```
Verification Re-audit Complete

Original → Now:
  P0 Critical: {original} → {current} ({resolved} fixed, {new} new)
  P1 High:     {original} → {current} ({resolved} fixed, {new} new)
  P2 Medium:   {original} → {current}
  P3 Low:      {original} → {current}

Resolved gaps: {list}
Remaining gaps: {list}
New gaps: {list if any}

Verification report: docs/gap-reports/{date}-verification-report.md
```

**>>> USER APPROVAL GATE**

**If P0/P1 remaining > 0:**
```
{N} Critical/High gaps still remain.

Options:
  1. Fix remaining gaps (loop back to Phase 4) — {loop count}/2 iterations used
  2. Accept current state
  3. Stop

Select:
```

Maximum 2 fix-verify iterations. After 2 loops:
```
Maximum fix iterations reached (2).
Remaining gaps require manual investigation.
→ Accept current state? [Yes / Stop]
```

**If all P0/P1 resolved:**
```
All Critical and High gaps resolved!
→ Finalize? [Yes / Stop]
```

---

### Completion

1. **Merge fix branch:**
   ```
   Ready to merge fix/gap-fixes-{date}?
   [Yes / Keep branch open]
   ```

2. **Update roadmap:** Set fix stories to `status: done`

3. **Update state:**
   ```yaml
   gaps_phase: complete
   completed: {ISO date}
   ```

4. **Summary:**
   ```
   Gap-Fix Pipeline Complete!

   Original audit: {date}
   URL: {url}

   Results:
     - Gaps found: {original total}
     - Gaps fixed: {resolved}
     - Gaps remaining: {remaining}
     - Fix stories: {N} completed

   Outputs:
     - Original report: docs/gap-reports/{date}-gap-report.md
     - Fix requirements: docs/pm-architect/gap-fixes/{date}-fix-requirements.md
     - Verification report: docs/gap-reports/{date}-verification-report.md

   Branch: fix/gap-fixes-{date} → {merged / still open}
   ```

---

## Resume Capability

If the user runs `/crew gaps` and `.crew/current-feature.yaml` exists with a `gaps_phase` field:

```
Resuming gap-fix pipeline for: {feature}
Last completed phase: {gaps_phase}
Original report: {path}

→ Continue from {next phase}? [Yes / Start fresh audit / View status]
```

`gaps_phase` values: `audit_complete`, `analysis_complete`, `roadmap_integrated`, `fixes_implemented`, `verification_complete`, `complete`
