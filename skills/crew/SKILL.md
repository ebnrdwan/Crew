---
name: crew
description: Phase-based development workflow manager that guides projects through structured phases from strategy and design through implementation, quality assurance, and launch. Manages roadmaps, feature branches, agent orchestration, and MCP server configuration.
---

# /crew — Phase-Based Development Workflow

Crew manages the full software development lifecycle through structured phases, from onboarding existing codebases to launching production software.

## Usage
```
/crew                → Show available subcommands
/crew init           → Initialize Crew in a new project
/crew onboard        → Onboard an existing codebase (interactive wizard)
/crew setup-mcp      → Configure MCP servers for external tools
/crew setup-mcp jira → Configure a specific MCP server
/crew feature        → Add a new feature to the roadmap
/crew feature login  → Quick-add a feature by name
```

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

### Unknown subcommand
```
Unknown subcommand: [arg]

Available: init, onboard, setup-mcp, feature
Run /crew for help.
```
