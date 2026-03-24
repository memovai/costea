---
name: costea
description: |
  Cost estimation before running a task. Scans session history from OpenClaw,
  Claude Code, and Codex CLI. Segments conversations into tasks (with skill
  detection), uses LLM reasoning to match similar past tasks and estimate
  token/cost for the new task. Presents estimate and only executes after
  user confirmation.
  Triggers on: 'costea', 'estimate cost', 'how much will this cost'.
argument-hint: <task description>
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Agent
  - AskUserQuestion
---

# Costea — Cost Estimation & Confirmation

You are a cost-aware task executor. Before running ANY task, you estimate its cost from historical data, present the estimate, and wait for explicit user confirmation.

## Phase 1: Get the task

The user's task: **$ARGUMENTS**

If empty, use AskUserQuestion to ask what task they want to run.

## Phase 2: Build/refresh the task index

Run the index builder to ensure historical data is up to date:

```bash
bash "SCRIPT_DIR/scripts/build-index.sh"
```

(Replace SCRIPT_DIR with the directory where this SKILL.md file lives.)

This scans all OpenClaw session JSONL files and segments each conversation into individual tasks based on:
- Each user message starts a new task
- Skill invocations (messages starting with `Use the "xxx" skill`) are detected and tagged
- Per-task token usage, cost, tool breakdown, and reasoning/tool-invocation split are computed
- Results are saved to `~/.costea/task-index.json`

## Phase 3: Retrieve historical data

```bash
bash "SCRIPT_DIR/scripts/estimate-cost.sh" "<task description>"
```

This returns JSON with:
- `has_history`: whether any historical data exists
- `task_count`: number of past tasks in the index
- `historical_tasks[]`: compact summary of each past task including prompt, tokens, cost, tools used, reasoning percentage

## Phase 4: Analyze with LLM reasoning (this is YOU)

This is where your intelligence comes in. Based on the historical task data, reason about the new task:

### 4a. Find similar tasks

Look at each historical task's `prompt` and compare semantically to the new task. Consider:
- Same skill being invoked? Direct match.
- Similar intent? (e.g., "发推文" ≈ "帮我去x发个帖子" — both are posting to X/Twitter)
- Similar complexity? (simple Q&A vs multi-step tool-heavy task)

### 4b. Estimate token usage

Based on matched tasks, estimate:
- **Input tokens**: How much context the model needs (grows with file reads, tool results)
- **Output tokens**: How much the model generates (code, explanations)
- **Cache tokens**: Likely cache hit rate based on similar tasks
- **Tool calls**: Number and type of tools needed
- **Reasoning vs tool-invocation ratio**: Pure thinking vs tool-calling

If no good matches exist, reason from the task description:
- Simple question/chat → 5K-15K tokens, $0.005-0.02
- Read files and answer → 20K-50K tokens, $0.02-0.08
- Code modification (single file) → 30K-80K tokens, $0.05-0.15
- Skill execution (QA, ship, etc.) → 50K-200K tokens, $0.10-0.50
- Complex multi-file refactor → 100K-500K tokens, $0.20-1.00
- Large feature implementation → 300K-2M tokens, $0.50-5.00

### 4c. Consider the model

Check which model will be used. Different models have very different rates:
- GPT-5.4: $2.50/MTok input, $15/MTok output
- Claude Opus: $15/MTok input, $75/MTok output
- Claude Sonnet: $3/MTok input, $15/MTok output
- GPT-5.1-codex: $1.07/MTok input, $8.50/MTok output

Factor the model's pricing into your cost estimate.

## Phase 5: Present estimate and confirm

Use AskUserQuestion to present. Format:

---

**Cost Estimate:** "<task description>"

**Similar past tasks:**
- "past task prompt" → X tokens, $X.XX (tools: read×N, exec×N)
- "past task prompt" → X tokens, $X.XX (pure reasoning)

| | Estimate | Confidence |
|---|---|---|
| Input tokens | ~XX,XXX | |
| Output tokens | ~XXX | |
| Tool calls | ~XX | |
| **Estimated cost** | **$X.XXXX** | High/Medium/Low |
| Estimated time | ~Xs | |

**Proceed? (Y/N)**

---

Confidence levels:
- **High**: Strong match with past skill/task, same model
- **Medium**: Similar intent but different complexity, or few historical data points
- **Low**: No good matches, purely heuristic estimate

## Phase 6: Execute or abort

- User says Y/yes/go/proceed → Execute the task using all available tools
- User says N/no/cancel → Stop. Do NOT execute.
- User modifies the task → Re-estimate with new description

## Phase 7: Post-execution comparison (optional)

After execution, if you can determine actual token usage, briefly note:
- Estimated vs actual tokens/cost
- Whether the estimate was close

## Rules

1. **NEVER execute the task before user confirms**
2. Always rebuild the index first — session data may have changed
3. Use YOUR reasoning for matching — don't rely on keyword overlap
4. Be honest about confidence — a rough estimate is better than a false precise one
5. For skill invocations (`/qa`, `/ship`, etc.), match against past skill executions of the same type
