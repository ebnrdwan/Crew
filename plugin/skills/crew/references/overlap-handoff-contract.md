# Overlap & Handoff Contract — Gang → Crew

When `/crew gang-import <slug>` runs, the `gang-bridge` agent has to decide which Crew agents are *redundant* (Gang already produced their output) and which Crew agents must still run. This doc spells out that contract so it's not a per-feature judgement call.

> **Sister doc:** [gang-integration.md](./gang-integration.md) covers the lifecycle, state files, and conceptual model. This doc covers the *artifact-level skip rules*.

---

## Why a contract is needed

Crew was forked from archflow before Gang existed. Gang grew its own deliverables independently. Both systems then needed BRDs, architecture docs, API contracts, personas — because every dev workflow does. The result: **six artifact types are produced by agents in both systems.**

Without an explicit contract, two failure modes happen:
- **Double work** — `pm-architect` re-derives the BRD that Gang's CEO/CTO Advisor already wrote.
- **Silent drift** — Crew's regenerated artifact doesn't match Gang's; downstream Crew agents follow Crew's version; the Gang-side decision becomes detached from what's actually being built.

The contract below tells `gang-bridge` exactly what to copy, what to translate, and what each Crew agent should check before running.

---

## The 6 overlap zones

| # | Artifact | Gang producer | Gang output path | Crew producer (default) | Crew output path |
|---|---|---|---|---|---|
| 1 | **BRD / requirements** | Deliverables Writer | `.gang/features/<slug>/go-package/brd.md` | `feature-planner` + `pm-architect` | `.crew/features/<slug>/brd.md` |
| 2 | **Architecture / ADR** | Solutions Architect | `.gang/features/<slug>/go-package/architecture.md` | `pm-architect` | `.crew/features/<slug>/architecture.md` |
| 3 | **API contracts** | Deliverables Writer | `.gang/features/<slug>/go-package/api-contracts.md` | `api-contract-architect` | `docs/api-contract.md` |
| 4 | **Personas + journeys** | UX Researcher | `.gang/features/<slug>/ux/personas.md`, `journeys.md` | `ux-designer` | `.crew/features/<slug>/personas.md`, `journeys.md` |
| 5 | **Design tokens / wireframes** | UX Researcher | `.gang/features/<slug>/ux/design-tokens.yaml`, `wireframes.md` | `ux-designer` + `dsl-generator` | `design-artifacts/styled-dsl.yaml` |
| 6 | **Risk register / project charter** | Finance Analyst + Deliverables Writer | `.gang/features/<slug>/go-package/risk-register.md`, `charter.md` | (covered in `pm-architect` BRD) | `.crew/features/<slug>/charter.md` |

---

## Skip rules

For each zone, `gang-bridge` declares one of three states in `.crew/imports.yaml#features[<slug>].artifacts[<zone>]`:

| State | Meaning | Crew agent behaviour |
|---|---|---|
| `imported` | Gang artifact copied/translated into Crew filesystem; treated as authoritative | The Crew agent for that zone **skips entirely** and logs `skipped (gang-imported)` to its phase output |
| `seeded` | Gang artifact copied as a *starting draft*; Crew agent must refine, not regenerate | The Crew agent **runs in refine mode** — reads the seed, produces deltas only, never overwrites unless explicitly told |
| `absent` | Gang did not produce this artifact (or it was rejected during import) | The Crew agent **runs normally** from scratch |

The default state per zone depends on the **Gang verdict + card type**:

| Gang verdict | Card type | BRD | Architecture | API contract | UX (personas/journeys) | UX (tokens/wireframes) | Risk register |
|---|---|---|---|---|---|---|---|
| GO | feature / enhancement | `imported` | `imported` | `imported` | `imported` | `seeded` | `imported` |
| GO | initiative | `imported` | `seeded` | `seeded` | `imported` | `seeded` | `imported` |
| CONDITIONAL-GO | feature / enhancement | `seeded` | `seeded` | `seeded` | `seeded` | `seeded` | `imported` |
| CONDITIONAL-GO | spike / change | `seeded` | `absent` | `absent` | `seeded` | `absent` | `seeded` |
| (any) | spike | `seeded` | `absent` | `absent` | `seeded` | `absent` | `absent` |

