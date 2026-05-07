<div align="center">

# Crew

**Turn Claude Code into a structured development team.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) [![Claude Code](https://img.shields.io/badge/Claude%20Code-Framework-blueviolet)](https://docs.anthropic.com/en/docs/claude-code) [![Agents](https://img.shields.io/badge/Agents-20-blue)](#agents) [![Phases](https://img.shields.io/badge/Phases-6-green)](#the-phases) [![Forked from archflow](https://img.shields.io/badge/forked%20from-archflow%201.2.3-orange)](https://github.com/azidan/archflow) [![Integrates with Gang](https://img.shields.io/badge/integrates%20with-Gang-cyan)](https://github.com/ebnrdwan/GangPlugin)

[Quick Start](#quick-start) · [How It Works](#how-it-works) · [Phases](#the-phases) · [Agents](#agents) · [Commands](#commands) · [Gang Integration](#gang-integration)

<img src="docs/crew-overview.svg" alt="Crew Overview" width="700" />

</div>

---

## What is Crew?

Crew is a **phase-based AI development framework** for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It orchestrates 16+ specialized agents through a structured workflow — from product strategy to production deployment.

Instead of one AI doing everything, each task goes to an agent with deep expertise in its domain. A `product-strategist` defines business goals. A `ux-designer` creates the design system. An `api-contract-architect` locks down API specs. Then `ui-engineer` and `api-engineer` build frontend and backend in parallel — coordinated through file-based handoffs and mandatory approval gates.

Crew works with any project type — fullstack, frontend-only, backend-only, or mobile — and adapts its phases, agents, and artifact structure accordingly.

---

## Quick Start

### 1. Add the Marketplace (one-time)

```bash
# Once you publish this fork to your own GitHub, replace <owner> below:
claude plugin marketplace add crew https://github.com/<owner>/crew

# Or install locally for development:
mkdir -p ~/.claude/plugins/local
ln -s "$(pwd)/plugin" ~/.claude/plugins/local/crew
```

### 2. Install the Plugin

```bash
claude plugin install crew --scope project
```

This saves the plugin reference to `.claude/settings.json` in your repo — any team member who clones gets prompted to install automatically.

Free and open source. No lock-in. Uninstall anytime with `claude plugin uninstall crew`.

### 3. Start Your Project

Open Claude Code in your project directory:

```bash
cd your-project
claude
```

- **New project?** Crew starts at Phase 1 (Strategy).
- **Existing codebase?** Run `/crew onboard` — agents analyze your code, import context from your tools, and generate all artifacts for approval.

### 4. Develop Features

```
/crew feature          # Interactive wizard
/crew feature login    # Quick-add by name
```

Crew creates the feature branch, breaks it into tasks, and guides implementation through the appropriate agents. Features are filtered by scope — a `backend_only` repo only sees backend-scoped features from the roadmap.

---

## How It Works

Building software with AI means context gets lost, quality varies, and the same mistakes repeat. Crew fixes this with three ideas:

- **Specialized agents** — A UX designer doesn't write backend code. An API engineer doesn't make design decisions. 16+ agents, each scoped to one domain.
- **File-based handoffs** — Context survives between conversations. Agents communicate through artifacts, not chat — so nothing gets lost when a session ends.
- **Phase gates** — 6 phases from strategy to deployment. Nothing moves forward without your approval. No skipped steps. No autonomous decisions on what ships.
- **Contract-first development** — API contracts are defined before implementation. Frontend and backend build against the same spec, so they never disagree.
- **Focused context** — Each phase loads only what the active agents need. Less noise, better results.
- **Acceptance testing** — Features aren't done until they pass acceptance testing against your roadmap criteria.

---

## The Phases

```
Phase 1    Strategy & Planning         product-strategist, feature-planner
Phase 2    Design                      ux-designer, dsl-generator
Phase 2.25 High-Fidelity Screens       SuperDesign MCP (optional)
Phase 2.5  API Architecture            api-contract-architect
Phase 3    Implementation (Parallel)   ui-engineer + api-engineer, qa-engineer, pm-maestro-reviewer
Phase 4    Quality & Optimization      code-reviewer, performance-optimizer, pm-maestro-reviewer
Phase 5    Launch & Operations         devops-engineer, post-launch-analyst
Phase 6    Enhancement (On-Demand)     i18n-engineer, post-launch-analyst, any agent as needed
```

Each phase has explicit completion criteria, expected output artifacts, and requires user approval before advancing.

---

## Works with Existing Projects

Most AI workflows assume you're starting from scratch. Crew meets you where you are.

Run `/crew onboard` and it dispatches up to 9 agents in parallel to deeply analyze your codebase. They import context from tools you already use (Jira, Notion, Linear, GitHub, Confluence, Slack), reverse-engineer your design system and API contracts, and drop you into the right phase based on what already exists.

```
Phase A: Interactive Collection     Answer 5 questions about your stack and context sources

Phase B: Autonomous Agent Dispatch  Up to 9 agents analyze your codebase in parallel:
                                    codebase audit → doc deep-dive → design extraction →
                                    route/API extraction → product-strategist → ux-designer →
                                    api-contract-architect → dsl-generator → feature-planner

Phase C: Synthesis & Presentation   Artifacts generated and presented for your approval
```

The onboarding agents generate ready-to-use `project-context.md`, `roadmap.yaml`, `api-contract.md`, `theme.yaml`, `styled-dsl.yaml`, and `user-flows.md` — all reverse-engineered from your existing code and imported documentation. It also creates or updates your project's `CLAUDE.md` with architecture context derived from the analysis.

**New project?** `/crew init` starts you at Phase 1 with a clean slate.

---

## Agents

| Phase | Agents |
|-------|--------|
| 1. Strategy & Planning | `product-strategist`, `feature-planner` |
| 2. Design | `ux-designer`, `dsl-generator` |
| 2.25 High-Fidelity (optional) | SuperDesign MCP |
| 2.5 API Architecture | `api-contract-architect` |
| 3. Implementation | `ui-engineer`, `api-engineer`, `qa-engineer`, `pm-maestro-reviewer` |
| 4. Quality & Optimization | `code-reviewer`, `performance-optimizer`, `pm-maestro-reviewer` |
| 5. Launch & Operations | `devops-engineer`, `post-launch-analyst` |
| 6. Enhancement | `i18n-engineer`, any agent as needed |

---

## Commands

### Core (inherited from archflow)
| Command | What it does |
|---------|-------------|
| `/crew` | Show available subcommands and current project status |
| `/crew init` | Initialize a new project at Phase 1 |
| `/crew onboard` | Analyze an existing codebase and generate all artifacts |
| `/crew feature [name]` | Add a feature, create branches, assign agents |
| `/crew setup-mcp [tool]` | Connect external tools (Jira, Notion, Linear, GitHub, etc.) |

### Workflow extensions (Crew additions)
| Command | What it does |
|---------|-------------|
| `/crew drive [name]` | End-to-end product-led feature dev: pm-architect → implementation → QA → gap audit |
| `/crew deploy [flags]` | Pre-deployment checklist with auto-remediation (verify env → health checks → dispatch fix agents) |
| `/crew gaps [url]` | Gap-finder audit and fix pipeline (audit UI → analyze gaps → create fixes → verify) |
| `/crew features [filters]` | Feature dashboard with status, pages, navigation flow, and acceptance progress |

### Gang integration (Crew additions)
| Command | What it does |
|---------|-------------|
| `/crew gang-import <slug>` | Import a Gang evaluation (GO Package) as a Crew feature, preserving CONDITIONAL-GO conditions as phase-3 gates |
| `/crew gang-escalate <slug>` | Send a stalled or invalidated Crew feature back to Gang for re-scoring |

---

## Gang Integration

Crew works **better when paired with [Gang](https://github.com/ebnrdwan/GangPlugin)** — a separate plugin that runs a 6-stage strategic committee (PM, Market, Finance, Architect, Domain Expert, CEO/CTO Advisor) and produces an evidence-backed GO Package for any feature.

```
Gang answers:  "Should we build it?"          → produces GO Package
Crew  answers: "How do we ship it?"            → consumes GO Package
```

**Lifecycle:**

1. **Gang evaluates the feature** — runs `/gang init … advise … deliver` to produce BRD, charter, risk register, data model, API contracts, and a verdict (GO / CONDITIONAL-GO / NO-GO).
2. **Crew imports the verdict** — `/crew gang-import <slug>` reads `.gang/features/<slug>/go-package/*.md`, seeds a `roadmap.yaml` entry, and copies CONDITIONAL-GO conditions verbatim. **Phase-3 implementation will not unlock until those conditions are validated.**
3. **Crew executes** — features march through phases 2 → 5 with the right agents per phase.
4. **Crew can escalate back** — if execution reveals new evidence that contradicts Gang's verdict, `/crew gang-escalate <slug>` packages the current state for `/gang reinit`. Fresh verdict comes back, re-import to update.

A dedicated `gang-bridge` agent (in `plugin/agents/`) handles all state translation between `.gang/` and `.crew/` so the two plugins stay in sync without manual copy/paste. Full lifecycle docs at [`plugin/skills/crew/references/gang-integration.md`](plugin/skills/crew/references/gang-integration.md).

**Requirements:**
- Gang plugin v1.3.0+ installed at `~/.claude/plugins/marketplaces/gang-marketplace/`
- A Gang evaluation that has reached at least the `advise` stage (`deliver` recommended for full GO Package)

---

## Project Types

Crew detects and adapts to your project type:

| Type | Frontend Agent | Backend Agent | Notes |
|------|---------------|---------------|-------|
| `fullstack` | Yes | Yes | Parallel frontend/backend development |
| `frontend_only` | Yes | No | Pages, components, flows |
| `backend_only` | No | Yes | Endpoints, services, modules |
| `mobile` | Yes | Yes | React Native, SwiftUI, or Jetpack Compose |

Phase instructions, agent selection, audit checks, and roadmap structure all adapt to the project type.

---

## Git Workflow

Crew uses a structured branching strategy:

```
main
 └── feature/user-auth              (feature branch)
      ├── user-auth/login-form       (task branch)
      ├── user-auth/auth-api         (task branch)
      └── user-auth/session-mgmt     (task branch)
```

- Feature branches from `main`
- Task branches from the feature branch
- Merges only happen after explicit user approval
- Feature completion triggers cleanup and roadmap updates

---

## Key Artifacts

Crew manages these files in your project:

| File | Purpose |
|------|---------|
| `.crew/project-context.md` | Business goals, tech stack, architecture decisions |
| `.crew/roadmap.yaml` | Feature roadmap and sprint planning |
| `.crew/current-phase.yaml` | Phase state tracker (auto-created) |
| `.crew/current-feature.yaml` | Active feature scope and task tracking |
| `docs/api-contract.md` | API specifications (single source of truth) |
| `design-artifacts/styled-dsl.yaml` | Component specifications with styling |
| `design-artifacts/theme.yaml` | Design system tokens |
| `design-artifacts/wireframes/` | Screen layouts |
| `docs/acceptance-reports/` | Maestro acceptance test results |

---

<details>
<summary><strong>File Structure</strong></summary>

Crew is distributed as a Claude Code plugin marketplace. The plugin contains all framework code; your project only stores state files.

### Marketplace (this repo)

```
crew/
├── .claude-plugin/marketplace.json  # Marketplace registry
├── plugin/                          # Installable plugin
│   ├── .claude-plugin/plugin.json   # Plugin manifest
│   ├── hooks/hooks.json             # SessionStart hook (loads instructions after compaction)
│   ├── agents/                      # 17 specialized agent definitions
│   ├── skills/crew/             # Slash command implementations
│   │   ├── SKILL.md                 # Router (onboard, feature, setup-mcp)
│   │   ├── mcp-registry.yaml        # Curated MCP server registry
│   │   └── commands/
│   │       ├── onboard.md           # /crew onboard
│   │       ├── feature.md           # /crew feature
│   │       └── setup-mcp.md         # /crew setup-mcp
│   └── .crew/                   # Framework instructions and phase files
│       ├── instructions.md          # Core instructions (reloaded via hook)
│       ├── workflow.md              # Git branching strategy
│       ├── base-dsl-structure.yaml  # DSL template for design artifacts
│       └── phases/                  # Phase-specific instruction files (10 files)
├── README.md
└── LICENSE
```

### Project (created by `/crew onboard` or Phase 1 setup)

```
your-project/
├── .crew/                       # Project state (version-controlled)
│   ├── current-phase.yaml           # Phase state tracker
│   ├── project-context.md           # Business goals, tech stack, architecture
│   ├── roadmap.yaml                 # Feature roadmap and sprint planning
│   └── current-feature.yaml         # Active feature scope and tasks
├── .claude/settings.json            # Plugin reference (auto-created on install)
└── CLAUDE.md                        # Updated with Crew section by onboarding
```

</details>

<details>
<summary><strong>External Tool Integration</strong></summary>

The `/crew setup-mcp` command configures MCP servers to connect with your existing tools:

| Tool | Transport | Purpose |
|------|-----------|---------|
| Jira | HTTP/OAuth | Import epics, stories, sprint data |
| Confluence | HTTP/OAuth | Import documentation |
| Notion | HTTP/OAuth | Import pages and databases |
| Linear | HTTP/OAuth | Import issues, projects, cycles |
| GitHub | HTTP/OAuth | Import issues, PRs, project boards |
| Google Drive | stdio/OAuth | Import Google Docs and Sheets |
| Slack | HTTP/OAuth | Import context from channels/threads |
| Trello | stdio/env | Import boards, lists, cards |

These integrations are primarily used during `/crew onboard` to pull existing project context into Crew's format.

</details>

---

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (latest version)
- Git
- Node.js (for some MCP servers)

---

## Contributing

Contributions are welcome. Areas of interest:

- **New agents** — Add specialized agents in `agents/` following the existing format
- **Phase improvements** — Refine phase instructions in `.crew/phases/`
- **MCP registry** — Add tool integrations in `skills/crew/mcp-registry.yaml`
- **Bug fixes** — Open an issue or submit a PR

---

## Community & Support

- **Bug reports:** [GitHub Issues](https://github.com/AZidan/archflow/issues)
- **Feature requests:** [GitHub Issues](https://github.com/AZidan/archflow/issues)
- **Questions:** [GitHub Discussions](https://github.com/AZidan/archflow/discussions)

---

## Differences from upstream archflow

Crew is a deliberate fork of [archflow v1.2.3](https://github.com/azidan/archflow). Diff in one table:

| Area | archflow 1.2.3 | crew 0.1.0 |
|------|-----------------|-------------|
| Slash command | `/archflow` | `/crew` |
| State directory | `.archflow/` | `.crew/` (lets a project run Crew + Gang side-by-side without conflict) |
| Subcommands | `init`, `onboard`, `feature`, `setup-mcp` | + `drive`, `deploy`, `gaps`, `features`, `gang-import`, `gang-escalate` |
| Agents | 17 specialised engineering agents | + `gap-finder`, `pm-architect`, `gang-bridge` (20 total) |
| Gang plugin handoff | manual (copy/paste between the two plugins' state) | first-class commands (`gang-import`, `gang-escalate`) and a dedicated `gang-bridge` agent |
| CONDITIONAL-GO gating | conditions documented in the BRD but not enforced | phase-3 implementation refuses to activate until conditions are validated |
| Plugin manifest | `name: archflow` | `name: crew`, with an `upstream` block recording the fork point |

All upstream archflow agents are preserved unchanged (apart from `archflow → crew` text rebranding). Phase definitions and DSL/roadmap schemas are unchanged. The fork is **strictly additive**.

If you don't need Gang integration or the `drive`/`deploy`/`gaps`/`features` commands, [archflow upstream](https://github.com/azidan/archflow) is the simpler choice — keep tracking it.

### Tracking upstream

To pull future archflow improvements into Crew:

```bash
# Add archflow as an upstream remote (one-time)
git remote add upstream https://github.com/azidan/archflow.git

# Periodically:
git fetch upstream
git checkout main
git merge upstream/main           # may need conflict resolution on rebranded files
# Re-run the rebrand script to clean up any stray "archflow" references introduced by the merge
```

---

## License

MIT License — see [LICENSE](LICENSE) for details. Original work © AZidan; fork modifications © ebnrdwan.

---

<div align="center">

**Crew: Because building software deserves structure, not chaos.**

[Back to top](#crew)

</div>
