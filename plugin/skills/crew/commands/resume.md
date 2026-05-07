# /crew resume — Resume from a budget checkpoint

When `/crew` stops mid-build because token usage approached the rate limit, it writes a checkpoint to `.crew/checkpoints/` and schedules a task to resume. That task fires `/crew resume {checkpoint_id}` which this command handles.

Resume is **idempotent** — if the same checkpoint is processed twice (e.g., scheduled task + manual user trigger), the second run is a no-op.

---

## Usage

```
/crew resume                       → Resume from the most recent checkpoint
/crew resume {checkpoint_id}       → Resume from a specific checkpoint
/crew resume --list                → Show all checkpoints (most recent first)
/crew resume --discard {id}        → Mark a checkpoint as discarded (won't auto-resume)
```

---

## Step 0 — Locate checkpoint

If `--list` is passed: `ls -t .crew/checkpoints/*.yaml`, print one line per file with `(timestamp) feature_id phase next_step`. Exit.

If `--discard {id}` is passed: rename `.crew/checkpoints/{id}.yaml` → `.crew/checkpoints/{id}.yaml.discarded`. This prevents future scheduled resumes from acting on it. Exit.

Otherwise:
1. If a checkpoint ID was passed: read `.crew/checkpoints/{id}.yaml`.
2. If no ID: read the most recent file in `.crew/checkpoints/` (sorted by name; ISO timestamps sort correctly).
3. If no checkpoint exists: print "No checkpoint found." and exit 0.

---

## Step 1 — Idempotency check (lock file)

```
LOCK = .crew/locks/resume-{checkpoint_id}.lock
```

1. If `LOCK` exists and was modified within the last 10 minutes:
   - Print: "Resume already in progress (locked at {timestamp}). Skipping."
   - Exit 0 — another instance is handling it.

2. Otherwise, claim the lock:
   ```bash
   mkdir -p .crew/locks
   touch .crew/locks/resume-{checkpoint_id}.lock
   ```

3. On exit (success OR error), `rm -f` the lock so a future scheduled task can retry.

---

## Step 2 — Verify it's safe to resume

Read the checkpoint's `scheduled_resume_at` field.

```
now = current UTC time
target = checkpoint.scheduled_resume_at
delta = (now - target).total_seconds()
```

| Condition | Action |
|---|---|
| `delta < -300` (more than 5 min early) | Warn user: "Scheduled for {target}, currently {now}. Resume anyway?" → `AskUserQuestion`. If "No", exit. |
| `-300 ≤ delta ≤ 86400` (within ±1 day window) | Proceed normally. |
| `delta > 86400` (over a day late) | Warn: "Checkpoint is more than 24h old. State may be stale. Resume anyway, archive, or discard?" → `AskUserQuestion`. |

---

## Step 3 — Restore state

Read the checkpoint:

```yaml
timestamp:               2026-05-08T15:30:00Z
reason:                  budget_stop
feature_id:              user-auth
phase:                   3
next_step:               dispatch_api_engineer
estimated_tokens_used:   4_900_000
blocked_op:
  op_type: api_engineer_full_feature
  op_cost: 45_000
scheduled_resume_at:     2026-05-08T20:40:00Z
schedule_command:        /crew resume 2026-05-08T15-30-00Z-user-auth
```

1. **Verify `current-feature.yaml` matches.** If `feature_id` differs from what's in `.crew/current-feature.yaml`, dispatch `AskUserQuestion`:
   - "Active feature is '{current}', checkpoint is for '{ckpt_feature}'. Switch to checkpoint feature, or stay on current and discard checkpoint?"

2. **Verify phase consistency.** If `current-phase.yaml#phase` ≠ checkpoint phase, the user has moved on; warn and confirm.

3. **Reset session usage tracking.** The rate-limit window has rolled over, so:
   ```yaml
   # .crew/usage-state.yaml
   session:
     started: {now}                    # fresh window
     estimated_tokens_used: 0          # reset
     last_updated: {now}
     log: []                            # archive previous log if you want history
     resumed_from: {checkpoint_id}
   ```
   Optionally archive the old `usage-state.yaml` to `.crew/usage-state.{prev_session_start}.yaml` for audit.

4. **Print resume context** to the user before continuing:
   ```
   ▶ Resuming from checkpoint: {checkpoint_id}
     Feature: {feature_id}
     Phase:   {phase}
     Stopped at: {timestamp}
     Was about to: {next_step}
     Token budget: reset (new session window)
   ```

---

## Step 4 — Continue from `next_step`

Dispatch back into the appropriate command/phase based on `next_step`. The mapping table:

| `next_step` value | What to do |
|---|---|
| `dispatch_pm_architect_discovery` | Re-enter `/crew drive` Phase 1 |
| `dispatch_pm_architect_architecture` | Re-enter `/crew drive` Phase 2 |
| `dispatch_pm_architect_brd` | Re-enter `/crew drive` Phase 3 |
| `dispatch_ui_engineer` | Re-enter `/crew drive` Phase 5, dispatch ui-engineer |
| `dispatch_api_engineer` | Re-enter `/crew drive` Phase 5, dispatch api-engineer |
| `dispatch_qa_engineer` | Re-enter `/crew drive` Phase 6, dispatch qa-engineer |
| `dispatch_pm_maestro_reviewer` | Re-enter `/crew drive` Phase 6, acceptance review |
| `dispatch_gap_finder` | Re-enter `/crew drive` Phase 7 |
| `dispatch_code_reviewer` | Re-enter Phase 4 (Quality) |
| `phase_transition_to_{N}` | Move to Phase {N} of the orchestrator |
| (custom) | If `next_step` is unrecognised, present the user with options matching the closest known steps |

After resume completes the previously-blocked op, re-run `crew-budget-check.sh` for the *next* op as normal. The resume itself does NOT bypass budget checks — if the new session window is also tight, another checkpoint may be written.

---

## Step 5 — Archive the consumed checkpoint

After successful resume + completion of the previously-blocked op:

```bash
mv .crew/checkpoints/{id}.yaml .crew/checkpoints/.consumed/{id}.yaml
```

Discarded checkpoints (`*.discarded`) and consumed checkpoints stay around for audit but never trigger another resume.

Release the lock:

```bash
rm -f .crew/locks/resume-{id}.lock
```

---

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| "No checkpoint found" | No file in `.crew/checkpoints/` | Nothing to do — exit cleanly |
| "Resume already in progress" | Lock file is fresh | Wait or `rm` the lock if stuck |
| "Checkpoint is more than 24h old" | Schedule fired late (machine asleep, etc.) | User confirms whether state is still valid |
| Mismatch between checkpoint and `current-feature.yaml` | User worked on something else after the stop | User chooses which to keep |
| Same `next_step` blocks again on second run | Budget reset didn't actually happen (rate limit still active) | Budget check writes another checkpoint; second scheduled task fires later |
