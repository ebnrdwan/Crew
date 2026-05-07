# Usage-Aware Checkpointing & Auto-Resume

When `/crew` is driving a feature through implementation, it can consume a lot of tokens — especially during parallel agent dispatches (ui-engineer + api-engineer + qa-engineer). If the session approaches the rate-limit ceiling mid-build, hitting the wall leaves the feature in a half-built state with no clean recovery path.

The **usage-aware checkpoint system** solves this. Crew estimates the cost of each upcoming operation, compares to a configurable budget, and when the next op would push past the stop threshold, it:

1. **Saves a checkpoint** with the feature state and the next step that was about to run
2. **Schedules a task** via `mcp__scheduled-tasks__create_scheduled_task` to fire `/crew resume {id}` after the rate-limit window plus a buffer
3. **Exits gracefully** instead of crashing mid-dispatch

When the scheduled task fires, `/crew resume` reads the checkpoint, verifies the rate-limit window has actually rolled over, and continues from `next_step` as if nothing happened.

---

## How it fits into the flow

```
            ┌──────────────────────────────────────────────────┐
            │  Pre-dispatch (every heavy agent op)             │
            │                                                  │
            │  1. crew-budget-check.sh --op-type ...           │
            │     Returns: ok | warn | stop                    │
            │                                                  │
            │  2a. ok    → proceed                             │
            │  2b. warn  → proceed but log; consider light mode│
            │  2c. stop  → checkpoint written; schedule task;  │
            │              exit gracefully                     │
            │                                                  │
            │  3. Agent dispatch happens (if not stopped)      │
            │                                                  │
            │  4. crew-budget-log.sh --tokens N                │
            │     Updates running session total                │
            └──────────────────────────────────────────────────┘
```

---

## The two scripts

### `plugin/scripts/crew-budget-check.sh`

Pre-flight gate. Reads `.crew/config.yaml#usage` + `.crew/usage-state.yaml#session.estimated_tokens_used`. Looks up the op cost in `usage.op_costs[op_type]` (or uses `--op-cost` override). Outputs JSON; exit codes: `0=ok`, `1=warn`, `2=stop`, `3=error`.

When status is `stop`:
- Writes `.crew/checkpoints/{ISO}-{feature}.yaml` with full resume state
- Computes `scheduled_resume_at = session_start + reset_window + buffer_minutes`
- Emits `instructions_for_caller` telling the model exactly which `mcp__scheduled-tasks__create_scheduled_task` call to make
- The **model is responsible** for actually invoking the MCP tool — the script doesn't have access to it

### `plugin/scripts/crew-budget-log.sh`

Post-flight logger. Called after a dispatch with the model's best estimate of actual tokens used:

```bash
bash plugin/scripts/crew-budget-log.sh \
  --op-type ui_engineer_full_feature \
  --tokens 47000 \
  --feature-id user-auth \
  --phase 3
```

Updates `session.estimated_tokens_used` and appends to `session.log[]` for audit.

---

## State files

### `.crew/config.yaml#usage`

```yaml
usage:
  enabled: true
  budget_scope: session                   # session | feature | both

  # Plan-tier defaults (Max plan; tune for Pro)
  max_tokens_per_session: 5_000_000
  warn_threshold_percent: 90
  stop_threshold_percent: 98

  # When the rate-limit window resets — controls when /crew resume fires
  reset_window: "5h"                      # "5h" | "1h" | "daily" | "custom:HH:MM"
  resume_buffer_minutes: 10

  estimation_mode: static                 # static | self_reported | hybrid

  # Per-operation token estimates. Static defaults shipped with the plugin;
  # override here per-project if your dispatches consistently cost more/less.
  op_costs:
    pm_architect_discovery:    80_000
    pm_architect_architecture: 60_000
    pm_architect_brd:          50_000
    ui_engineer_full_feature:  50_000
    api_engineer_full_feature: 45_000
    qa_engineer:               30_000
    pm_maestro_reviewer:       20_000
    code_reviewer:             25_000
    performance_optimizer:     30_000
    gap_finder_audit:          70_000
    ux_designer:               40_000
    dsl_generator:             15_000
    api_contract_architect:    35_000
    light_dispatch:             8_000
    deep_dispatch:             25_000
    default:                   20_000
```

### `.crew/usage-state.yaml`

```yaml
session:
  started: 2026-05-08T15:30:00Z
  estimated_tokens_used: 4_572_000
  last_updated: 2026-05-08T17:42:00Z
  resumed_from: null                      # checkpoint_id if this session was resumed
  log:
    - {ts: 2026-05-08T15:31:12Z, op: pm_architect_discovery, tokens: 78000, feature_id: user-auth, phase: 1}
    - {ts: 2026-05-08T15:48:30Z, op: pm_architect_architecture, tokens: 62000, feature_id: user-auth, phase: 2}
    - {ts: 2026-05-08T16:15:00Z, op: ui_engineer_full_feature, tokens: 51000, feature_id: user-auth, phase: 3}
    # ...
```

