# /crew drive — End-to-End Product-Led Development

Drive a feature from discovery through deployment with integrated product analysis, architecture, implementation, and quality assurance.

## Usage
```
/crew drive              → Interactive: ask for feature name/description
/crew drive [name]       → Quick-start with feature name
```

## Prerequisites
- `.crew/current-phase.yaml` must exist (run `/crew init` or `/crew onboard` first)
- `.crew/roadmap.yaml` must exist
- Crew MCP configured (for C4 diagrams, blast radius) — optional but recommended
- No feature currently in progress (`.crew/current-feature.yaml` should not exist or have status `complete`)

## Design Context (Impeccable Integration)

The drive pipeline reads `.impeccable.md` from the project root at the start and threads design context through every phase:

- **Phase 1 (Discovery):** pm-architect uses design principles to evaluate competitor UX and identify design gaps
- **Phase 2 (Architecture):** Functional requirements include UI requirements aligned with design principles
- **Phase 3 (BRD):** BRD includes a "Design Compliance" section referencing `.impeccable.md` principles
- **Phase 4 (Roadmap):** UI stories include design principle compliance as acceptance criteria
- **Phase 5 (Implementation):** ui-engineer receives full design context from `.impeccable.md`
- **Phase 7 (Gap Audit):** gap-finder evaluates against design principles (semantic color, earned simplicity, etc.)

All agent dispatches that touch UI MUST include:
```
Design context: Read .impeccable.md for brand personality, aesthetic direction, and 5 design principles.
All UI work must comply: data density with hierarchy, semantic color is law, earned simplicity,
professional craft, confidence through clarity.
```

---

## Interactive Collaboration Pattern (CRITICAL)

The drive pipeline is **collaborative, not autonomous**. The user must be involved early and often so the feature matches their intent, not the model's assumptions.

### Rules

1. **Use `AskUserQuestion` for every decision point** — never ask in plain chat where the user must type. Present clickable options so the user can decide in one click.
2. **Multi-select where applicable** — if the question has multiple valid answers (which opportunities matter, which metrics to track, which NFRs are critical), use `multiSelect: true`.
3. **Always include a "Let Claude decide" option** — for users who want to move fast, or who don't have strong opinions on a specific decision.
4. **Always include a "Stop and clarify" option** — at every gate. If the user selects it, pause, answer their questions, then re-ask the original question.
5. **Clarification loop** — if the user asks a question mid-flow (not matching any option), answer it fully, then re-present the same `AskUserQuestion` to continue. The drive pipeline pauses, it never abandons state.
6. **Resume-safe** — after every interactive gate, update `.crew/current-feature.yaml` with `drive_phase` so the pipeline can resume if interrupted.

### Question Design

Every `AskUserQuestion` call must include:
- `header` — short topic label (2-5 words)
- `question` — clear, specific prompt
- `options` — 3-5 concrete choices, each with label + description
- Always include: `{label: "Let Claude decide", description: "I'll pick based on best practices"}`
- Always include: `{label: "Stop and clarify", description: "I have questions first"}`
- Set `multiSelect: true` when multiple answers are valid

### Example

```
AskUserQuestion({
  questions: [{
    header: "Deep Research",
    question: "Run deep web research before discovery?",
    multiSelect: false,
    options: [
      {label: "Yes, full research", description: "15-30 cited sources via firecrawl/exa"},
      {label: "Yes, quick scan", description: "5-10 sources, faster turnaround"},
      {label: "No, skip", description: "Use model knowledge only"},
      {label: "Let Claude decide", description: "I'll pick based on feature scope"},
      {label: "Stop and clarify", description: "I have questions first"}
    ]
  }]
})
```

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

3. **No active feature?**
   ```
   Check: .crew/current-feature.yaml
   If exists AND status != "complete":
   ```
   **Dispatch `AskUserQuestion`:**
   ```
   AskUserQuestion({
     questions: [{
       header: "Active feature",
       question: "Feature '{existing_name}' is currently in progress (phase: {phase}, branch: {branch}). How to proceed?",
       multiSelect: false,
       options: [
         {label: "Archive + new drive", description: "Move current-feature.yaml to .crew/archive/, start fresh"},
         {label: "Finish existing first (Recommended)", description: "Halt — complete the in-progress feature before starting new work"},
         {label: "Resume existing", description: "Switch to the existing feature via /crew feature"},
         {label: "Force new drive", description: "Overwrite current-feature.yaml without archiving (risky)"}
       ]
     }]
   })
   ```

4. **Crew MCP?**
   ```
   Check: Search for crew MCP tools
   If not found → WARN:
     "Crew MCP not connected. Architecture diagrams will use text/Mermaid fallback.
      For C4 diagrams and blast radius: /crew setup-mcp crew"
   Ask: "Continue without Crew MCP? [Yes / Setup first]"
   ```

All checks passed → proceed to Step 1.

---

### Step 1: Feature Input & Validation

#### If argument provided (e.g., `/crew drive user-authentication`)

1. **Length check:** Name must be >= 3 characters
   - If too short → "Feature name too short. Please provide a more descriptive name."

