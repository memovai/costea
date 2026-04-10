<p align="center">
  <img src="docs/images/banner.svg" alt="Costea — AIエージェントのコスト予測" width="800" />
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License" /></a>
  <a href="https://www.npmjs.com/package/@costea/costea"><img src="https://img.shields.io/npm/v/%40costea%2Fcostea?color=red" alt="npm skill" /></a>
  <a href="https://www.npmjs.com/package/@costea/web"><img src="https://img.shields.io/npm/v/%40costea%2Fweb?color=red&label=npm%20web" alt="npm web" /></a>
  <a href="https://github.com/memovai/costea"><img src="https://img.shields.io/badge/GitHub-costea-black" alt="GitHub" /></a>
</p>

<p align="center"><b>使う前に、コストを知る。</b></p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a>
</p>

---

## インストール

### 方法A: npm（推奨）

```bash
# CLIスキルをインストール (/costea + /costeamigo)
npx @costea/costea

# Web UIダッシュボードを起動
npx @costea/web serve 3000
```

> npmレジストリがプライベートの場合は、次を追加してください: `--registry https://registry.npmjs.org`

### 方法B: Gitクローン

```bash
git clone https://github.com/memovai/costea.git
cd costea

# スキルをClaude Codeにリンク
ln -sf $(pwd)/skills/costea ~/.claude/skills/costea
ln -sf $(pwd)/skills/costeamigo ~/.claude/skills/costeamigo

# スキルをCodex CLIにリンク
ln -sf $(pwd)/skills/costea ~/.codex/skills/costea

# Web UIを起動
cd web && npm install && npm run dev
```

### 必要環境

- **jq** — `brew install jq`（すべてのシェルスクリプトで使用）
- **Node.js 18+** — Web UIのみに必要

### 初回実行 — インデックスの構築

インストール後、履歴からセッションインデックスを構築します:

```bash
# インストール済みスキルスクリプト経由
bash ~/.claude/skills/costea/scripts/update-index.sh

# クローンした場合
bash skills/costea/scripts/update-index.sh
```

`~/.claude/projects/`、`~/.codex/sessions/`、`~/.openclaw/` をスキャンしてタスクデータベースを構築します。

---

## 使い方

### CLIスキル

インストール後、新しいClaude CodeまたはCodexセッションを開きます:

```bash
# タスク実行前にコストを見積もり — レシートを表示し、Y/Nで確認
/costea refactor the auth module

# 過去の支出レポート
/costeamigo all        # 全プラットフォーム合計
/costeamigo claude     # Claude Codeのみ
/costeamigo codex      # Codex CLIのみ
/costeamigo openclaw   # OpenClawのみ
```

### Web UI

```bash
# npm経由
npx @costea/web serve 3000

# ローカル実行
cd web && npm run dev
```

http://localhost:3000 を開きます — ページ一覧:

| ページ | 表示内容 |
|------|--------------|
| `/` | レシートカード付きランディングページ、インストールコマンド |
| `/dashboard` | 全セッション、総コスト、プラットフォームフィルター、コスト/トークン/日付でソート |
| `/session/{id}` | セッション詳細: モデル別内訳、ツール、ターン（LLMコール詳細の展開可能） |
| `/estimate` | インタラクティブなコスト予測 — タスクを入力するとリアルタイムでレシートを表示 |
| `/analytics` | コスト推移、モデル/プラットフォーム別チャート、日別内訳 |
| `/accuracy` | 予測と実績の比較: 散布図、誤差分布、精度統計 |

---

## スキル

### `/costea` — コスト予測レシート

実行**前に**トークンコストを見積もります。ターミナルにマルチプロバイダー比較付きレシートを表示し、Y/Nで確認を求めます。予測は `~/.costea/estimates.jsonl` に記録され、実行後に実際の使用量と比較されます。

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

### `/costeamigo` — 過去の支出レポート

多次元分析: プラットフォーム別、モデル別、スキル別、ツール使用パターン、推論とツールの比率、高コストタスクのランキング。

