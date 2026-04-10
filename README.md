<p align="center">
  <img src="docs/images/banner.svg" alt="Costea — cost prediction for AI agents" width="800" />
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License" /></a>
  <a href="https://www.npmjs.com/package/@costea/costea"><img src="https://img.shields.io/npm/v/%40costea%2Fcostea?color=red" alt="npm skill" /></a>
  <a href="https://www.npmjs.com/package/@costea/web"><img src="https://img.shields.io/npm/v/%40costea%2Fweb?color=red&label=npm%20web" alt="npm web" /></a>
  <a href="https://github.com/memovai/costea"><img src="https://img.shields.io/badge/GitHub-costea-black" alt="GitHub" /></a>
</p>

<p align="center"><b>Know what you spend before you spend it.</b></p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a>
</p>

---

## Install

### Option A: npm (recommended)

```bash
# Install CLI skills (/costea + /costeamigo)
npx @costea/costea

# Start Web UI dashboard
npx @costea/web serve 3000
```

> If your npm registry is private, add: `--registry https://registry.npmjs.org`

### Option B: Git clone

```bash
git clone https://github.com/memovai/costea.git
cd costea

# Link skills into Claude Code
ln -sf $(pwd)/skills/costea ~/.claude/skills/costea
ln -sf $(pwd)/skills/costeamigo ~/.claude/skills/costeamigo

# Link skills into Codex CLI
ln -sf $(pwd)/skills/costea ~/.codex/skills/costea

# Start Web UI
cd web && npm install && npm run dev
```

### Requirements

- **jq** — `brew install jq` (used by all shell scripts)
- **Node.js 18+** — for Web UI only

### First run — build the index

After installing, build the session index from your history:

```bash
# Via installed skill scripts
bash ~/.claude/skills/costea/scripts/update-index.sh

# Or if cloned
bash skills/costea/scripts/update-index.sh
```

This scans `~/.claude/projects/`, `~/.codex/sessions/`, and `~/.openclaw/` to build the task database.

---

## Usage

### CLI Skills

Open a new Claude Code or Codex session after installing:

```bash
# Estimate cost before running a task — shows receipt, asks Y/N
/costea refactor the auth module

# Historical spending report
/costeamigo all        # All platforms combined
/costeamigo claude     # Claude Code only
/costeamigo codex      # Codex CLI only
/costeamigo openclaw   # OpenClaw only
```

### Web UI

```bash
# Via npm
npx @costea/web serve 3000

# Or locally
cd web && npm run dev
```

Open http://localhost:3000 — pages:

| Page | What it shows |
|------|--------------|
| `/` | Landing page with receipt card, install commands |
| `/dashboard` | All sessions, total cost, platform filter, sort by cost/tokens/date |
| `/session/{id}` | Per-session detail: model breakdown, tools, turns (expandable with LLM call detail) |
| `/estimate` | Interactive cost prediction — type a task, get live receipt |
| `/analytics` | Cost over time, by-model/platform charts, daily breakdown |
| `/accuracy` | Prediction vs actual comparison: scatter plot, error distribution, accuracy stats |

---

## Skills

### `/costea` — Cost Prediction Receipt

Estimates token cost **before** execution. Shows a terminal receipt with multi-provider comparison, then asks for Y/N confirmation. Logs predictions to `~/.costea/estimates.jsonl` and compares with actual usage after execution.

```
┌──────────────────────────────────────────────────┐
│                  C O S T E A                     │
│              Agent Cost Receipt                  │
│╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│
│  TASK                                            │
│  Refactor the auth module                        │
│╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│
│  Input tokens                        12,400      │
│  Output tokens                        5,800      │
│  Tool calls                              14      │
│╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│
│  PROVIDER ESTIMATES                              │
│  Claude Sonnet 4                        $0.38    │
│  GPT-5.4                                $0.54    │
│  Gemini 2.5 Pro                         $0.29    │
│══════════════════════════════════════════════════│
│  ESTIMATED TOTAL                        $0.38    │
│  Confidence                              96%     │
│╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│
│            Proceed? [Y/N]                        │
└──────────────────────────────────────────────────┘
```

### `/costeamigo` — Historical Spending Report

Multi-dimensional analysis: per-platform, per-model, per-skill, tool patterns, reasoning vs tool split, top expensive tasks.

---

## How It Works

```
Session JSONL (3 platforms)
      ↓  parse-claudecode.sh / parse-codex.sh / parse-openclaw.sh
~/.costea/sessions/{id}/
  session.jsonl · llm-calls.jsonl · tools.jsonl · agents.jsonl
      ↓  summarize-session.sh
summary.json → index.json
      ↓
  ┌───────┬──────────┬────────────┐
  ↓       ↓          ↓            ↓
/costea  /costeamigo  Web UI    estimates.jsonl
receipt  report       dashboard  prediction tracking
+ Y/N                analytics  accuracy comparison
```

### Key Design

- **Parallel tool-call dedup** — Claude Code splits one API response into multiple records sharing `message.id`. Only the first is counted.
- **Cumulative delta** — Codex CLI stores running totals; per-turn usage = `current - previous`.
- **Native cost** — OpenClaw provides per-message USD cost directly.
- **Subagent attribution** — Claude Code `subagents/agent-*.jsonl` scanned and attributed to parent session.
- **Prediction tracking** — Each `/costea` estimate is logged; actual usage is compared after execution.

---

## Supported Platforms

| Platform | Parser | Token Source | Status |
|----------|--------|-------------|--------|
| Claude Code | `parse-claudecode.sh` | `message.usage` per assistant msg | Tested |
| Codex CLI | `parse-codex.sh` | Cumulative `token_count` events | Tested |
| OpenClaw | `parse-openclaw.sh` | `message.usage` with cost | Tested |

---

## npm Packages

| Package | Version | Purpose | Install |
|---------|---------|---------|---------|
| `@costea/costea` | 1.1.0 | CLI skills (SKILL.md + scripts) | `npx @costea/costea` |
| `@costea/web` | 1.0.0 | Web UI (standalone Next.js) | `npx @costea/web serve [port]` |

---

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `parse-claudecode.sh` | Parse Claude Code JSONL (dedup + subagents) |
| `parse-codex.sh` | Parse Codex CLI rollout JSONL (cumulative deltas) |
| `parse-openclaw.sh` | Parse OpenClaw JSONL (native cost) |
| `build-index.sh` | Build task index from all platforms |
| `estimate-cost.sh` | Historical data + aggregate stats for prediction |
| `receipt.sh` | Render terminal receipt from JSON |
| `log-estimate.sh` | Log predictions + actuals for accuracy tracking |
| `summarize-session.sh` | Generate summary.json from session JSONL |
| `update-index.sh` | Full scan + rebuild index |
| `test-all.sh` | Run regression test suite (9 tests) |
| `lib/cost.sh` | Shared price table and jq helpers |

---

## Data Directory

All data under `~/.costea/` — safe to delete and regenerate:

```
~/.costea/
├── sessions/{uuid}/
│   ├── session.jsonl      per-turn summaries
│   ├── llm-calls.jsonl    per-API-call records (deduped)
│   ├── tools.jsonl        per-tool invocation
│   ├── agents.jsonl       subagent lifecycle events
│   └── summary.json       aggregated session stats
├── task-index.json        task index (build-index.sh)
├── index.json             session index (update-index.sh)
└── estimates.jsonl        prediction log (log-estimate.sh)
```

---

## License

[Apache License 2.0](LICENSE)