2. **Duplicate check:** Fuzzy-match against existing stories in `.crew/roadmap.yaml`
   - Search all `stories[].title` for similar names (case-insensitive, partial match)
   - If match found, **dispatch `AskUserQuestion`:**
     ```
     AskUserQuestion({
       questions: [{
         header: "Duplicate?",
         question: "Similar stories already exist: {list up to 3 titles with IDs}. How to proceed?",
         multiSelect: false,
         options: [
           {label: "Scoped drive (Recommended)", description: "Run drive scoped around the unbuilt parts only — avoids duplicating existing stories"},
           {label: "Resume existing", description: "Use /crew feature on the matching story instead of full drive"},
           {label: "New drive anyway", description: "Different scope — proceed with fresh drive despite overlap"},
           {label: "Rename feature", description: "Edit the feature name to be more specific, re-check for duplicates"}
         ]
       }]
     })
     ```

3. **Normalize** name to kebab-case for branches/paths:
   - "User Authentication" → `user-authentication`
   - "Add Payment Flow" → `add-payment-flow`

4. **Confirm:**
   ```
   Feature: **{name}**
   Description: Not provided — will be defined during Discovery
   Branch: feature/{kebab-name}

   Proceed to Discovery? [Yes / Add description / Edit name]
   ```

#### If no argument (interactive mode)

Ask:
1. "What feature do you want to build?"
2. "Brief description (1-2 sentences, or skip to define during Discovery):"

Then run the same validation (length, duplicate, normalize, confirm).

---

### Step 1.5: Use existing Gang GO Package? (Interactive)

Drive does **not** run Gang from inside its own pipeline. Gang is a separate plugin with its own lifecycle — the user runs Gang independently when they want strategic evaluation, then `/crew drive` picks up the resulting GO Package. This step detects whether such a package exists and offers to import it.

**Skip this step entirely if invoked with `--skip-gang` flag.**

#### 1.5a — Detect GO Package on disk

Look for `.gang/features/{feature_id}/go-package/` (after kebab-casing). The folder must contain at least `brd.md` to count as a usable GO Package.

```bash
GANG_DIR=".gang/features/{feature_id}"
GO_PKG="$GANG_DIR/go-package"

if [[ -f "$GO_PKG/brd.md" ]]; then
  GO_PKG_FOUND=true
  GANG_VERDICT=$(yq -r '.advise.verdict' "$GANG_DIR/state.json")  # GO | CONDITIONAL-GO | NO-GO
else
  GO_PKG_FOUND=false
fi
```

#### 1.5b — Branch on detection result

**If `GO_PKG_FOUND == false`:**

No package exists. Continue to Phase 1 — pm-architect handles discovery, architecture, and BRD from scratch. No question asked, no friction. Set state:

```yaml
# .crew/current-feature.yaml
gang_used: false
drive_phase: "gang_check_complete"
```

**If `GO_PKG_FOUND == true` AND `GANG_VERDICT == "NO-GO"`:**

A Gang evaluation exists but the verdict was NO-GO. Show this to the user and ask:

```
AskUserQuestion({
  questions: [{
    header: "Gang said NO-GO",
    question: "Gang evaluated this feature and returned NO-GO. Continue building anyway, abandon, or escalate back to Gang for re-scoring?",
    multiSelect: false,
    options: [
      {label: "Build anyway (override)", description: "Ignore Gang verdict; pm-architect handles discovery from scratch"},
      {label: "Abandon drive", description: "Halt; do not create roadmap entry or card"},
      {label: "Escalate to Gang", description: "Run /crew gang-escalate {feature_id} — send fresh context to Gang for re-evaluation"}
    ]
  }]
})
```

**If `GO_PKG_FOUND == true` AND `GANG_VERDICT ∈ {GO, CONDITIONAL-GO}`:**

A usable package exists. Ask:

```
AskUserQuestion({
  questions: [{
    header: "Use Gang GO Package?",
    question: "Found a Gang GO Package for '{feature_id}' (verdict: {verdict}, generated {age_human_readable}). Use it as the source of truth for discovery + architecture + API contracts? Drive will skip its own Phase 1 + Phase 2 and pick up at the BRD review step.",
    multiSelect: false,
    options: [
      {label: "Yes — import it", description: "Run /crew gang-import {feature_id}, skip Phase 1 + 2, push card with source=gang"},
      {label: "No — fresh discovery", description: "Ignore the package; pm-architect runs discovery + architecture from scratch (typical when scope changed since Gang ran)"}
    ]
  }]
})
```

#### 1.5c — Action on "Yes — import it"

1. Run `/crew gang-import {feature_id}`. The `gang-bridge` agent:
   - Copies the GO Package artifacts into `.crew/features/{feature_id}/` per the [overlap & handoff contract](../references/overlap-handoff-contract.md)
   - Sets `roadmap.yaml#features[id].source.origin = "gang"` and copies CONDITIONAL-GO conditions into `source.conditions` (these gate Phase 3 implementation)
   - Marks BRD, architecture, API contract as `imported` (drive will not regenerate them)

