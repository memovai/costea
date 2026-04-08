---
name: costeamigo
description: |
  Historical token consumption report across OpenClaw, Claude Code, and Codex CLI.
  Rebuilds task index from all session logs and produces a structured summary:
  per-source breakdown, per-skill aggregation, per-model cost, tool usage
  patterns, and reasoning vs tool-invocation analysis.
  Use when: 'token report', 'usage summary', 'how much have I spent',
  'token history', 'cost report', 'show usage'.
argument-hint: "[all | openclaw | claude | codex]"
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# Costeamigo — Historical Token Consumption Report

You generate a comprehensive, well-organized report of historical token consumption.

## Step 1: Choose platform

Check `$ARGUMENTS`:

- If `$ARGUMENTS` is `all` → report all platforms combined
- If `$ARGUMENTS` is `openclaw` → report OpenClaw only
- If `$ARGUMENTS` is `claude` → report Claude Code only
- If `$ARGUMENTS` is `codex` → report Codex CLI only
- If `$ARGUMENTS` is empty or unrecognized → ask the user to choose:

Use AskUserQuestion with this format:

```
Choose a platform to analyze:

A) all     — Combined report (OpenClaw + Claude Code + Codex)
B) openclaw — OpenClaw sessions
C) claude   — Claude Code sessions
D) codex    — Codex CLI sessions

Enter A/B/C/D or platform name:
```

Map the user's response:
- A / all → `all`
- B / openclaw → `openclaw`
- C / claude → `claude`
- D / codex → `codex`

## Step 2: Generate report data

Run the report script with the chosen source filter:

```bash
bash "SCRIPT_DIR/scripts/report.sh" --source <chosen_platform>
```

(Replace SCRIPT_DIR with the directory where this SKILL.md file lives.)

Valid `--source` values: `all`, `openclaw`, `claude-code`, `codex`

Note: user says "claude" but the script expects "claude-code". Map accordingly:
- `claude` → `--source claude-code`
- `openclaw` → `--source openclaw`
- `codex` → `--source codex`
- `all` → `--source all`

The script outputs JSON with these sections:
- `overview`: total tasks, tokens, cost, time range, sources
- `by_source`: breakdown per platform with models used
- `by_skill`: aggregation per skill
- `by_model`: aggregation per model
- `by_tool`: tool usage ranking
- `reasoning_vs_tools`: reasoning vs tool-invocation split
- `top_tasks_by_tokens`: top 10 most token-heavy tasks
- `all_tasks`: every task with full metrics

## Step 3: Analyze and present

Using the JSON data, produce a clear, layered report:

### Layer 1: Overview
- Total tasks, total tokens, total cost
- Time range covered
- Platform(s) analyzed

### Layer 1.5: By Source Platform (only in `all` mode)
- Show each platform with: task count, tokens, models used
- Estimate cost for platforms without cost data using model pricing:
  - Claude Opus 4.6: $15/MTok input, $75/MTok output, $1.50/MTok cache read, $18.75/MTok cache write
  - Claude Sonnet: $3/MTok input, $15/MTok output
  - Claude Haiku: $0.80/MTok input, $4/MTok output
  - GPT-5.2-codex: $1.75/MTok input, $14/MTok output, $0.175/MTok cache read
  - GPT-5.4: $2.50/MTok input, $15/MTok output

### Layer 2: By Category

**By Skill:**
- List each skill with: invocation count, total tokens, total cost, avg cost
- "(conversation)" = non-skill direct chat tasks

**By Model:**
- List each model with: task count, tokens (input/output/cache split), cost

**By Tool:**
- Rank tools by total call count

### Layer 3: Efficiency Analysis

**Reasoning vs Tool Invocation:**
- Show the percentage split
- high reasoning % = mostly thinking; high tool % = lots of file I/O

**Top Expensive Tasks:**
- List top 5 most costly tasks
- Show: task prompt, tokens, cost, tools used

### Layer 4: Insights (LLM analysis)

2-3 brief, actionable insights based on the data.

## Formatting

- Use tables for structured data
- Use bold for key numbers
- Keep it scannable
- Use Chinese if the user communicates in Chinese, English otherwise
