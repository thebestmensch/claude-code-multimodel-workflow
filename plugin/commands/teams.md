---
description: Orchestrate a multi-codebase feature using Agent Teams. Spawns coordinated subagents that share a written contract, user-invoke only because the blast radius spans services.
disable-model-invocation: true
effort: high
---

Orchestrate a feature implementation using Agent Teams with coordinated specialized agents.

Use this when the task requires changes across multiple codebases, services, or domains that can be worked in parallel by agents who need to coordinate on shared contracts.

## When NOT to use this

- Changes only touch one codebase: use SDD instead
- The feature is small enough for direct execution (< 15 min of work)
- The shared contract is already established and stable: agents don't need to negotiate

## Red Flags

If you catch yourself thinking any of these, STOP, you're about to spawn agents that will build against different contracts.

| Excuse | Reality |
|--------|---------|
| "The contract is obvious, I don't need to write it down" | "Obvious" contracts produce the most mismatches. If agents don't share the same document, they build different assumptions. |
| "I'll let the agents figure out the interface" | Agents can't negotiate. They'll each build their side and you'll discover the mismatch at integration. |
| "One agent can start while I define the contract for the other" | The first agent will make contract decisions you haven't reviewed. Now you're integrating against two contracts. |
| "This is small enough for one agent" | If it crosses codebases, it needs a contract. Size doesn't determine coordination needs, boundaries do. |
| "I'll fix the integration issues myself at the end" | Integration "issues" are contract mismatches. Fixing them means redoing agent work. Define the contract up front. |

## Arguments

$ARGUMENTS, the feature description or plan reference

## Process

### Phase 1: Plan the work

Before creating any team, decompose the feature into:

1. **Shared contract**: the interfaces, API shapes, or data formats that multiple agents need to agree on
2. **Agent workstreams**: what each agent is responsible for, scoped to their codebase/domain
3. **Integration tasks**: anything that requires multiple agents' work to be combined

Create a task list capturing all of this. Mark integration tasks as blocked by the workstream tasks they depend on.

### Phase 2: Create the team

```
TeamCreate(team_name="feature-<short-name>", description="<feature description>")
```

Spawn one agent per workstream. For each agent, provide in the prompt:
- **Workspace path and codebase context**: where they work, what stack they're in
- **Package manager and tooling**: how to run tests, lint, build
- **Their specific tasks** from the plan
- **The shared contract**: so they know what interfaces to implement
- **Communication rules:**
  - When their part of the contract is implemented and tested, message the other agents with details
  - When all tasks are done, message the orchestrator
  - If they need to change the agreed contract, message the orchestrator AND all affected agents BEFORE making the change

Use the project's CLAUDE.md and relevant rules to populate stack details for each agent. Choose model tiers based on task complexity: sonnet for implementation, opus for architecture-heavy work.

### Phase 3: Orchestrate

Your role as orchestrator:

1. **Monitor progress**: check TaskList periodically. When agents message you, respond.
2. **Mediate contract changes**: if any agent requests a contract change, evaluate it, update the contract, and notify all affected agents via SendMessage.
3. **Unblock**: if an agent is stuck, help directly or reassign.
4. **Do NOT implement**: your job is coordination, not coding.

### Phase 4: Integration

When all agents report their tasks complete:

1. **Verify each workstream**: run tests/lint for each codebase
2. **Cross-check contract**: read both sides of any shared interface to confirm they match
3. **Integration test**: if applicable, run it. If not, note as a follow-up.

### Phase 5: Shutdown

1. Mark all integration tasks as completed
2. Send shutdown messages to all agents
3. Report results to the user: what was built, what was tested, any follow-ups needed
4. Dispatch code review via `/lens-review` covering all changes