2. Set state:
   ```yaml
   # .crew/current-feature.yaml
   gang_used: true
   gang_verdict: GO                    # or CONDITIONAL-GO
   drive_phase: "gang_check_complete"
   skip_phases: [1, 2]                 # drive skips these; goes to BRD review
   ```

3. **Jump directly to Step 1.6** (push card). Do **not** run Phase 1 (Discovery) or Phase 2 (Architecture) — they're already done by Gang.

#### 1.5d — Action on "No — fresh discovery"

Continue to Phase 1 normally. pm-architect re-derives discovery + architecture, even though a Gang package exists. This is the right choice when the package is stale or scope changed materially. Set state:

```yaml
gang_used: false
gang_package_ignored: .gang/features/{feature_id}/   # audit trail
drive_phase: "gang_check_complete"
```

---

### Step 1.6: Push initial card to GitHub Projects

Both branches of Step 1.5 land here:

- **From 1.5c (Yes — import it):** the GO Package has been imported, `current-feature.yaml#gang_used: true` is set, source.origin = "gang"
- **From 1.5b/1.5d (No GO Package, or fresh discovery):** standard manual feature, source.origin = "manual"

Either way, create the live status card on the configured GitHub Projects board(s) so stakeholders can see the feature exists:

```
/crew push                  # invokes commands/push.md in create mode
```

This creates a draft card with status `Planned`, card type derived from `current-feature.yaml#card_type` (default: `feature`). If `config.github.enabled: false` or no boards configured, this step is silently skipped.

**If `gang_used: true`** the card body skeleton injects the `gang_link_line` placeholder pointing back to `.gang/features/{feature_id}/` + the verdict badge — so anyone reading the GitHub board can trace the build back to the source Gang evaluation.

**Next step depends on Step 1.5 outcome:**

- **If `gang_used: true`** → jump straight to **Phase 3 (BRD review)**. Phase 1 (Discovery) and Phase 2 (Architecture) are skipped entirely; their outputs already exist in `.crew/features/{feature_id}/` from gang-import.
- **Otherwise** → continue to **Phase 1** below.

---

### Phase 1: Discovery & Research — pm-architect agent

> **Skip Phase 1 entirely if `gang_used: true`** — the Gang GO Package already contains discovery + competitive analysis + assumptions ledger. Jump to Phase 3 (BRD review).

#### Step 1.0: Optional Deep Research (Interactive)

**Dispatch `AskUserQuestion`:**

**Note:** `AskUserQuestion` caps at 4 options per question. "Other" is provided automatically — use it for "stop and clarify" and custom answers.

```
AskUserQuestion({
  questions: [{
    header: "Deep research",
    question: "Run deep web research before discovery? It pulls live cited data from multiple sources (competitors, market sizing, trends) and feeds richer context into pm-architect.",
    multiSelect: false,
    options: [
      {
        label: "Full research (Recommended)",
        description: "15-30 cited sources via firecrawl/exa MCP, ~10 min"
      },
      {
        label: "Quick scan",
        description: "5-10 sources, faster turnaround, ~3 min"
      },
      {
        label: "Skip research",
        description: "Use pm-architect's model knowledge only"
      },
      {
        label: "Let Claude decide",
        description: "Run deep research only if feature novelty warrants it"
      }
    ]
  }]
})
```

(User picks "Other" to ask clarification questions — pause, answer, then re-ask.)

**Handle response:**

- **"Stop and clarify"** → Pause pipeline. Answer the user's questions. Re-dispatch this same `AskUserQuestion` until the user picks an actionable option.
- **"No — model knowledge only"** → Skip to Step 1.1 directly.
- **"Let Claude decide"** → Judge scope: new product domain, unfamiliar competitors, regulatory/market uncertainty → run full research. Otherwise skip.
- **"Yes — full research" or "Yes — quick scan"** → Proceed below.

**If proceeding with research:**

1. Check MCP availability:
   ```
   Scan for: firecrawl_search, firecrawl_scrape, web_search_exa, crawling_exa
   ```
   - If neither found, dispatch `AskUserQuestion`:
     ```
     AskUserQuestion({
       questions: [{
         header: "MCP missing",
         question: "Deep research needs firecrawl or exa MCP — neither is connected. How to proceed?",
         multiSelect: false,
         options: [
           {label: "Configure firecrawl (Recommended)", description: "Run /crew setup-mcp firecrawl"},
           {label: "Configure exa", description: "Run /crew setup-mcp exa"},
           {label: "Skip deep research", description: "Continue with pm-architect only"},
           {label: "Let Claude decide", description: "Skip if quick scan, configure if full research"}
         ]
       }]
     })
     ```
   - If at least one found: proceed.