### `.crew/checkpoints/{ISO}-{feature}.yaml`

```yaml
timestamp:               2026-05-08T17:42:00Z
reason:                  budget_stop
feature_id:              user-auth
phase:                   "3"
next_step:               dispatch_api_engineer
estimated_tokens_used:   4_900_000
blocked_op:
  op_type: api_engineer_full_feature
  op_cost: 45_000
max_tokens:              5_000_000
percent_used:            98.00
percent_after_blocked:   98.90
session_started:         2026-05-08T15:30:00Z
reset_window:            "5h"
scheduled_resume_at:     2026-05-08T20:40:00Z   # session_start + 5h + 10min
schedule_command:        /crew resume 20260508T174200Z-user-auth
```

---

## Wiring into command files

Every command that dispatches a heavy agent should call `crew-budget-check.sh` immediately before the dispatch:

```markdown
### Phase 5: Implementation

**Pre-dispatch budget check:**

```bash
bash {plugin_root}/scripts/crew-budget-check.sh \
  --op-type ui_engineer_full_feature \
  --feature-id {feature_id} \
  --phase 3 \
  --next-step dispatch_ui_engineer
```

If the script exits 2 (stop), the JSON output contains `instructions_for_caller`. Read it; call `mcp__scheduled-tasks__create_scheduled_task` with the supplied `prompt` and `schedule`; exit gracefully.

If the script exits 1 (warn), proceed but consider light-mode dispatch.
If the script exits 0 (ok), proceed.

**After dispatch completes:**

```bash
bash {plugin_root}/scripts/crew-budget-log.sh \
  --op-type ui_engineer_full_feature \
  --tokens {model_estimate_of_actual_tokens} \
  --feature-id {feature_id} \
  --phase 3
```
```

The pattern is the same for every dispatch — only `--op-type` and `--next-step` change.

---

## What happens when stop fires

1. Script writes `.crew/checkpoints/20260508T174200Z-user-auth.yaml`
2. Script outputs JSON like:
   ```json
   {
     "status": "stop",
     "schedule_at": "2026-05-08T20:40:00Z",
     "schedule_command": "/crew resume 20260508T174200Z-user-auth",
     "instructions_for_caller": "Call mcp__scheduled-tasks__create_scheduled_task with: prompt: '/crew resume 20260508T174200Z-user-auth' schedule: '2026-05-08T20:40:00Z' Then exit gracefully — do NOT proceed with the blocked op."
   }
   ```
3. Model parses JSON; calls `mcp__scheduled-tasks__create_scheduled_task` with those values
4. Model prints to user:
   ```
   ⏸  Crew paused at 98% session usage.

   Saved checkpoint: 20260508T174200Z-user-auth
   Was about to:    dispatch_api_engineer (phase 3)
   Resume scheduled: 2026-05-08T20:40:00Z (5h reset + 10min buffer)

   You can also resume manually with: /crew resume
   ```
5. Model exits gracefully — does NOT call the blocked agent

When the scheduled task fires later, it runs `/crew resume {checkpoint_id}` which:
- Verifies the rate-limit window rolled over
- Resets `usage-state.yaml#session` (fresh window)
- Continues from `next_step`

---

## Idempotency

Two ways `/crew resume` could fire on the same checkpoint:
1. The scheduled task fires at the appointed time
2. The user manually runs `/crew resume`

Both code paths claim a lock at `.crew/locks/resume-{id}.lock`. If the lock exists and was modified within the last 10 minutes, the second invocation is a no-op. After successful resume, the checkpoint is moved to `.crew/checkpoints/.consumed/` so it can never trigger another resume.

---

## Why static estimates instead of live token counts

Claude Code doesn't expose per-call token counts to the running session. We can't ask "how many tokens have I used so far?" from inside a skill. So we have to **estimate**:

- Static estimates per op type are the floor (good enough for warn/stop decisions)
- The model can override with `--op-cost N` when it has better information (e.g., a particularly large prompt)
- After dispatch, the model logs its own best estimate via `crew-budget-log.sh`

The system is designed to be **safe under bad estimates**: 98% stop threshold gives 2% headroom for under-estimation, and the budget itself can be tuned downward if you find the system bumps into the wall anyway.

---

## Pro vs Max defaults

| Plan | `max_tokens_per_session` (recommended starting point) | `reset_window` |
|---|---|---|
| Pro | 1_000_000 | 5h |
| Max | 5_000_000 | 5h |
| Team / Enterprise | 10_000_000+ | depends on contract |

These are starting points — calibrate by watching `usage-state.yaml#session.estimated_tokens_used` over a few sessions and see where you actually hit the wall in practice. If you hit the wall at 80% of your configured `max_tokens_per_session`, lower `max_tokens_per_session` to match observed behaviour.
