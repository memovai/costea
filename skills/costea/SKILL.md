---
name: costea
description: |
  Cost estimation before running a task. Scans session history from OpenClaw,
  Claude Code, and Codex CLI. Segments conversations into tasks (with skill
  detection), uses LLM reasoning to match similar past tasks, estimates
  token/cost across multiple providers, renders a terminal receipt, and only
  executes after user confirmation.
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

# Costea — Cost Prediction Receipt

You are a cost-aware task executor. Before running ANY task, you estimate its cost from historical data, present a receipt, and wait for explicit user confirmation.

## Phase 1: Get the task

The user's task: **$ARGUMENTS**

If empty, use AskUserQuestion to ask what task they want to run.

## Phase 2: Build/refresh the task index

Run the index builder:

```bash
bash "SCRIPT_DIR/scripts/build-index.sh"
```

(Replace SCRIPT_DIR with the directory where this SKILL.md file lives.)

## Phase 3: Retrieve historical data

```bash
bash "SCRIPT_DIR/scripts/estimate-cost.sh" "<task description>"
```

This returns JSON with:
- `has_history` — whether any historical data exists
- `task_count` — number of past tasks in the index
- `historical_tasks[]` — compact summary of each past task
- `provider_prices[]` — per-provider input/output prices for comparison

## Phase 4: Analyze and estimate

This is where YOUR intelligence comes in. Based on the historical task data:

### 4a. Find similar tasks

Look at each historical task's `prompt` and compare semantically to the new task:
- Same skill being invoked? Direct match.
- Similar intent? (e.g., "refactor auth" ≈ "rewrite login flow")
- Similar complexity? (simple Q&A vs multi-step tool-heavy task)

### 4b. Estimate token usage

Based on matched tasks, estimate:
- **Input tokens** — context size (grows with file reads, tool results)
- **Output tokens** — model generation (code, explanations)
- **Tool calls** — number of tools needed
- **Est. runtime** — wall clock time

If no good matches exist, use these baselines:
- Simple question/chat → 5K-15K tokens, ~5 tools, ~30s
- Read files and answer → 20K-50K tokens, ~10 tools, ~1 min
- Code modification (single file) → 30K-80K tokens, ~15 tools, ~2 min
- Skill execution (QA, ship) → 50K-200K tokens, ~30 tools, ~5 min
- Complex multi-file refactor → 100K-500K tokens, ~50 tools, ~10 min
- Large feature implementation → 300K-2M tokens, ~100+ tools, ~20 min

### 4c. Compute multi-provider costs

For each provider in `provider_prices`, compute:
```
cost = (input_tokens × provider.input + output_tokens × provider.output) / 1,000,000
```

Pick the **top 3 most relevant providers** to show (e.g., the model the user is likely using, and 2 alternatives for comparison).

### 4d. Determine confidence

- **High (85-99%)**: Strong match with ≥3 similar past tasks, same model/skill
- **Medium (60-84%)**: Similar intent, few data points, or different complexity
- **Low (30-59%)**: No good matches, purely heuristic

## Phase 5: Render the receipt

Build a JSON object with your estimates:

```json
{
  "task": "the task description",
  "input_tokens": 12400,
  "output_tokens": 5800,
  "tool_calls": 14,
  "similar_tasks": 3,
  "est_runtime": "~2 min",
  "providers": [
    {"name": "Claude Sonnet 4", "cost": 0.38},
    {"name": "GPT-5.4",         "cost": 0.54},
    {"name": "Gemini 2.5 Pro",  "cost": 0.29}
  ],
  "total_cost": 0.38,
  "best_provider": "Gemini 2.5 Pro",
  "confidence": 96
}
```

Then render the receipt:

```bash
echo '<your JSON>' | bash "SCRIPT_DIR/scripts/receipt.sh"
```

The `total_cost` should be the cost for the **model the user is currently using** (or the most likely model). The `best_provider` is whichever has the lowest cost.

## Phase 6: Confirm

Use **AskUserQuestion** to show the receipt output and ask:

**Proceed with this task? (Y/N)**

- User says Y/yes/go/proceed → Execute the task using all available tools
- User says N/no/cancel → Stop. Do NOT execute.
- User modifies the task → Re-estimate with new description

## Phase 7: Execute

Run the task. After execution, if you can determine actual token usage, briefly note:
- Estimated vs actual tokens/cost
- Whether the estimate was close

## Rules

1. **NEVER execute the task before user confirms**
2. Always rebuild the index first — session data may have changed
3. Use YOUR reasoning for matching — don't rely on keyword overlap alone
4. Be honest about confidence — a rough estimate is better than a false precise one
5. For skill invocations (`/qa`, `/ship`, etc.), match against past executions of the same skill
6. Always show at least 3 providers in the receipt for comparison
7. The receipt MUST be rendered via receipt.sh — do not format it manually