2. **Dispatch `/deep-research` skill** with prompt:
   ```
   Research the following feature for a software product:

   Feature: {name}
   Description: {description or "to be scoped"}
   Project context: [Read .crew/project-context.md for domain/stack context]

   Sub-questions to investigate:
   1. Who are the top 3-5 competitors offering this feature? What do they do well/poorly?
   2. What are current market trends and user pain points around this feature?
   3. What is the market size or adoption rate (if applicable)?
   4. What technical approaches do competitors use to implement this?
   5. Any regulatory, compliance, or industry constraints to be aware of?

   Requirements:
   - Every claim must have a source citation
   - Prefer sources from the last 12 months
   - Flag any unverified or single-source claims
   - Use parallel agents for sub-questions 1-2, 3-4, 5 if topic is broad

   Output: Save full cited report to docs/pm-architect/{kebab-name}/deep-research.md
   ```

3. **Wait for deep-research to complete.**

4. Confirm to user:
   ```
   Deep research complete.
   Sources gathered: {N}
   Report saved: docs/pm-architect/{kebab-name}/deep-research.md

   Feeding findings into pm-architect discovery phase...
   ```

---

#### Step 1.1: Discovery & Research — pm-architect agent

**Dispatch:** Launch `pm-architect` agent with prompt:

```
Run Phases 1-3 (Discover, Research, Analyze) for the feature:

Feature: {name}
Description: {description or "To be discovered"}
Project context: [Read .crew/project-context.md]
Existing roadmap: [Read .crew/roadmap.yaml for context]
Design context: [Read .impeccable.md for brand personality, design principles, and aesthetic direction]
{if deep research was run}
Deep research findings: [Read docs/pm-architect/{kebab-name}/deep-research.md — use as primary evidence base, do not re-research topics already covered there]
{end if}

Tasks:
1. DISCOVER: Scope the feature, create a Feature Brief
2. RESEARCH: Analyze 3-5 competitors, market trends, user pain points
   - Evaluate competitor UX against our design principles (data density, semantic color, earned simplicity)
   {if deep research was run}
   - Use deep-research.md as the evidence base — extend it, don't repeat it
   {end if}
3. ANALYZE: Gap analysis, RICE scoring, MoSCoW classification
   - Include design/UX gaps vs competitors per .impeccable.md principles

Output: Save all findings to docs/pm-architect/{kebab-name}/discovery.md
```

**Wait for agent to complete.**

#### Present Results
```
Discovery & Research Complete
{if deep research was run}
  Deep Research: docs/pm-architect/{name}/deep-research.md ({N} sources)
{end if}
Feature Brief: {1-paragraph summary}
Competitors Analyzed: {list}
Key Findings:
  - {insight 1}
  - {insight 2}
  - {insight 3}
RICE Top Features: {top 3 with scores}

Full report: docs/pm-architect/{name}/discovery.md
```

#### Step 1.2: Interactive Opportunity Assessment

Before moving to architecture, pm-architect's discovery typically surfaces **multiple opportunities** (user pain points, competitor gaps, market segments). The user must decide which opportunities are in scope — the model should not pick unilaterally.

**Extract** the opportunity list from `discovery.md` (typically 4-8 items).

**Two-pass pattern** (because `AskUserQuestion` caps at 4 options):

**Pass A — scope mode:**
```
AskUserQuestion({
  questions: [{
    header: "Opp scope",
    question: "Discovery surfaced {N} opportunities. How should the feature be scoped?",
    multiSelect: false,
    options: [
      {label: "Pick specific ones", description: "Next step: multi-select the exact opportunities (best control)"},
      {label: "Top by RICE (Recommended)", description: "Let Claude pick top 2-3 by RICE score, justify in writing"},
      {label: "All opportunities", description: "Address every opportunity — broadest scope, likely needs sprint split"},
      {label: "Top 1 only", description: "Narrowest MVP — smallest feature, fastest ship"}
    ]
  }]
})
```

**Pass B — only if user picked "Pick specific ones":**
Split opportunities into batches of ≤4 and run `AskUserQuestion` with `multiSelect: true` per batch. For each batch:
```
AskUserQuestion({
  questions: [{
    header: "Opps {i}/{n}",
    question: "Which of these opportunities should the feature address? (Select all that apply.)",
    multiSelect: true,
    options: [
      {label: "{Opportunity A title}", description: "{1-line summary + RICE score}"},
      {label: "{Opportunity B title}", description: "{1-line summary + RICE score}"},
      {label: "{Opportunity C title}", description: "{1-line summary + RICE score}"},
      {label: "{Opportunity D title}", description: "{1-line summary + RICE score}"}
    ]
  }]
})
```

**Handle response:**

- **"Stop and clarify"** → Pause. Answer questions using the full `discovery.md` context. Re-dispatch the question.
- **"Let Claude decide"** → Select top 2-3 by RICE score, justify in a one-paragraph note in `discovery.md`.
- **"All of the above"** → Scope all opportunities into the feature (warn user: may create large feature requiring sprint split).
- **Specific selections** → Use those exact opportunities as the feature scope.

**Save selection** to `docs/pm-architect/{kebab-name}/selected-opportunities.md` with:
```markdown
# Selected Opportunities

## User choice
- [x] {Opportunity 1}
- [x] {Opportunity 3}
- [ ] {Opportunity 2}
- [ ] {Opportunity 4}

## Reasoning
{Either user's clarification answers OR Claude's justification if "Let Claude decide"}
```

