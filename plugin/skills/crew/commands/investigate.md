# /crew investigate — Hypothesis-driven, time-boxed investigation

Used when a **symptom is observed but the root cause is unknown**. Produces a `spike` card on the GitHub Projects board with findings, hypotheses tested, and a recommendation for the next action.

**Scope: technical investigations only.**
For strategic investigations (retention drops, conversion shifts, market changes), use Gang directly via `/gang init`. Crew does **not** auto-route between the two — the choice of tool is the user's, made deliberately.

> **Card lifecycle:** spike card created in `Building` status → moved to `In Review` once findings are synthesized → either consumed (replaced by a `bug` / `feature` card via the next command) or marked `Shipped` (recommendation shipped, no follow-up).

---

## Usage

```
/crew investigate                              → Interactive: ask for topic + type
/crew investigate "topic"                      → Quick-start with topic
/crew investigate "topic" --type {bug|perf|integration|architecture}
/crew investigate "topic" --time-box 2h        → Default: 2h
```

---

## Step 0 — Frame the investigation

If invoked interactively (no positional arg), dispatch `AskUserQuestion` to gather:

```
AskUserQuestion({
  questions: [{
    header: "Investigation type",
    question: "What kind of investigation?",
    multiSelect: false,
    options: [
      {label: "Bug — symptom observed, root cause unknown", description: "Crashes, errors, wrong output, intermittent failures. Dispatches code-reviewer + gap-finder for UI bugs."},
      {label: "Performance — slow / memory / load", description: "Latency spikes, memory leaks, slow renders, N+1 queries. Dispatches performance-optimizer + code-reviewer."},
      {label: "Integration mystery — works in isolation, breaks together", description: "Two systems disagree, unexpected coupling, contract violations. Dispatches code-reviewer + api-engineer (read-only)."},
      {label: "Architecture — understand how something works", description: "Mapping, tracing, learning the existing system before touching it. Dispatches pm-architect."}
    ]
  }]
})
```

Then ask for:
- **Topic** — 1–2 sentence summary
- **Symptom** — what's observed (error message, behavior, metric)
- **Expected vs actual** — what should happen, what does happen
- **Time-box** — default 2h; user can adjust (`30m` / `1h` / `2h` / `4h` / "let me set later")
- **Repro available?** — yes / no / partial

Write to `.crew/current-feature.yaml`:

```yaml
mode: investigate
investigation:
  spike_id: SPK-{YYYYMMDD}-{slug}     # auto-generated
  type: bug                            # bug | perf | integration | architecture
  topic: "Login fails 5% of the time on Safari"
  symptom: "Form submit returns 500, no error in logs"
  expected: "Successful login → /dashboard"
  actual:   "500 error, user stuck on form"
  time_box_hours: 2
  has_repro: partial
  started: 2026-05-08T...
```

---

## Step 1 — Profile + budget check (existing patterns)

```bash
bash {plugin_root}/scripts/crew-profile-check.sh \
  --feature-description "investigate: {topic}"
```

Ask about new techs that surface in the topic (e.g., investigating Safari → ask about safari/webkit knowledge level).

```bash
bash {plugin_root}/scripts/crew-budget-check.sh \
  --op-type deep_dispatch \
  --feature-id {spike_id} \
  --phase 4 \
  --next-step dispatch_investigation_agents
```

Investigations are typically Phase 4 territory (Quality / understanding). If budget check returns `stop`, save checkpoint, schedule resume — same pattern as drive.

---

## Step 2 — Push spike card (`Building` status)

```
/crew push   → invokes commands/push.md in create mode
```

Card details set on creation:
- `card_type: spike`
- Status field → `Building` (logical "Building" because investigation IS the work; mapped via `phase_to_logical_status[4]`)
- Body filled from the spike skeleton in `references/card-skeletons.md` — hypothesis, research questions, time-box table, definition of done
- Custom field `Source` → `investigation`

Cache the resulting `item_id` in `.crew/github-cards.yaml#features.{spike_id}.boards[*]`.

---

## Step 3 — Dispatch investigation agents (read-only mode)

**Critical: agents in this step run in read-only mode.** They read code, traces, logs, configs — they do not modify files. Output goes to `.crew/investigations/{spike_id}/`.

