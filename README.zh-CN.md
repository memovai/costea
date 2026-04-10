<p align="center">
  <img src="docs/images/banner.svg" alt="Costea — AI Agent 费用预测" width="800" />
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License" /></a>
  <a href="https://www.npmjs.com/package/@costea/costea"><img src="https://img.shields.io/npm/v/%40costea%2Fcostea?color=red" alt="npm skill" /></a>
  <a href="https://www.npmjs.com/package/@costea/web"><img src="https://img.shields.io/npm/v/%40costea%2Fweb?color=red&label=npm%20web" alt="npm web" /></a>
  <a href="https://github.com/memovai/costea"><img src="https://img.shields.io/badge/GitHub-costea-black" alt="GitHub" /></a>
</p>

<p align="center"><b>花钱之前，先知道要花多少。</b></p>

---

## 安装

### 方式 A: npm（推荐）

```bash
# 安装 CLI 技能（/costea + /costeamigo）
npx @costea/costea

# 启动 Web UI 仪表盘
npx @costea/web serve 3000
```

> 如果你的 npm registry 是私有的，请加：`--registry https://registry.npmjs.org`

### 方式 B: Git 克隆

```bash
git clone https://github.com/memovai/costea.git
cd costea

# 链接到 Claude Code
ln -sf $(pwd)/skills/costea ~/.claude/skills/costea
ln -sf $(pwd)/skills/costeamigo ~/.claude/skills/costeamigo

# 链接到 Codex CLI
ln -sf $(pwd)/skills/costea ~/.codex/skills/costea

# 启动 Web UI
cd web && npm install && npm run dev
```

### 依赖

- **jq** — `brew install jq`（所有 shell 脚本需要）
- **Node.js 18+** — 仅 Web UI 需要

### 首次运行 — 构建索引

安装后，从历史 session 构建索引：

```bash
bash ~/.claude/skills/costea/scripts/update-index.sh
```

扫描 `~/.claude/projects/`、`~/.codex/sessions/`、`~/.openclaw/` 构建任务数据库。

---

## 使用

### CLI 技能

安装后新开一个 Claude Code 或 Codex 会话：

```bash
# 执行前预估费用 — 显示账单，Y/N 确认
/costea 重构认证模块

# 历史消耗报告
/costeamigo all        # 所有平台汇总
/costeamigo claude     # 仅 Claude Code
/costeamigo codex      # 仅 Codex CLI
/costeamigo openclaw   # 仅 OpenClaw
```

### Web UI

```bash
# npm 方式
npx @costea/web serve 3000

# 本地开发
cd web && npm run dev
```

打开 http://localhost:3000：

| 页面 | 功能 |
|------|------|
| `/` | 落地页（receipt 卡片、安装命令） |
| `/dashboard` | 所有 session 列表 + 总费用 + 平台筛选 + 排序 |
| `/session/{id}` | Session 详情：模型分布、工具排行、可展开的 turn 列表（含 LLM 调用明细） |
| `/estimate` | 交互式费用预估 — 输入任务描述，实时生成 receipt |
| `/analytics` | 全局分析：费用趋势图、模型/平台分布、日报表 |
| `/accuracy` | 预估准确率：散点图、误差分布、对比统计 |

---

## 技能

### `/costea` — 费用预估账单

执行前预估 Token 费用，终端账单展示多 Provider 对比，Y/N 确认后执行。自动记录预估值，执行后对比实际开销。

### `/costeamigo` — 历史消耗报告

多维度分析：按平台、按模型、按技能、工具使用、推理 vs 工具调用、最贵任务排行。

---

## 工作原理

```
平台 Session JSONL
      ↓  parse-claudecode.sh / parse-codex.sh / parse-openclaw.sh
~/.costea/sessions/{id}/
  session.jsonl · llm-calls.jsonl · tools.jsonl · agents.jsonl
      ↓  summarize-session.sh
summary.json → index.json
      ↓
  ┌───────┬──────────┬────────────┐
  ↓       ↓          ↓            ↓
/costea  /costeamigo  Web UI    estimates.jsonl
账单     报告        仪表盘    预估追踪
+ Y/N                分析      准确率对比
```

### 核心设计

- **并行工具调用去重** — Claude Code 拆分共享 `message.id` 的记录，只取第一条
- **累积增量** — Codex CLI 存运行总计，逐轮 = `当前 - 上轮`
- **原生费用** — OpenClaw 直接提供 USD cost
- **子 Agent 归因** — 递归扫描 `subagents/` 归属到父 session
- **预估追踪** — 每次 `/costea` 预估记录到 `estimates.jsonl`，执行后对比实际值

---

## 支持平台

| 平台 | 解析器 | Token 来源 | 状态 |
|------|--------|-----------|------|
| Claude Code | `parse-claudecode.sh` | `message.usage` | 已测试 |
| Codex CLI | `parse-codex.sh` | 累积 `token_count` | 已测试 |
| OpenClaw | `parse-openclaw.sh` | `message.usage` 含 cost | 已测试 |

---

## npm 包

| 包名 | 版本 | 用途 | 安装 |
|------|------|------|------|
| `@costea/costea` | 1.1.0 | CLI 技能 | `npx @costea/costea` |
| `@costea/web` | 1.0.0 | Web UI | `npx @costea/web serve [端口]` |

---

## 数据目录

`~/.costea/` 下的数据可以安全删除并重新生成：

```
~/.costea/
├── sessions/{uuid}/
│   ├── session.jsonl      轮次汇总
│   ├── llm-calls.jsonl    API 调用（已去重）
│   ├── tools.jsonl        工具调用
│   ├── agents.jsonl       子 Agent 事件
│   └── summary.json       聚合统计
├── task-index.json        任务索引
├── index.json             Session 索引
└── estimates.jsonl        预估记录
```

---

## 许可证

[Apache License 2.0](LICENSE)