**Update `.crew/current-feature.yaml`:** `drive_phase: opportunities_selected`

---

**>>> USER APPROVAL GATE**
```
Discovery complete. Opportunities selected: {N}/{total}.
→ Approve and proceed to Architecture Design? [Yes / Request changes / Stop]
```

---

### Phase 2: Architecture Design — pm-architect agent

> **Skip Phase 2 entirely if `gang_used: true` AND `gang_verdict ∈ {GO, CONDITIONAL-GO}`** — the Gang GO Package already contains architecture + tech-architecture.md + API contract draft. Jump to Phase 3 (BRD review) where drive treats Gang's BRD as `seeded` (extend, don't regenerate).

**Dispatch:** Launch `pm-architect` agent with prompt:

```
Run Phase 4 (Design) for the feature:

Feature: {name}
Discovery findings: [Read docs/pm-architect/{name}/discovery.md]
Project context: [Read .crew/project-context.md]

Tasks:
1. Define Functional Requirements (FR-IDs with user stories, acceptance criteria)
2. Define Non-Functional Requirements (all 8 categories)
3. Design solution architecture:
   - If Crew MCP available: Create C4 diagrams, run blast radius analysis
   - If not: Create text descriptions with Mermaid diagrams
4. Identify API contracts needed

Output: Save to docs/pm-architect/{kebab-name}/architecture.md
```

**Wait for agent to complete.**

**>>> USER APPROVAL GATE**
```
Architecture designed.
  - {N} Functional Requirements defined
  - {N} Non-Functional Requirements defined
  - Architecture: {C4 diagrams created / Text descriptions}
  - Blast radius: {summary if available}

Full report: docs/pm-architect/{name}/architecture.md
→ Approve and proceed to BRD generation? [Yes / Request changes / Stop]
```

---

### Phase 3: BRD Generation — pm-architect agent

#### Step 3.0: Interactive Non-Goals

Before drafting the BRD, explicitly capture what is **out of scope**. This prevents scope creep and ambiguity (Stage 11 of the product spec pipeline).

**Two-pass pattern** (grouped because tool caps at 4 options):

**Pass A — platform/scope non-goals:**
```
AskUserQuestion({
  questions: [{
    header: "Non-goals 1",
    question: "Which platform/scope boundaries are out of scope for v1? (Select all that apply.)",
    multiSelect: true,
    options: [
      {label: "Mobile/native apps", description: "Desktop web only for v1"},
      {label: "Internationalization", description: "English only for v1"},
      {label: "Offline mode", description: "Requires network connection"},
      {label: "Backwards compatibility", description: "No legacy data migration"}
    ]
  }]
})
```

**Pass B — integration/UX non-goals:**
```
AskUserQuestion({
  questions: [{
    header: "Non-goals 2",
    question: "Which integration/UX boundaries are out of scope for v1? (Select all that apply.)",
    multiSelect: true,
    options: [
      {label: "Third-party integrations", description: "No external API connections in v1"},
      {label: "Admin/settings UI", description: "Configuration via env vars only"},
      {label: "Custom theming", description: "Default theme only, no user customization"},
      {label: "Bulk operations", description: "Single-item actions only in v1"}
    ]
  }]
})
```

**After both passes, dispatch a third question** to capture custom additions:
```
AskUserQuestion({
  questions: [{
    header: "Custom goals",
    question: "Anything else to mark as non-goal? (Use 'Other' to add custom items.)",
    multiSelect: false,
    options: [
      {label: "Done, use selections above", description: "The 2 passes cover everything"},
      {label: "Let Claude add defaults", description: "Claude will add any obvious ones missed"},
      {label: "Add more via text", description: "Use 'Other' to type custom non-goals"},
      {label: "Skip non-goals section", description: "No explicit non-goals in BRD (not recommended)"}
    ]
  }]
})
```

**Save non-goals** to `docs/pm-architect/{kebab-name}/non-goals.md`.

---

#### Step 3.1: Interactive Outcome Metrics

Define success BEFORE building (Stage 5 of the spec pipeline).

**Two-pass pattern** (grouped North-Star metrics vs guardrails):

**Pass A — North-Star success metrics:**
```
AskUserQuestion({
  questions: [{
    header: "Success 1",
    question: "Which North-Star success metrics matter? (Select all that apply.)",
    multiSelect: true,
    options: [
      {label: "Adoption rate", description: "% of eligible users who try feature within 30 days"},
      {label: "Engagement", description: "DAU/WAU/MAU ratio, session duration"},
      {label: "Retention lift", description: "Cohort retention vs users without feature"},
      {label: "Conversion uplift", description: "Impact on primary funnel conversion"}
    ]
  }]
})
```

**Pass B — task-level + guardrail metrics:**
```
AskUserQuestion({
  questions: [{
    header: "Success 2",
    question: "Which task-level and guardrail metrics matter? (Select all that apply.)",
    multiSelect: true,
    options: [
      {label: "Task success rate", description: "% of users who complete the primary job"},
      {label: "Time to value", description: "Median time from feature entry to first success"},
      {label: "Error/drop-off rate", description: "Guardrail — must stay below threshold"},
      {label: "Performance SLO", description: "p95 latency, error budget"}
    ]
  }]
})
```

