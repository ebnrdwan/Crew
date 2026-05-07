# /crew deploy — Pre-Deployment Verification & Remediation

Full-stack deployment checklist with agent-powered auto-remediation and observation tracking.

## Usage
```
/crew deploy              # Run full checklist
/crew deploy --phase 1    # Pre-deploy checks only
/crew deploy --phase 2    # Service health checks only
/crew deploy --fix        # Auto-dispatch agents to fix failures
/crew deploy --skip-build # Skip frontend build step
/crew deploy --skip-tests # Skip backend test step
```

## Flow

### Step 0: Prerequisites

1. Verify `.crew/current-phase.yaml` exists:
   - If missing: "No project onboarded. Run `/crew onboard` first."
   - If exists: read current phase
2. If current phase < 5 (Launch), show warning:
   ```
   ⚠ Project is in Phase {N} ({name}). Deploy checklist is typically
   run in Phase 5 (Launch). Proceed anyway? [Yes / No]
   ```
3. Read `.crew/project-context.md` for deployment context
4. Read `.crew/roadmap.yaml` to check for deployment-related stories

### Step 1: Run Checklist Script

Execute the deploy checklist script:
```bash
bash scripts/deploy_checklist.sh --json {pass through user flags}
```

If the script doesn't exist at `scripts/deploy_checklist.sh`:
```
Deploy checklist script not found. This is required for /crew deploy.
The script should exist at scripts/deploy_checklist.sh in the project root.
```

Parse the JSON output into structured results.

### Step 2: Present Results

Show results grouped by category as a markdown checklist:

```markdown
## Deploy Checklist — {project name}
**Phase:** {current phase} | **Date:** {timestamp}
**Status:** ready | blocked | partial

| Category | Passed | Failed | Skipped |
|----------|--------|--------|---------|
| env      | 8      | 1      | 0       |
| docker   | 3      | 0      | 0       |
| ...      | ...    | ...    | ...     |

### Failures
- [ ] [env] SECRET_KEY is not default → Still using default insecure key
- [ ] [frontend] Vite production build → Build failed
```

### Step 3: Agent Dispatch

If there are failures AND (user passed `--fix` OR user approves fix):

For each failure category, dispatch the appropriate crew agent:

| Failure Category | Agent | Dispatch Prompt |
|-----------------|-------|-----------------|
| Build/compile errors | `build-error-resolver` | "Deploy checklist found build failure: {error}. Fix the build error in {project root}. Read the relevant source files and fix the issue." |
| Test failures | `qa-engineer` | "Deploy checklist found test failures: {error}. Investigate and fix the failing tests. Project: {project root}." |
| Security issues (`env`, `security`) | `security-reviewer` | "Deploy checklist found security issue: {error}. Scan for secrets, insecure defaults, and fix. Project: {project root}." |
| Infrastructure (`docker`, `containers`) | `devops-engineer` | "Deploy checklist found infrastructure issue: {error}. Fix Docker/compose configuration. Compose file: backend/docker-compose.yml." |
| Frontend build | `ui-engineer` | "Deploy checklist found frontend build failure: {error}. Fix the build error in frontend/. Run npm run build to verify." |
| API health failures | `api-engineer` | "Deploy checklist found API health failure: {error}. Debug the endpoint issue. Backend entry: backend/api/main.py." |
| ML model issues | — | Flag for manual review. Print: "ML model issues require manual investigation. Known bugs: cluster mapping, single-sample normalization." |

**Agent dispatch rules:**
- Provide context from `.crew/project-context.md` and `.crew/current-phase.yaml`
- Wait for each agent to complete
- After all agents complete, present results summary

**Without `--fix` flag:**
Present failures and ask:
```
>>> APPROVAL GATE
{N} check(s) failed. Options:
1. Auto-fix — dispatch agents to resolve failures
2. Re-run — run checklist again (after manual fixes)
3. Skip — proceed with known failures
4. Stop — abort deployment
```

### Step 4: Re-verify

After agent fixes complete, re-run the checklist:
```bash
bash scripts/deploy_checklist.sh --json {same phase flags}
```

Present updated results. If new failures appear, repeat Step 3.

### Step 5: Update Observations

After checklist completes (pass or fail), write deployment observations.

**Write `.crew/deploy-observations.yaml`:**

```yaml
last_check: "{ISO 8601 timestamp}"
status: "ready"  # ready | blocked | partial
phase_run: "{phase argument or all}"
summary:
  passed: 42
  failed: 0
  skipped: 3
blockers: []  # List of unresolved failures
  # - category: "ml"
  #   check: "Model file: regime_detector.pkl"
  #   error: "File exists but suspiciously small"
  #   severity: "high"
agents_dispatched: []  # List of agents that were called
  # - agent: "build-error-resolver"
  #   category: "frontend"
  #   result: "fixed"  # fixed | failed | skipped
  #   timestamp: "{ISO 8601}"
history:
  - timestamp: "{ISO 8601}"
    status: "blocked"
    failed: 3
    note: "Frontend build failed, 2 env vars missing"
  # Keep last 5 entries
```

**If all checks pass**, also update `.crew/current-phase.yaml`:
- Add `deployment_ready: true` and `deployment_checked: "{timestamp}"` under the current phase

### Step 6: Final Approval Gate

```
>>> USER APPROVAL GATE

Deploy Checklist Complete
━━━━━━━━━━━━━━━━━━━━━━━
Passed: {N} | Failed: {N} | Skipped: {N}
Status: {ready | blocked | partial}

{If ready}
✓ All checks passed. Ready to deploy.
→ Proceed with deployment? [Yes / Re-run / Stop]

{If blocked}
✗ {N} blocker(s) remain:
  - {list blockers}
→ Options: [Fix again / Skip blockers / Stop]

{If partial}
~ {N} check(s) skipped (non-blocking):
  - {list skipped}
→ Proceed with deployment? [Yes / Re-run / Stop]
```

If user approves deployment, print:
```
Run deployment with:
  bash scripts/fast_deploy.sh

Or manually:
  cd backend && docker compose up -d

Then run post-deploy monitoring:
  /crew deploy --phase 4
```
