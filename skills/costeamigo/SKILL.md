---
name: costeamigo
description: |
  Historical token consumption report across OpenClaw, Claude Code, and Codex CLI.
  Rebuilds task index from all session logs and produces a structured summary:
  per-source breakdown, per-skill aggregation, per-model cost, tool usage
  patterns, and reasoning vs tool-invocation analysis.
  Use when: 'token report', 'usage summary', 'how much have I spent',
  'token history', 'cost report', 'show usage'.
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# Costeamigo — Historical Token Consumption Report

You generate a comprehensive, well-organized report of historical token consumption across all AI coding tools (OpenClaw, Claude Code, Codex CLI).

## Step 1: Generate report data

Run the report script to rebuild the task index and produce aggregated data:

```bash
bash "SCRIPT_DIR/scripts/report.sh"
```

(Replace SCRIPT_DIR with the directory where this SKILL.md file lives.)

This outputs JSON with these sections:
- `overview`: total tasks, tokens, cost, time range, sources (openclaw/claude-code/codex)
- `by_source`: breakdown per platform (OpenClaw, Claude Code, Codex) with models used
- `by_skill`: aggregation per skill (skill tasks grouped by name, non-skill as "(conversation)")
- `by_model`: aggregation per model (tokens, cost per model)
- `by_tool`: tool usage ranking (total calls, how many tasks used each tool)
- `reasoning_vs_tools`: reasoning tokens vs tool-invocation tokens with percentage
- `top_tasks_by_tokens`: top 10 most token-heavy tasks
- `all_tasks`: every task with full metrics

## Step 2: Analyze and present

Using the JSON data, produce a clear, layered report in this structure:

### Layer 1: Overview
- Total tasks, total tokens, total cost
- Time range covered
- Sessions scanned

### Layer 1.5: By Source Platform
- Show each platform (OpenClaw / Claude Code / Codex) with: task count, tokens, models used
- Note: Claude Code and Codex don't store per-message cost — estimate cost using model pricing:
  - Claude Opus 4.6: $15/MTok input, $75/MTok output, $1.50/MTok cache read, $18.75/MTok cache write
  - Claude Sonnet: $3/MTok input, $15/MTok output
  - Claude Haiku: $0.80/MTok input, $4/MTok output
  - GPT-5.2-codex: $1.75/MTok input, $14/MTok output, $0.175/MTok cache read
  - GPT-5.4: $2.50/MTok input, $15/MTok output

### Layer 2: By Category
Present these breakdowns, skipping any that are empty:

**By Skill:**
- List each skill with: invocation count, total tokens, total cost, avg cost per invocation
- "(conversation)" = non-skill direct chat tasks
- Sort by cost descending

**By Model:**
- List each model with: task count, tokens (input/output/cache split), cost
- Note which model is most cost-efficient

**By Tool:**
- Rank tools by total call count
- Note which tasks are tool-heavy vs reasoning-heavy

### Layer 3: Efficiency Analysis

**Reasoning vs Tool Invocation:**
- Show the percentage split
- Explain what it means: high reasoning % = mostly thinking; high tool % = lots of file I/O

**Top Expensive Tasks:**
- List top 5 (or fewer) most costly tasks
- Show: task prompt, tokens, cost, tools used, reasoning %
- Flag any unusually expensive tasks

### Layer 4: Insights (LLM analysis)

Based on the data, provide 2-3 brief insights. Examples:
- "Most of your cost comes from skill X — consider if all invocations were necessary"
- "Tool read accounts for 80% of tool calls — caching could reduce costs"
- "Your avg task costs $0.03 — at current rate, monthly cost would be ~$X"

## Formatting

- Use tables for structured data
- Use bold for key numbers
- Keep it scannable — bullet points over paragraphs
- Round costs to 4 decimal places, tokens to whole numbers
- Use Chinese if the user communicates in Chinese, English otherwise