For each selected metric, pm-architect must define: **baseline**, **target**, **guardrail threshold**.

For each selected metric, pm-architect must define: **baseline**, **target**, **guardrail threshold**.

**Save outcome metrics** to `docs/pm-architect/{kebab-name}/outcome-metrics.md`.

---

#### Step 3.2: Interactive Tracking Spec

Bridge metrics to implementation with an analytics tracking spec (Stage 14). This tells ui-engineer/api-engineer exactly which events to instrument.

**Two-pass pattern:**

**Pass A — core funnel events:**
```
AskUserQuestion({
  questions: [{
    header: "Events 1",
    question: "Which core funnel events should be tracked? (Select all that apply.)",
    multiSelect: true,
    options: [
      {label: "Feature entry", description: "User views/opens the feature"},
      {label: "Primary action", description: "User performs the core job (click, submit, select)"},
      {label: "Success state", description: "User reaches successful outcome"},
      {label: "Error/failure", description: "User hits error or abandons"}
    ]
  }]
})
```

**Pass B — secondary/context events:**
```
AskUserQuestion({
  questions: [{
    header: "Events 2",
    question: "Which secondary/context events should be tracked? (Select all that apply.)",
    multiSelect: true,
    options: [
      {label: "Secondary actions", description: "Filters, sorts, configuration changes"},
      {label: "Time-on-feature", description: "Duration between entry and exit"},
      {label: "Session depth", description: "Repeat visits, feature usage frequency"},
      {label: "Feature exit", description: "User leaves the feature (voluntary or timeout)"}
    ]
  }]
})
```

For each selected event, pm-architect produces a tracking-spec row: `event_name`, `trigger`, `properties`, `destination` (GA4, Mixpanel, internal, etc.).

For each selected event, pm-architect produces a tracking-spec row: `event_name`, `trigger`, `properties`, `destination` (GA4, Mixpanel, internal, etc.).

**Save tracking spec** to `docs/pm-architect/{kebab-name}/tracking-spec.md`.

---

#### Step 3.3: BRD Generation — pm-architect agent

**Dispatch:** Launch `pm-architect` agent with prompt:

```
Run Phases 5-6 (Document, Review) for the feature:

Feature: {name}
Discovery: [Read docs/pm-architect/{name}/discovery.md]
Selected opportunities: [Read docs/pm-architect/{name}/selected-opportunities.md]
Architecture: [Read docs/pm-architect/{name}/architecture.md]
Non-goals: [Read docs/pm-architect/{name}/non-goals.md]
Outcome metrics: [Read docs/pm-architect/{name}/outcome-metrics.md]
Tracking spec: [Read docs/pm-architect/{name}/tracking-spec.md]
Design context: [Read .impeccable.md for design principles]

Tasks:
1. Generate professional BRD document using the docx skill (anthropic-skills:docx)
2. Include all sections: Executive Summary through Appendices
3. MANDATORY sections (from user's interactive selections):
   - "Non-Goals" — explicit list of what is out of scope
   - "Outcome Metrics" — selected metrics with baseline/target/guardrail
   - "Tracking Spec" — event table for analytics instrumentation
4. Include a "Design Compliance" section:
   - Map each UI requirement to the applicable design principle from .impeccable.md
   - Specify color tokens (semantic color is law), spacing (4px grid), typography expectations
   - Reference dark theme tokens from index.css
5. Run adversarial QA gate (Phase 6 Review)
6. Fix any gaps found during review

Output: Save BRD to docs/brd/{kebab-name}-brd.docx
        Save QA report to docs/pm-architect/{kebab-name}/review.md
```

**Wait for agent to complete.**

**>>> USER APPROVAL GATE**
```
BRD Generated: docs/brd/{name}-brd.docx
QA Review: {pass/fail summary}
  - Completeness: {result}
  - Quality: {result}
  - Gap Detection: {result}

→ Approve BRD and add feature to roadmap? [Yes / Request revisions / Stop]
```

---

### Phase 4: Roadmap Integration

This phase runs inline (no agent dispatch needed).

1. **Read** `.crew/roadmap.yaml`

2. **Epic Selection:**
   ```
   Which epic does this feature belong to?

   Existing epics:
     1. {E1}: {name}
     2. {E2}: {name}
     ...
     N. Create new epic

   Select:
   ```

3. **Create Stories** from the functional requirements:
   - Each FR becomes a story with acceptance criteria
   - Assign `priority` from RICE/MoSCoW analysis
   - Set `status: backlog`
   - Set `assigned` based on scope (ui-engineer, api-engineer, or both)

4. **Sprint Assignment:**
   ```
   Assign stories to sprint? [Yes / Leave in backlog]
   ```

5. **Update** `.crew/roadmap.yaml` with new stories

