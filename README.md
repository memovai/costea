# Costea

> Know what you spend before you spend it.

Costea is a set of AI agent skills that track, analyze, and estimate token consumption across multiple coding AI platforms.

[中文版 README](README.zh-CN.md)

## Skills

### `/costea` — Cost Estimation Before Execution

Estimates the token cost of a task **before** running it, then asks for your confirmation.

```
/costea refactor the auth module
```

**How it works:**

1. Builds a task index from your session history (OpenClaw, Claude Code, Codex CLI)
2. Uses LLM reasoning to find similar past tasks
3. Estimates token usage, cost, and runtime
4. Presents the estimate and asks: **Proceed? (Y/N)**
5. Only executes after you confirm

### `/costeamigo` — Historical Token Consumption Report

Generates a multi-dimensional report of your historical token spending.

```
/costeamigo          # prompts you to pick a platform
/costeamigo all      # all platforms combined
/costeamigo claude   # Claude Code only
/costeamigo codex    # Codex CLI only
/costeamigo openclaw # OpenClaw only
```

**Report includes:**

- Total tokens, cost, and time range
- Breakdown by platform, model, skill, and tool
- Reasoning vs tool-invocation split
- Top most expensive tasks
- Actionable insights

## Supported Platforms

| Platform | Session Location | Token Data |
|----------|-----------------|------------|
| **Claude Code** | `~/.claude/projects/<project>/<session>.jsonl` | Per-message usage in assistant entries |
| **Codex CLI** | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | Cumulative `token_count` events |
| **OpenClaw** | `~/.openclaw/agents/main/sessions/*.jsonl` | Per-message usage with cost breakdown |

## Architecture

```
skills/
├── costea/                  # /costea skill
│   ├── SKILL.md             # Skill definition (estimation + confirmation workflow)
│   └── scripts/
│       ├── build-index.sh   # Scans all 3 platforms → ~/.costea/task-index.json
│       ├── estimate-cost.sh # Reads index, outputs history JSON for LLM matching
│       └── analyze-tokens.sh# Per-session 3-level token analysis
└── costeamigo/              # /costeamigo skill
    ├── SKILL.md             # Skill definition (historical report workflow)
    └── scripts/
        └── report.sh        # Aggregates index into multi-dimensional JSON report
```

**Data flow:**

```
Session JSONL files (3 platforms)
        ↓  build-index.sh (pure jq, no LLM)
~/.costea/task-index.json
        ↓
   ┌────┴────┐
   ↓         ↓
/costea   /costeamigo
(LLM estimates    (LLM formats
 future cost)      historical report)
```

## Requirements

- **jq** — `brew install jq`
- At least one of: Claude Code, Codex CLI, or OpenClaw with session history

## Installation

Copy or symlink the skill directories to your agent's skills path:

```bash
# For Claude Code
ln -s /path/to/costea/skills/costea ~/.claude/skills/costea
ln -s /path/to/costea/skills/costeamigo ~/.claude/skills/costeamigo

# For OpenClaw
ln -s /path/to/costea/skills/costea ~/.agents/skills/costea
ln -s /path/to/costea/skills/costeamigo ~/.agents/skills/costeamigo
```

## License

[Apache License 2.0](LICENSE)