---

## 仕組み

```
セッションJSONL（3プラットフォーム）
      ↓  parse-claudecode.sh / parse-codex.sh / parse-openclaw.sh
~/.costea/sessions/{id}/
  session.jsonl · llm-calls.jsonl · tools.jsonl · agents.jsonl
      ↓  summarize-session.sh
summary.json → index.json
      ↓
  ┌───────┬──────────┬────────────┐
  ↓       ↓          ↓            ↓
/costea  /costeamigo  Web UI    estimates.jsonl
レシート  レポート     ダッシュボード  予測記録
+ Y/N                分析       精度比較
```

### 設計のポイント

- **並列ツールコールの重複排除** — Claude Codeは1つのAPIレスポンスを `message.id` を共有する複数レコードに分割します。最初のレコードのみカウントされます。
- **累積デルタ** — Codex CLIは累計値を保存します。ターンごとの使用量 = `現在値 - 前回値`。
- **ネイティブコスト** — OpenClawはメッセージごとのUSDコストを直接提供します。
- **サブエージェント帰属** — Claude Codeの `subagents/agent-*.jsonl` をスキャンし、親セッションに紐付けます。
- **予測追跡** — `/costea` の見積もりは毎回記録され、実行後に実際の使用量と比較されます。

---

## 対応プラットフォーム

| プラットフォーム | パーサー | トークンソース | ステータス |
|----------|--------|-------------|--------|
| Claude Code | `parse-claudecode.sh` | アシスタントメッセージごとの `message.usage` | テスト済み |
| Codex CLI | `parse-codex.sh` | 累積 `token_count` イベント | テスト済み |
| OpenClaw | `parse-openclaw.sh` | コスト付き `message.usage` | テスト済み |

---

## npmパッケージ

| パッケージ | バージョン | 用途 | インストール |
|---------|---------|---------|---------|
| `@costea/costea` | 1.1.0 | CLIスキル（SKILL.md + スクリプト） | `npx @costea/costea` |
| `@costea/web` | 1.0.0 | Web UI（スタンドアロンNext.js） | `npx @costea/web serve [port]` |

---

## スクリプトリファレンス

| スクリプト | 用途 |
|--------|---------|
| `parse-claudecode.sh` | Claude Code JSONLの解析（重複排除 + サブエージェント） |
| `parse-codex.sh` | Codex CLI rollout JSONLの解析（累積デルタ） |
| `parse-openclaw.sh` | OpenClaw JSONLの解析（ネイティブコスト） |
| `build-index.sh` | 全プラットフォームからタスクインデックスを構築 |
| `estimate-cost.sh` | 履歴データ + 予測用の集計統計 |
| `receipt.sh` | JSONからターミナルレシートを描画 |
| `log-estimate.sh` | 精度追跡のための予測と実績を記録 |
| `summarize-session.sh` | セッションJSONLからsummary.jsonを生成 |
| `update-index.sh` | フルスキャン + インデックス再構築 |
| `test-all.sh` | 回帰テストスイートを実行（9テスト） |
| `lib/cost.sh` | 共有価格テーブルとjqヘルパー |

---

## データディレクトリ

すべてのデータは `~/.costea/` 配下にあります — 削除して再生成しても安全です:

```
~/.costea/
├── sessions/{uuid}/
│   ├── session.jsonl      ターンごとのサマリー
│   ├── llm-calls.jsonl    APIコールごとのレコード（重複排除済み）
│   ├── tools.jsonl        ツール呼び出しごとのレコード
│   ├── agents.jsonl       サブエージェントのライフサイクルイベント
│   └── summary.json       セッションの集計統計
├── task-index.json        タスクインデックス（build-index.sh）
├── index.json             セッションインデックス（update-index.sh）
└── estimates.jsonl        予測ログ（log-estimate.sh）
```

---

## ライセンス

[Apache License 2.0](LICENSE)