6. **Create** `.crew/current-feature.yaml`:
   ```yaml
   feature: {name}
   branch: feature/{kebab-name}
   drive_phase: roadmap_integrated
   stories: [S{epic}-{seq}, ...]
   started: {ISO date}
   ```

7. **Create feature branch:**
   ```bash
   git checkout -b feature/{kebab-name}
   ```

8. **Commit:**
   ```bash
   git add .crew/roadmap.yaml .crew/current-feature.yaml docs/pm-architect/ docs/brd/
   git commit -m "docs(drive): {name} — discovery, architecture, and BRD"
   ```

**>>> USER APPROVAL GATE**
```
Feature added to roadmap:
  - Epic: {epic name}
  - Stories: {N} stories created
  - Branch: feature/{kebab-name}

→ Ready to begin implementation? [Yes / Edit stories / Stop]
```

---

### Phase 5: Implementation — ui-engineer + api-engineer

**Pre-flight: usage budget check (CRITICAL — runs before every heavy dispatch).**

Before dispatching either engineer, run:

```bash
bash {plugin_root}/scripts/crew-budget-check.sh \
  --op-type ui_engineer_full_feature \
  --feature-id {feature_id} \
  --phase 3 \
  --next-step dispatch_ui_engineer
```

Then again before api-engineer with `--op-type api_engineer_full_feature --next-step dispatch_api_engineer`.

**Branch on script exit code:**

- **Exit 0 (`status: ok`)** → proceed normally
- **Exit 1 (`status: warn`)** → proceed but tell the user "approaching budget ceiling — consider lighter dispatch mode if available." Continue.
- **Exit 2 (`status: stop`)** → the script has already written a checkpoint. Read the JSON output's `instructions_for_caller` field. **Call `mcp__scheduled-tasks__create_scheduled_task`** with the supplied `prompt` (`/crew resume {id}`) and `schedule` (the ISO timestamp). Then print to user:
  ```
  ⏸  Crew paused at {percent_used}% session usage.

  Saved checkpoint: {checkpoint_id}
  Was about to:    {next_step}
  Resume scheduled: {schedule_at} ({reset_window} reset + {buffer}min buffer)

  Manual resume anytime with: /crew resume
  ```
  **Exit drive cleanly.** Do NOT proceed with the dispatch. Drive will resume from the same `next_step` when the scheduled task fires.

---

**Push card status → Building (auto-trigger).** If budget check passes, run:

```
/crew push                  # update-status mode → "Building"
```

This sets the GitHub Projects card's Status field to whichever option the board mapped to logical state `Building` (typically "In Progress"). Skipped if `config.github.enabled: false` or no boards configured.

---

Read `.crew/current-phase.yaml` to determine `project_type` and select agents:

| Agent | fullstack | frontend_only | backend_only |
|-------|-----------|---------------|--------------|
| `ui-engineer` | Yes | Yes | No |
| `api-engineer` | Yes | No | Yes |

**Follow the execution pattern from `.crew/phases/phase-3-implementation.md`:**

1. Run Phase 3 pre-flight validation (git, feature branch, API contract, design artifacts)
2. Dispatch engineers in parallel (for fullstack)
3. Each engineer works on their assigned stories
4. Engineers follow the task-level git workflow from `workflow.md`

**When dispatching `ui-engineer`, always include in the prompt:**
```
Design context: Read .impeccable.md for brand personality, aesthetic direction, and design principles.
All UI work MUST comply with these 5 principles:
  1. Data density with hierarchy — show info, use visual hierarchy
  2. Semantic color is law — green=gains, red=losses, blue=action, yellow=warning
  3. Earned simplicity — every element earns its place
  4. Professional craft — pixel-perfect, 4px grid, smooth transitions
  5. Confidence through clarity — no ambiguous states, clear signals
Use CSS variable tokens from index.css. Dark theme only.
```

**For each story:**
- Create task branch: `feature/{name}/{story-id}-{task}`
- Implement to meet acceptance criteria from roadmap.yaml
- Commit with conventional messages
- Merge task branch back to feature branch

**Wait for all engineers to complete.**

**Post-dispatch: log token usage** for each completed engineer:

```bash
bash {plugin_root}/scripts/crew-budget-log.sh \
  --op-type ui_engineer_full_feature \
  --tokens {your_best_estimate_of_actual_tokens_consumed} \
  --feature-id {feature_id} \
  --phase 3
```

Repeat for `api_engineer_full_feature`. The log keeps `.crew/usage-state.yaml#session.estimated_tokens_used` accurate so the next budget check has fresh data. If you don't know exact tokens, the static estimate from `op_costs[op_type]` is used by default — call this script only when you have a better number.

**Update** `.crew/current-feature.yaml`:
```yaml
drive_phase: implementation_complete
```

**>>> USER APPROVAL GATE**
```
Implementation complete.
  - Stories implemented: {list}
  - Files changed: {summary}

→ Ready for QA? [Yes / Continue implementing / Stop]
```

---

### Phase 6: QA & Acceptance — qa-engineer + pm-maestro-reviewer

**Push card status → In Review (auto-trigger).** Before dispatching qa-engineer, run:

