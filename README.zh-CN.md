<p align="center">
  <img src="docs/images/banner.svg" alt="Costea — AI Agent 费用预测" width="800" />
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License" /></a>
  <a href="https://www.npmjs.com/package/@costea/costea"><img src="https://img.shields.io/npm/v/@costea/costea.svg?color=red" alt="npm" /></a>
  <a href="https://github.com/memovai/costea"><img src="https://img.shields.io/badge/GitHub-costea-black" alt="GitHub" /></a>
</p>

<p align="center"><b>花钱之前，先知道要花多少。</b></p>

---

## 快速开始

```bash
npx @costea/costea
```

或手动安装：

```bash
# 克隆
git clone https://github.com/memovai/costea.git

# 符号链接到 Claude Code
ln -sf $(pwd)/costea/skills/costea ~/.claude/skills/costea
ln -sf $(pwd)/costea/skills/costeamigo ~/.claude/skills/costeamigo

# Codex CLI
ln -sf $(pwd)/costea/skills/costea ~/.codex/skills/costea
```

**依赖：** `jq`（`brew install jq`）

---

## 技能

### `/costea` — 费用预估账单

在执行任务**之前**预估 Token 费用，以终端账单形式展示多 Provider 价格对比，确认后才执行。

```
/costea 重构认证模块
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

### `/costeamigo` — 历史消耗报告

跨平台的多维度 Token 消耗分析报告。

```
/costeamigo all        # 所有平台汇总
/costeamigo claude     # 仅 Claude Code
/costeamigo codex      # 仅 Codex CLI
/costeamigo openclaw   # 仅 OpenClaw
```

报告包含：按平台分组、按模型计费、按技能聚合、工具使用频次、推理 vs 工具调用占比、最贵任务排行。

---

## 工作原理

```
平台 Session JSONL 文件
        │
        ├── Claude Code   ~/.claude/projects/{proj}/{uuid}.jsonl
        ├── Codex CLI     ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
        └── OpenClaw      ~/.openclaw/agents/main/sessions/*.jsonl
                │
                ▼
  ┌─────────────────────────────────────┐
  │  parse-claudecode.sh                │
  │  parse-codex.sh        (逐文件)     │
  │  parse-openclaw.sh                  │
  └─────────────────────────────────────┘
                │
                ▼
  ~/.costea/sessions/{id}/
    session.jsonl       每轮对话汇总
    llm-calls.jsonl     每次 API 调用（已去重）
    tools.jsonl         每次工具调用
    agents.jsonl        子 Agent 事件
    summary.json        聚合统计
                │
                ▼
  ┌─────────────┬──────────────┐
  │             │              │
  /costea     /costeamigo    index.json
  账单 +      历史报告       全局索引
  Y/N 确认
```

### 核心设计

- **并行工具调用去重** — Claude Code 将一次 API 响应拆成多条 assistant 记录（共享 `message.id`），只计第一条的 Token
- **累积增量** — Codex CLI 存储运行总计，逐轮用量 = `当前累积 - 上轮累积`
- **原生费用** — OpenClaw 直接提供每条消息的 USD 费用，无需本地计算
- **子 Agent 归因** — Claude Code 的 `subagents/agent-*.jsonl` 被递归扫描并归属到父 Session

---

## 支持平台

| 平台 | 解析器 | Token 来源 | 状态 |
|------|--------|-----------|------|
| Claude Code | `parse-claudecode.sh` | 每条 assistant 消息的 `message.usage` | 已测试（106 sessions）|
| Codex CLI | `parse-codex.sh` | 累积 `token_count` 事件 | 已测试（80 sessions）|
| OpenClaw | `parse-openclaw.sh` | `message.usage` 含费用 | 已测试（真实容器）|

---

## Provider 价格对比

账单展示同一任务在不同 Provider 下的预估费用：

| Provider | 输入 ($/M) | 输出 ($/M) |
|----------|-----------|-----------|
| Claude Opus 4.6 | $5 | $25 |
| Claude Sonnet 4.6 | $3 | $15 |
| Claude Haiku 4.5 | $1 | $5 |
| GPT-5.4 | $2.50 | $15 |
| GPT-5.2 Codex | $1.07 | $8.50 |
| Gemini 2.5 Pro | $1.25 | $5 |
| Gemini 2.5 Flash | $0.15 | $0.60 |

---

## 脚本一览

| 脚本 | 用途 |
|------|------|
| `parse-claudecode.sh` | 解析 Claude Code JSONL（去重 + 子 Agent）|
| `parse-codex.sh` | 解析 Codex CLI rollout JSONL（累积增量）|
| `parse-openclaw.sh` | 解析 OpenClaw JSONL（原生费用）|
| `build-index.sh` | 从所有平台构建任务索引 |
| `estimate-cost.sh` | 检索历史数据供费用预测 |
| `receipt.sh` | 从 JSON 渲染终端账单 |
| `summarize-session.sh` | 从 JSONL 生成 summary.json |
| `update-index.sh` | 全量扫描 + 重建索引 |
| `lib/cost.sh` | 共享价格表和 jq 辅助函数 |

---

## 数据目录

所有解析数据在 `~/.costea/` 下，可随时删除并重新生成：

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

## 许可证

[Apache License 2.0](LICENSE)
