---
name: crew
description: Phase-based development workflow manager that guides projects through structured phases from strategy and design through implementation, quality assurance, and launch. Manages roadmaps, feature branches, agent orchestration, and MCP server configuration.
---

# /crew — Phase-Based Development Workflow

Crew manages the full software development lifecycle through structured phases, from onboarding existing codebases to launching production software.

## Usage
```
/crew                         → Show available subcommands
/crew init                    → Initialize Crew in a new project
/crew onboard                 → Onboard an existing codebase (interactive wizard)
/crew setup-mcp               → Configure MCP servers for external tools
/crew setup-mcp jira          → Configure a specific MCP server
/crew feature                 → Add a new feature to the roadmap
/crew feature login           → Quick-add a feature by name
/crew drive                   → End-to-end product-led feature development
/crew drive user-auth         → Quick-start drive for a named feature
/crew gaps                    → Gap-finder audit and fix pipeline
/crew gaps http://localhost   → Audit a specific URL
/crew deploy                  → Pre-deployment checklist with auto-remediation
/crew deploy --phase 1        → Run pre-deploy checks only
/crew deploy --fix            → Auto-dispatch agents to fix failures
/crew features                → Show all features with status and context
/crew features --status done  → Filter features by status/epic/priority
/crew gang-import <slug>      → Import a Gang evaluation as a Crew feature
/crew gang-escalate <slug>    → Send a stalled Crew feature back to Gang for re-evaluation
/crew push                    → Sync the current feature to GitHub Projects (live status card)
/crew resume [id]             → Resume from a usage-budget checkpoint (or list)
/crew profile [check|set|list]→ Manage user knowledge profile per technology
```

## Gang Integration

Crew integrates with the **Gang multi-agent committee plugin**. Gang evaluates whether to build something; Crew executes the build. See `references/gang-integration.md` for the full lifecycle.

The two integration commands above (`gang-import`, `gang-escalate`) require the Gang plugin installed at `~/.claude/plugins/marketplaces/gang-marketplace/` and a Gang evaluation that has reached at least the `advise` stage.

## Subcommand Router

When the user runs `/crew`, check the argument to determine which subcommand to execute:

### No arguments → Show help
```
Crew — Phase-Based Development Workflow

Available subcommands:

  /crew init          Initialize Crew in a new project
                          (creates .crew/ state files, sets Phase 1)

  /crew onboard       Onboard an existing codebase to the phase framework
                          (detect project type, import context, audit, set phase)

  /crew setup-mcp     Configure MCP servers for external tools
                          (Jira, Notion, Linear, GitHub, SuperDesign, etc.)

  /crew feature       Add a new feature to the roadmap and start development
                          (from description, external tool link, or existing roadmap)

  /crew drive         End-to-end product-led feature development
                          (pm-architect → implementation → QA → gap audit)

  /crew deploy        Pre-deployment checklist with auto-remediation
                          (verify env → health checks → dispatch agents → update observations)

  /crew gaps          Gap-finder audit and fix pipeline
                          (audit UI → analyze gaps → create fixes → verify)

  /crew features      Feature dashboard — show all roadmap features
                          (status, pages, navigation flow, acceptance progress)

  /crew gang-import   Import a Gang evaluation (GO Package) as a Crew feature
                          (requires the Gang plugin and a completed evaluation)

  /crew gang-escalate Escalate a stalled or invalidated Crew feature back to Gang
                          (for re-scoring when scope or assumptions change)

  /crew push          Sync the current feature to GitHub Projects v2
                          (live status card, updates Status field per phase)

  /crew resume        Resume from a usage-budget checkpoint
                          (auto-fired by scheduled tasks; can run manually)

  /crew profile       Manage user knowledge profile per technology
                          (one-time per tech; cached; sets plain-English mode
                           when any tech is none/low)

Current project status:
  → Read .crew/current-phase.yaml if it exists, show phase + project type
  → If missing: "No project onboarded. Run /crew onboard to get started."
```

### `init` → Load project initializer
Read and follow `skills/crew/commands/init.md`

### `onboard` → Load onboarding wizard
Read and follow `skills/crew/commands/onboard.md`

### `setup-mcp` → Load MCP setup helper
Read and follow `skills/crew/commands/setup-mcp.md`
Pass any additional arguments (e.g., `jira`, `notion`) as the tool name.

### `feature` → Load feature command
Read and follow `skills/crew/commands/feature.md`
Pass any additional arguments (e.g., `login`) as the feature name for quick-add.

### `drive` → Load drive command
Read and follow `skills/crew/commands/drive.md`
Pass any additional arguments (e.g., `user-authentication`) as the feature name for quick-start.

### `deploy` → Load deploy command
Read and follow `skills/crew/commands/deploy.md`
Pass any additional arguments (e.g., `--phase 1`, `--fix`, `--skip-build`, `--skip-tests`) as flags.

### `gaps` → Load gaps command
Read and follow `skills/crew/commands/gaps.md`
Pass any additional arguments (e.g., `http://localhost:5173`) as the target URL.
Also pass any flags (`--quick`, `--a11y`, `--responsive`, `--compare {url}`).

### `features` → Load features command
Read and follow `skills/crew/commands/features.md`
Pass any flags (`--status`, `--epic`, `--priority`) as filters.

### `gang-import` → Load Gang import command
Read and follow `skills/crew/commands/gang-import.md`
Pass the Gang evaluation slug as the argument. Dispatches the `gang-bridge` agent.

### `gang-escalate` → Load Gang escalation command
Read and follow `skills/crew/commands/gang-escalate.md`
Pass the Crew feature ID as the argument. Dispatches the `gang-bridge` agent.

### `push` → Load GitHub Projects sync command
Read and follow `skills/crew/commands/push.md`
Creates a draft card on GitHub Projects v2 board(s) for the current feature, or updates
the existing card's Status field based on the current phase. Pass `--dry-run` to preview
without making API calls. Pass a feature ID as positional arg to push a specific feature
instead of the current one.

### `resume` → Load resume-from-checkpoint command
Read and follow `skills/crew/commands/resume.md`
Resumes a feature build that was paused by the usage-budget system. With no argument,
resumes from the most recent checkpoint. Pass a checkpoint ID for a specific one,
`--list` to see all checkpoints, or `--discard {id}` to mark one as won't-resume.
This is idempotent — concurrent invocations on the same checkpoint are safe.

### `profile` → Load user-profile command
Read and follow `skills/crew/commands/profile.md`
Manages the user's per-technology knowledge profile. Subcommands: `check` (default —
detects techs and asks about new ones), `set <tech> <level>`, `list`, `clear <tech>`,
`reset`. When any cached tech is none/low, all subsequent agent dispatches get a
"PLAIN ENGLISH MODE" prefix.

### Unknown subcommand
```
Unknown subcommand: [arg]

Available: init, onboard, setup-mcp, feature, drive, deploy, gaps, features, gang-import, gang-escalate, push, resume, profile
Run /crew for help.
```