| Investigation type | Agents dispatched |
|---|---|
| `bug` | code-reviewer (read scope: relevant files, tests, recent commits)<br>+ gap-finder (UI inventory + interact pass, no fix dispatch) |
| `perf` | performance-optimizer (profile + identify bottlenecks)<br>+ code-reviewer (trace hot paths) |
| `integration` | code-reviewer (read both sides of the integration)<br>+ api-engineer (in read-only mode — verify contract conformance) |
| `architecture` | pm-architect (read codebase, produce diagram + narrative) |

Append to **every** dispatch prompt:

```
READ-ONLY MODE — do not modify any files. Output your findings to
.crew/investigations/{spike_id}/findings-{your-name}.md with sections:
  ## Hypothesis
  ## What I checked
  ## What I found
  ## What I could not determine
  ## Confidence: high | medium | low
  ## Reproduction status: verified | partial | not reproducible
```

Wait for all agents to complete. Log each via `crew-budget-log.sh`.

---

## Step 4 — Synthesize findings

Read every `findings-*.md` file in `.crew/investigations/{spike_id}/`. Produce a consolidated brief at `.crew/investigations/{spike_id}/SUMMARY.md` with:

- **Topic** (from intake)
- **Hypotheses tested** (across all agent reports)
- **Confirmed root cause** (if any) — file, function, line, why it happens
- **What's known**
- **What's still unknown**
- **Confidence level** (highest of: agents' individual confidences, gated by repro status)
  - HIGH = root cause located + reproducible + unique trigger identified
  - MEDIUM = strong hypothesis + partial repro
  - LOW = ruled out some causes but origin unclear
- **Time spent vs time-box** (from `crew-budget-log.sh` data)

Write the summary; this is what the recommendation in Step 5 reads from.

---

## Step 5 — Always suggest next command (calibrated to confidence)

**Always present a recommendation.** The recommendation is calibrated to the confidence level so MEDIUM/LOW investigations don't push the user into a wrong follow-up — but they're never left wondering what to do next.

Compose the recommendation from Step 4's `confidence` + `reproduction status`:

| Confidence | Reproducible? | Recommended next | Why |
|---|---|---|---|
| HIGH | Verified | `/crew fix` (with pre-filled context) | Root cause located, repro confirmed — fix flow can skip its own locate step |
| HIGH | Verified | `/crew feature` (instead of fix) | If finding says "this is missing functionality" rather than "this is broken" |
| MEDIUM | Partial | Continue investigating (extend time-box, deeper pass) | Strong hypothesis but more digging needed |
| MEDIUM | Not reproducible | Add observability + revisit | Find better repro before acting |
| LOW | Verified | Continue investigating with different `--type` | Rule out the wrong category (e.g. you're investigating as `bug`, it's actually `perf`) |
| LOW | Not reproducible | Escalate to `/gang` or kill | Beyond the scope of technical investigation |

### Dispatch the recommendation

```
AskUserQuestion({
  questions: [{
    header: "Next action",
    question: "Investigation complete. Confidence: {HIGH|MEDIUM|LOW}. {Root cause summary OR what's still unknown}.",
    multiSelect: false,
    options: [
      // FIRST option is always the recommendation, marked with ★
      {label: "★ {Recommended next command}", description: "{1-line why this is recommended at this confidence level}"},
      // Other options follow
      {label: "Continue investigating", description: "Extend the time-box; dispatch another read-only pass with refined hypotheses"},
      {label: "Kill investigation", description: "Mark spike as inconclusive and Shipped — don't proceed further"},
      {label: "Hand back to me", description: "Close the spike card with the findings; I'll decide what to do"}
    ]
  }]
})
```

### Compose the recommendation text

Build the recommended action's `label` and `description` based on the table:

**HIGH + reproducible + bug-shaped:**
```
label:       "★ Run /crew fix"
description: "Root cause located at {file:line}. Repro verified. Fix flow can skip locate step."
```

**HIGH + reproducible + missing-functionality-shaped:**
```
label:       "★ Run /crew feature"
description: "Finding shows missing functionality, not a bug. Feature flow is the right fit."
```

**MEDIUM + partial repro:**
```
label:       "★ Continue investigating"
description: "Hypothesis is strong; need a deeper read-only pass on {area}. Extend time-box by {1h}."
```

**MEDIUM + no repro:**
```
label:       "★ Add observability, then revisit"
description: "Need better repro before acting. Suggest adding {logging/metric/trace} to capture trigger."
```

**LOW + verified repro:**
```
label:       "★ Re-run with --type {alt}"
description: "Current --type ruled out; symptoms suggest {alt}. Investigation type may be wrong."
```

**LOW + no repro:**
```
label:       "★ Escalate to /gang"
description: "Beyond technical scope; symptoms suggest a strategic question Gang's committee can stress-test."
```

### On user selecting the recommended option

If the recommendation is `/crew fix` or `/crew feature`, auto-invoke that command with pre-filled context so the user doesn't re-answer questions Step 4 already established:

```yaml
# Pre-fill .crew/current-feature.yaml#{fix|feature} block
mode: {fix|feature}
{fix|feature}:
  source_spike:   {spike_id}
  bug_summary:    {root_cause_summary}
  reproduction:   {repro_steps_from_findings}
  located_at:     {file:line from findings}
  severity:       {derived from findings impact}
  pre_planned:    true   # don't re-run locate / Phase-1 planning; already done
```

If the recommendation is "Continue investigating" or "Add observability, then revisit," extend `time_box_hours` by 1h, set `current-feature.yaml#investigation.refined_hypothesis: ...`, and re-dispatch Step 3 with the refined scope.

If the recommendation is "Re-run with --type {alt}," archive the current spike, then prompt:
> "Re-running investigation with `--type {alt}`. The previous spike findings will be archived to `.crew/investigations/.archived/{spike_id}/` for reference."

If the recommendation is "Escalate to /gang," print a hand-off message:
> "Investigation finished with LOW confidence. To stress-test this strategically, run:
>   `/gang init`
> with the topic '{topic}'. Gang's committee can weigh in where Crew's read-only agents couldn't."
> Spike status moves to `Shipped` (escalated; no further Crew action).

### Why always suggest

Silence on MEDIUM/LOW confidence is what the v0.1 sketch had — it was wrong. Users running `/crew investigate` are seeking direction; getting findings without a recommended next step makes the command feel half-finished. The fix isn't to suggest `/crew fix` regardless of confidence — that's the bad pattern. The fix is to **calibrate the recommendation**: at LOW confidence the right recommendation is often "investigate differently" or "escalate," not "fix." A bad recommendation costs more than no recommendation, but no recommendation costs more than a calibrated one.

The `★` marker in the option label visually identifies "this is what Crew thinks you should do" without forcing the user into it — they can always pick a non-starred option.

---

## Step 6 — Update spike card

After Step 5 resolves:

```
/crew push   → invokes update-status mode
```

Status field transitions:
- If user picked "Run /crew fix" or "Run /crew feature" → spike status → `Shipped` (consumed by next card)
- If user picked "Continue investigating" → spike stays `Building`
- If user picked "Kill" or "Hand back" → spike status → `Shipped` (closed with findings)

If `config.github.update_body_on_phase_change: true`, also rewrite the spike card body with the SUMMARY.md content.

---

## Step 7 — Cleanup

If `mode: investigate` is consumed by a next command, archive:

```bash
mv .crew/investigations/{spike_id}/ .crew/investigations/.consumed/{spike_id}/
```

The findings stay readable (audit trail) but don't appear in the active investigations list.

---

## Failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| Agents return findings but no root cause located | Investigation type was wrong (e.g., `bug` for what's actually a perf issue) | User picks "Continue investigating" with `--type perf` override |
| Time-box exhausted, still LOW confidence | Scope too broad | Either narrow the topic and re-investigate, or escalate to Gang |
| Same agent dispatched twice with same files | Pre-flight didn't dedupe across agent assignments | Manual review of agent task assignments before re-dispatch |
| Spike card stays in Building forever | User never resolved the Step 5 question | Run `/crew investigate --resolve {spike_id}` (planned) |

---

## What this command does NOT do

- **Modify code.** All dispatches are read-only.
- **Create bug or feature cards directly.** That's `/crew fix` or `/crew feature`.
- **Route to Gang automatically.** Strategic investigations live in Gang's domain; the user picks the tool.
- **Run gang-bridge.** Investigations don't import from Gang; they may *suggest* Gang at the end if findings are inconclusive AND the topic seems strategic.
