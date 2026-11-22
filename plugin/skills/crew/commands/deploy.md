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

### Step 1: Run the Checklist

Crew does not ship a checklist script. Use the project's own script when it has one, otherwise run the checklist
inline.

**1a. Project script.** If `scripts/deploy_checklist.sh` exists in the project root, run it:
```bash
bash scripts/deploy_checklist.sh --json {pass through user flags}
```
and parse its JSON output (`{category, check, status: pass|fail|skip, error}` per check) into structured results.

**1b. No project script — run the checklist inline.** Tell the user:
```
No scripts/deploy_checklist.sh in this project. Running Crew's built-in checklist inline.
(Offer: scaffold scripts/deploy_checklist.sh from these checks so the team can run it in CI? [Yes / No])
```
Then run each check below that applies to the project (detect from `.crew/project-context.md`, `package.json`,
`docker-compose*.yml`, `Dockerfile`, test config), and record each as pass / fail / skip with its error. Honour
`--phase`, `--skip-build` and `--skip-tests`.

*Phase 1 — pre-deploy checks*
| Category | Check |
|----------|-------|
| `env` | Every variable named in `.env.example` (or the project's config docs) is set for the target environment; no default or placeholder secrets (e.g. `changeme`, `secret`, `SECRET_KEY=dev`) |
| `security` | No secrets committed (scan tracked files for keys/tokens); dependency audit (`npm audit --omit=dev`, `pip-audit`, or the stack's equivalent) has no critical findings |
| `git` | Working tree clean; current branch is the one being released; tag/version bumped if the project uses them |
| `frontend` | Production build succeeds (`npm run build` or the project's build command) — skip with `--skip-build` |
| `backend` | Test suite passes (the project's test command) — skip with `--skip-tests` |
| `docker` | `docker compose config` validates; images build (`docker compose build`) when Docker is used |

*Phase 2 — service health checks* (only when the services can be started locally or a staging URL is known)
| Category | Check |
|----------|-------|
| `containers` | `docker compose up -d` starts every service and none is restarting |
| `api` | Health endpoint (from `docs/api-contract.md` or project context, e.g. `/health`) returns 200; one read endpoint returns the contracted shape |
| `frontend` | The built app serves its index page |

If the user chose to scaffold the script, write `scripts/deploy_checklist.sh` with exactly these checks (emitting the
JSON shape above), show it, and ask before keeping it. Never overwrite an existing script.

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
| Build/compile errors | `ui-engineer` (frontend) or `api-engineer` (backend) | "Deploy checklist found build failure: {error}. Fix the build error in {project root}. Read the relevant source files and fix the issue." |
| Test failures | `qa-engineer` | "Deploy checklist found test failures: {error}. Investigate and fix the failing tests. Project: {project root}." |
| Security issues (`env`, `security`) | `code-reviewer` (security review) | "Deploy checklist found security issue: {error}. Scan for secrets, insecure defaults, and propose fixes. Project: {project root}." |
| Infrastructure (`docker`, `containers`) | `devops-engineer` | "Deploy checklist found infrastructure issue: {error}. Fix the Docker/compose configuration ({compose file found in the project})." |
| Frontend build | `ui-engineer` | "Deploy checklist found frontend build failure: {error}. Fix the build error in {frontend folder}. Run the build command to verify." |
| API health failures | `api-engineer` | "Deploy checklist found API health failure: {error}. Debug the endpoint issue. Backend entry: {backend entry point from project context}." |
| Anything else | — | Flag for manual review and list it under blockers. |

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

After agent fixes complete, re-run the checklist the same way as Step 1 (the project script with the same flags, or
the inline checks).

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
  # - category: "env"
  #   check: "SECRET_KEY is not default"
  #   error: "Still using the default insecure key"
  #   severity: "high"
agents_dispatched: []  # List of agents that were called
  # - agent: "ui-engineer"
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

If user approves deployment, print the project's own deploy command (from `.crew/project-context.md`, a
`scripts/deploy*.sh`, the CI workflow, or `docker compose up -d` when the project deploys with Compose). Crew does not
run the deployment itself. Then suggest re-running `/crew deploy --phase 2` against the deployed environment for the
health checks.
