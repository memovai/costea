<p align="center">
  <img src="docs/images/banner.svg" alt="Costea — cost prediction for AI agents" width="800" />
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License" /></a>
  <a href="https://www.npmjs.com/package/@costea/costea"><img src="https://img.shields.io/npm/v/@costea/costea.svg?color=red" alt="npm" /></a>
  <a href="https://github.com/memovai/costea"><img src="https://img.shields.io/badge/GitHub-costea-black" alt="GitHub" /></a>
</p>

<p align="center"><b>Know what you spend before you spend it.</b></p>

---

## Quick Start

```bash
npx @costea/costea
```

Or install manually:

```bash
# Clone
git clone https://github.com/memovai/costea.git

# Symlink skills into Claude Code
ln -sf $(pwd)/costea/skills/costea ~/.claude/skills/costea
ln -sf $(pwd)/costea/skills/costeamigo ~/.claude/skills/costeamigo

# For Codex CLI
ln -sf $(pwd)/costea/skills/costea ~/.codex/skills/costea
```

**Requires:** `jq` (`brew install jq`)

---

## Skills

### `/costea` — Cost Prediction Receipt

Estimates the token cost of a task **before** you run it. Shows a terminal receipt with multi-provider comparison, then asks for confirmation.

```
/costea refactor the auth module
```

```
┌──────────────────────────────────────────────────┐
│                                                  │
│                  C O S T E A                     │
│              Agent Cost Receipt                  │
│             2026-04-08 14:32:07                  │
│                                                  │
│╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│
│                                                  │
│  TASK                                            │
│  Refactor the auth module                        │
│                                                  │
│╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│
│                                                  │
│  Input tokens                        12,400      │
│  Output tokens                        5,800      │
│  Tool calls                              14      │
│  Similar tasks matched                    3      │
│  Est. runtime                        ~2 min      │
│                                                  │
│╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│
│                                                  │
│  PROVIDER ESTIMATES                              │
│  Claude Sonnet 4                        $0.38    │
│  GPT-5.4                                $0.54    │
│  Gemini 2.5 Pro                         $0.29    │
│                                                  │
│══════════════════════════════════════════════════│
│                                                  │
│  ESTIMATED TOTAL                        $0.38    │
│                    best price: Gemini 2.5 Pro    │
│                                                  │
│╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│
│                                                  │
│  Confidence                              96%     │
│                                                  │
│╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│
│                                                  │
│            Proceed? [Y/N]                        │
│                                                  │
│          POWERED BY /COSTEA SKILL                │
│        THANK YOU FOR BEING COST-CONSCIOUS        │
│                                                  │
│       ║│║║│║│ ║║│║│║│║ ║║│║║│║│║│               │
│                                                  │
└──────────────────────────────────────────────────┘
```

### `/costeamigo` — Historical Spending Report

Generates a multi-dimensional report of your token consumption across all platforms.

```
/costeamigo all        # Combined report
/costeamigo claude     # Claude Code only
/costeamigo codex      # Codex CLI only
/costeamigo openclaw   # OpenClaw only
```

Reports include: per-platform breakdown, per-model costs, per-skill aggregation, tool usage patterns, reasoning vs tool-invocation split, and top expensive tasks.

---

## How It Works

```
Session JSONL files (3 platforms)
        │
        ├── Claude Code   ~/.claude/projects/{proj}/{uuid}.jsonl
        ├── Codex CLI     ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
        └── OpenClaw      ~/.openclaw/agents/main/sessions/*.jsonl
                │
                ▼
  ┌─────────────────────────────────────┐
  │  parse-claudecode.sh                │
  │  parse-codex.sh        (per file)   │
  │  parse-openclaw.sh                  │
  └─────────────────────────────────────┘
                │
                ▼
  ~/.costea/sessions/{id}/
    session.jsonl       per-turn summary
    llm-calls.jsonl     per-API-call (deduped)
    tools.jsonl         per-tool invocation
    agents.jsonl        subagent events
    summary.json        aggregated stats
                │
                ▼
  ┌─────────────┬──────────────┐
  │             │              │
  /costea     /costeamigo    index.json
  receipt +   historical     global
  Y/N         report         session index
```

### Key Design

- **Parallel tool-call dedup** — Claude Code splits one API response into multiple assistant records for parallel tool calls, sharing the same `message.id`. Only the first is counted for tokens.
- **Cumulative delta** — Codex CLI stores running totals; per-turn usage is computed as `current - previous`.
- **Native cost** — OpenClaw provides per-message USD cost directly; no local calculation needed.
- **Subagent attribution** — Claude Code subagent files in `subagents/agent-*.jsonl` are scanned and attributed back to the parent session.

---

## Supported Platforms

| Platform | Parser | Token Source | Status |
|----------|--------|-------------|--------|
| Claude Code | `parse-claudecode.sh` | `message.usage` per assistant msg | Tested (106 sessions) |
| Codex CLI | `parse-codex.sh` | Cumulative `token_count` events | Tested (80 sessions) |
| OpenClaw | `parse-openclaw.sh` | `message.usage` with cost | Tested (real containers) |

---

## Provider Price Comparison

The receipt shows estimated costs across multiple providers for the same task:

| Provider | Input ($/M) | Output ($/M) |
|----------|------------|-------------|
| Claude Opus 4.6 | $5 | $25 |
| Claude Sonnet 4.6 | $3 | $15 |
| Claude Haiku 4.5 | $1 | $5 |
| GPT-5.4 | $2.50 | $15 |
| GPT-5.2 Codex | $1.07 | $8.50 |
| Gemini 2.5 Pro | $1.25 | $5 |
| Gemini 2.5 Flash | $0.15 | $0.60 |

Prices sourced from `claude-code/src/utils/modelCost.ts` and provider documentation.

---

## Scripts

| Script | Purpose |
|--------|---------|
| `parse-claudecode.sh` | Parse Claude Code session JSONL (dedup + subagents) |
| `parse-codex.sh` | Parse Codex CLI rollout JSONL (cumulative deltas) |
| `parse-openclaw.sh` | Parse OpenClaw session JSONL (native cost) |
| `build-index.sh` | Build task index from all platforms |
| `estimate-cost.sh` | Retrieve historical data for cost prediction |
| `receipt.sh` | Render terminal receipt from JSON |
| `summarize-session.sh` | Generate summary.json from session JSONL |
| `update-index.sh` | Orchestrate full scan + rebuild index |
| `lib/cost.sh` | Shared price table and jq helpers |

---

## Data Directory

All parsed data lives under `~/.costea/` and can be safely deleted and regenerated:

```
~/.costea/
├── sessions/
│   └── {session-uuid}/
│       ├── session.jsonl
│       ├── llm-calls.jsonl
│       ├── tools.jsonl
│       ├── agents.jsonl
│       └── summary.json
├── task-index.json
└── index.json
```

---

## License

[Apache License 2.0](LICENSE)
