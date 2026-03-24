# Costea

> 花钱之前，先知道要花多少。

Costea 是一组 AI agent skill，用于追踪、分析和预估多平台的 token 消耗。

[English README](README.md)

## Skills

### `/costea` — 执行前的成本预估

在运行任务**之前**预估 token 成本，确认后才执行。

```
/costea 重构 auth 模块
```

**工作流程：**

1. 从历史会话中构建任务索引（支持 OpenClaw、Claude Code、Codex CLI）
2. 用 LLM 语义匹配相似的历史任务
3. 预估 token 用量、费用和运行时间
4. 展示预估结果，询问：**继续？(Y/N)**
5. 用户确认后才执行

### `/costeamigo` — 历史 Token 消耗报告

生成多维度的历史 token 消耗报告。

```
/costeamigo          # 弹出平台选择菜单
/costeamigo all      # 全平台汇总
/costeamigo claude   # 仅 Claude Code
/costeamigo codex    # 仅 Codex CLI
/costeamigo openclaw # 仅 OpenClaw
```

**报告包含：**

- 总 token 数、总费用、时间范围
- 按平台、模型、Skill、工具分类
- 推理 vs 工具调用占比
- 最贵任务排行
- 可操作的优化建议

## 支持平台

| 平台 | 会话位置 | Token 数据 |
|------|---------|-----------|
| **Claude Code** | `~/.claude/projects/<project>/<session>.jsonl` | 每条 assistant 消息的 usage |
| **Codex CLI** | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | 累积 `token_count` 事件 |
| **OpenClaw** | `~/.openclaw/agents/main/sessions/*.jsonl` | 每条消息的 usage + cost |

## 架构

```
skills/
├── costea/                  # /costea skill
│   ├── SKILL.md             # 预估 + 确认工作流
│   └── scripts/
│       ├── build-index.sh   # 扫描 3 个平台 → ~/.costea/task-index.json
│       ├── estimate-cost.sh # 读取索引，输出历史数据供 LLM 匹配
│       └── analyze-tokens.sh# 单 session 的 3 级 token 分析
└── costeamigo/              # /costeamigo skill
    ├── SKILL.md             # 历史报告工作流
    └── scripts/
        └── report.sh        # 多维聚合报告
```

**数据流：**

```
Session JSONL 文件（3 个平台）
        ↓  build-index.sh（纯 jq，不调 LLM）
~/.costea/task-index.json
        ↓
   ┌────┴────┐
   ↓         ↓
/costea   /costeamigo
(LLM 预估     (LLM 格式化
 未来成本)     历史报告)
```

## 依赖

- **jq** — `brew install jq`
- 至少安装了 Claude Code、Codex CLI 或 OpenClaw 之一，且有历史会话

## 安装

将 skill 目录复制或软链接到你的 agent skills 路径：

```bash
# Claude Code
ln -s /path/to/costea/skills/costea ~/.claude/skills/costea
ln -s /path/to/costea/skills/costeamigo ~/.claude/skills/costeamigo

# OpenClaw
ln -s /path/to/costea/skills/costea ~/.agents/skills/costea
ln -s /path/to/costea/skills/costeamigo ~/.agents/skills/costeamigo
```

## 许可证

[Apache License 2.0](LICENSE)