```
/crew push                  # update-status mode → "In Review"
```

The board's Status column now shows this feature awaiting QA. PM/stakeholders can see "the build is done, currently being reviewed" without asking.

---

**Step 6.1: Dispatch qa-engineer**
```
Write and run tests for the feature:
  Feature: {name}
  Stories: [Read from .crew/current-feature.yaml]
  Acceptance criteria: [Read from .crew/roadmap.yaml]

  Create unit tests, integration tests, and E2E tests.
  Achieve 80%+ coverage on new code.
```

**Step 6.2: Dispatch pm-maestro-reviewer**
```
Validate the feature against acceptance criteria:
  Feature: {name}
  Stories: [Story IDs]
  Roadmap: [Read .crew/roadmap.yaml]

  Run Maestro tests for each acceptance criterion.
  Produce pass/fail verdict.
```

**Wait for both to complete.**

**>>> USER APPROVAL GATE**
```
QA Results:
  - Test coverage: {percentage}%
  - Acceptance: {ACCEPTED/REJECTED}
  - {N} criteria passed, {M} failed

→ Ready for gap audit? [Yes / Fix failures first / Stop]
```

If REJECTED: Loop back to Phase 5 for fixes.

---

### Phase 7: Gap Audit — gap-finder agent

**Step 7.0: Get preview URL**
```
The app needs to be running for the gap audit.
Enter the preview URL (or press Enter for auto-detect):
```

Auto-detect: Check common ports (3000, 3001, 4173, 5173, 8080) with `curl -s -o /dev/null -w "%{http_code}"`.

**Step 7.1: Dispatch gap-finder agent**
```
Audit the running application for UI gaps:
  URL: {preview URL}
  Design context: [Read .impeccable.md for design principles]
  Feature: {name}
  Acceptance criteria: [From roadmap.yaml]

  Run full audit pipeline: Inventory → Interact → Inspect → Report
  Compare findings against acceptance criteria.
  Additionally evaluate against .impeccable.md design principles:
    - Semantic color compliance (green=gains, red=losses, blue=action, yellow=warning)
    - Data density and visual hierarchy
    - Missing states (loading, empty, error) — "confidence through clarity"
    - Spacing consistency (4px grid) — "professional craft"
    - Useless/decorative elements — "earned simplicity"
  Flag design principle violations as P2 Medium gaps.
  Save report to docs/gap-reports/{date}-{kebab-name}-gap-report.md
```

**Wait for agent to complete.**

**Step 7.2: Evaluate findings**

**>>> USER APPROVAL GATE**
```
Gap Audit Results:
  - Total elements tested: {N}
  - P0 Critical: {N}
  - P1 High: {N}
  - P2 Medium: {N}
  - P3 Low: {N}

Report: docs/gap-reports/{date}-{name}-gap-report.md

{If P0/P1 > 0}:
  Critical/High gaps found. Recommend fixing before finalizing.
  → Fix gaps (loop back to Implementation)? [Yes / Accept as-is / Stop]

{If P0/P1 == 0}:
  No critical gaps found!
  → Finalize feature? [Yes / Stop]
```

**Loop:** If user chooses to fix, loop back to Phase 5. Maximum 2 loop iterations, then require explicit decision.

---

### Completion

1. **Merge feature branch:**
   ```
   Ready to merge feature/{kebab-name} to main?
   [Yes / Keep branch open]
   ```

2. **Update roadmap:** Set all feature stories to `status: done`, mark acceptance criteria as `met: true`

3. **Update current-feature.yaml:**
   ```yaml
   drive_phase: complete
   completed: {ISO date}
   ```

4. **Push card status → Shipped (auto-trigger)** — only if `/crew deploy` has run successfully (check `current-feature.yaml#deploy_status == "success"`). Otherwise leave the card in `In Review` so the board accurately shows "merged but not yet in production":

   ```
   /crew push              # update-status → "Shipped" (only on confirmed deploy)
   ```

   If deploy hasn't run, suggest: "Run `/crew deploy` to push the card to Shipped, or update manually on the board."

5. **Summary:**
   ```
   Drive Pipeline Complete!

   Feature: {name}
   Duration: {start → end}
   Phases completed: 7/7

   Outputs:
     - Discovery: docs/pm-architect/{name}/discovery.md
     - Architecture: docs/pm-architect/{name}/architecture.md
     - BRD: docs/brd/{name}-brd.docx
     - Gap Report: docs/gap-reports/{date}-{name}-gap-report.md
     - Stories: {N} stories completed in roadmap

   Branch: feature/{kebab-name} → {merged to main / still open}
   ```

---

## Resume Capability

If the user runs `/crew drive` and `.crew/current-feature.yaml` exists with a `drive_phase` field:

```
Resuming drive pipeline for: {feature name}
Last completed phase: {drive_phase}

→ Continue from {next phase}? [Yes / Start over / View status]
```

`drive_phase` values: `validated`, `discovery_complete`, `architecture_complete`, `brd_complete`, `roadmap_integrated`, `implementation_complete`, `qa_complete`, `gap_audit_complete`, `complete`