**Rationale**:
- Unconditional GO on a `feature` means Gang debated it deeply enough that re-deriving the BRD is pure waste — `imported`.
- CONDITIONAL-GO carries unvalidated assumptions; downstream Crew agents may discover the contract needs to change as conditions resolve — `seeded` lets them edit.
- `spike` cards are exploratory by definition; Gang wasn't trying to produce a build-grade architecture — `absent` means the Crew agent runs fully.
- API contracts have a special rule: **even when `imported`, `api-contract-architect` runs in *validation mode*** — it reads the imported contract, checks schema validity, and confirms it covers every endpoint referenced by `feature-planner`'s user stories. If it doesn't, `gang-bridge` flips that zone from `imported` → `seeded` and logs the gap.

---

## What `gang-bridge` actually does

```
1. Read   .gang/features/<slug>/state.json
2. Verify state.advise.verdict ∈ {GO, CONDITIONAL-GO}
3. Read   .gang/features/<slug>/state.json#card_type
4. Look up the row in the table above
5. For each zone:
     a. If Gang artifact exists:
          - Copy/translate to Crew output path
          - Write `imported` or `seeded` per the rule
     b. If Gang artifact missing:
          - Write `absent`; flag in import report
6. Write   .crew/imports.yaml entry with full audit trail:
     - source_slug, source_verdict, source_card_type
     - artifacts: { brd: imported, architecture: seeded, ... }
     - skipped_agents: [pm-architect, api-contract-architect, ...]
     - imported_at: <ISO timestamp>
7. Write   .crew/roadmap.yaml entry with source.origin = "gang"
8. Print a handoff summary to the user listing:
     - Which Crew agents will be skipped
     - Which will run in refine mode
     - Which CONDITIONAL conditions block phase-3
```

---

## How Crew agents check the contract

Every Crew agent in an overlap zone reads `.crew/imports.yaml` at the top of its run:

```yaml
# .crew/imports.yaml
features:
  invoice-pdf-export:
    source_slug: invoice-pdf-export
    source_verdict: CONDITIONAL-GO
    source_card_type: feature
    artifacts:
      brd: seeded
      architecture: seeded
      api_contract: seeded
      ux_personas: seeded
      ux_tokens: seeded
      risk_register: imported
    skipped_agents: []
    refine_mode_agents:
      - pm-architect
      - api-contract-architect
      - ux-designer
      - dsl-generator
    imported_at: 2026-05-07T15:42:00Z
```

If the agent's name is in `skipped_agents`, the agent prints `Skipping: artifact already imported from Gang (<source_slug>)` and exits with success.

If the agent's name is in `refine_mode_agents`, the agent reads the seed file, computes deltas, and writes a `*.refinements.md` file alongside (never overwrites the seed).

If neither applies, the agent runs normally.

---

## Conflict handling

Three failure modes worth thinking through:

**1. Gang artifact is stale.** Gang ran 3 months ago, market shifted, the BRD's assumptions are now wrong. → User runs `/crew gang-escalate <slug>` (see [gang-integration.md](./gang-integration.md#conditional-go-conditions)). Gang re-evaluates; if the verdict survives, Crew re-imports with fresh artifacts.

**2. Imported artifact contradicts Crew agent's findings.** `api-contract-architect` running in validation mode finds that `feature-planner`'s newly-written user stories reference an endpoint Gang's contract doesn't define. → Agent flips that zone from `imported` → `seeded` in `.crew/imports.yaml`, prints a `CONTRACT-DRIFT` warning to the phase log, and runs in refine mode to add the missing endpoint.

**3. Multiple Gang slugs map to one Crew feature.** Two Gang evaluations were imported (e.g., `invoice-pdf-export` and `invoice-csv-export`) and a user wants them merged into one Crew feature. → `gang-bridge --merge` (planned, not implemented) takes both slugs, runs all artifacts through `seeded` mode regardless of original verdict, and unions the conditions list. For now, merge manually after import.

---

## What this contract is not

- **It's not security/permissions.** Gang artifacts are trusted because they came from a tool the user explicitly invoked. There's no signing/verification.
- **It's not bidirectional.** Crew artifacts don't flow back to Gang automatically. `gang-escalate` sends a *summary* of why Crew is stuck, not the full Crew output tree.
- **It's not version-pinned.** Today the contract assumes Gang v1.3.x and Crew v0.1.0. As either evolves, this table needs updating. Treat it as a living document, not a frozen spec.

---

## Quick reference card (for agents)

> Drop this into the system prompt of any overlap-zone Crew agent.

```
BEFORE running:
  1. cat .crew/imports.yaml
  2. Find the current feature's entry
  3. Check artifacts.<your_zone>:
     - "imported" → exit success, log "skipped (gang-imported)"
     - "seeded"   → run in refine mode, write deltas only
     - "absent"   → run normally, write to your default output path
  4. If .crew/imports.yaml does not exist or feature not listed:
     → run normally (this feature did not come from Gang)
```
