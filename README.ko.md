<p align="center">
  <img src="docs/images/banner.svg" alt="Costea — AI 에이전트 비용 예측" width="800" />
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License" /></a>
  <a href="https://www.npmjs.com/package/@costea/costea"><img src="https://img.shields.io/npm/v/%40costea%2Fcostea?color=red" alt="npm skill" /></a>
  <a href="https://www.npmjs.com/package/@costea/web"><img src="https://img.shields.io/npm/v/%40costea%2Fweb?color=red&label=npm%20web" alt="npm web" /></a>
  <a href="https://github.com/memovai/costea"><img src="https://img.shields.io/badge/GitHub-costea-black" alt="GitHub" /></a>
</p>

<p align="center"><b>쓰기 전에, 비용을 알자.</b></p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a>
</p>

---

## 설치

### 방법 A: npm (권장)

```bash
# CLI 스킬 설치 (/costea + /costeamigo)
npx @costea/costea

# Web UI 대시보드 시작
npx @costea/web serve 3000
```

> npm 레지스트리가 비공개인 경우: `--registry https://registry.npmjs.org` 를 추가하세요.

### 방법 B: Git clone

```bash
git clone https://github.com/memovai/costea.git
cd costea

# Claude Code에 스킬 연결
ln -sf $(pwd)/skills/costea ~/.claude/skills/costea
ln -sf $(pwd)/skills/costeamigo ~/.claude/skills/costeamigo

# Codex CLI에 스킬 연결
ln -sf $(pwd)/skills/costea ~/.codex/skills/costea

# Web UI 시작
cd web && npm install && npm run dev
```

### 요구 사항

- **jq** — `brew install jq` (모든 셸 스크립트에서 사용)
- **Node.js 18+** — Web UI 전용

### 첫 실행 — 인덱스 빌드

설치 후, 히스토리에서 세션 인덱스를 빌드하세요:

```bash
# 설치된 스킬 스크립트를 통해 실행
bash ~/.claude/skills/costea/scripts/update-index.sh

# 또는 clone한 경우
bash skills/costea/scripts/update-index.sh
```

이 명령은 `~/.claude/projects/`, `~/.codex/sessions/`, `~/.openclaw/` 를 스캔하여 작업 데이터베이스를 구축합니다.

---

## 사용법

### CLI 스킬

설치 후 새로운 Claude Code 또는 Codex 세션을 열어 사용하세요:

```bash
# 작업 실행 전 비용 예측 — 영수증을 표시하고 Y/N 확인을 요청합니다
/costea refactor the auth module

# 과거 지출 리포트
/costeamigo all        # 모든 플랫폼 통합
/costeamigo claude     # Claude Code만
/costeamigo codex      # Codex CLI만
/costeamigo openclaw   # OpenClaw만
```

### Web UI

```bash
# npm을 통해 실행
npx @costea/web serve 3000

# 또는 로컬에서 실행
cd web && npm run dev
```

http://localhost:3000 을 열어 확인하세요 — 페이지 목록:

| 페이지 | 표시 내용 |
|------|--------------|
| `/` | 영수증 카드, 설치 명령어가 포함된 랜딩 페이지 |
| `/dashboard` | 모든 세션, 총 비용, 플랫폼 필터, 비용/토큰/날짜별 정렬 |
| `/session/{id}` | 세션별 상세 정보: 모델 분석, 도구, 턴 (LLM 호출 상세 정보 펼침 가능) |
| `/estimate` | 인터랙티브 비용 예측 — 작업을 입력하면 실시간 영수증 표시 |
| `/analytics` | 시간대별 비용, 모델/플랫폼별 차트, 일별 분석 |
| `/accuracy` | 예측 vs 실제 비교: 산점도, 오차 분포, 정확도 통계 |

---

## 스킬

### `/costea` — 비용 예측 영수증

실행 **전에** 토큰 비용을 예측합니다. 다중 제공자 비교가 포함된 터미널 영수증을 보여주고, Y/N 확인을 요청합니다. 예측 결과는 `~/.costea/estimates.jsonl`에 기록되며, 실행 후 실제 사용량과 비교됩니다.

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

### `/costeamigo` — 과거 지출 리포트

다차원 분석: 플랫폼별, 모델별, 스킬별, 도구 사용 패턴, 추론 vs 도구 비율, 가장 비용이 높은 작업 목록.

---

## 작동 원리

```
Session JSONL (3개 플랫폼)
      ↓  parse-claudecode.sh / parse-codex.sh / parse-openclaw.sh
~/.costea/sessions/{id}/
  session.jsonl · llm-calls.jsonl · tools.jsonl · agents.jsonl
      ↓  summarize-session.sh
summary.json → index.json
      ↓
  ┌───────┬──────────┬────────────┐
  ↓       ↓          ↓            ↓
/costea  /costeamigo  Web UI    estimates.jsonl
영수증    리포트      대시보드   예측 추적
+ Y/N                분석       정확도 비교
```

### 핵심 설계

- **병렬 도구 호출 중복 제거** — Claude Code는 하나의 API 응답을 동일한 `message.id`를 공유하는 여러 레코드로 분할합니다. 첫 번째 레코드만 집계됩니다.
- **누적 델타** — Codex CLI는 누적 합계를 저장합니다. 턴당 사용량 = `현재 - 이전`.
- **네이티브 비용** — OpenClaw는 메시지당 USD 비용을 직접 제공합니다.
- **서브에이전트 귀속** — Claude Code `subagents/agent-*.jsonl`을 스캔하여 상위 세션에 귀속시킵니다.
- **예측 추적** — 각 `/costea` 예측이 기록되며, 실행 후 실제 사용량과 비교됩니다.

---

## 지원 플랫폼

| 플랫폼 | 파서 | 토큰 소스 | 상태 |
|----------|--------|-------------|--------|
| Claude Code | `parse-claudecode.sh` | 어시스턴트 메시지별 `message.usage` | 테스트 완료 |
| Codex CLI | `parse-codex.sh` | 누적 `token_count` 이벤트 | 테스트 완료 |
| OpenClaw | `parse-openclaw.sh` | 비용 포함 `message.usage` | 테스트 완료 |

---

## npm 패키지

| 패키지 | 버전 | 용도 | 설치 |
|---------|---------|---------|---------|
| `@costea/costea` | 1.1.0 | CLI 스킬 (SKILL.md + 스크립트) | `npx @costea/costea` |
| `@costea/web` | 1.0.0 | Web UI (독립형 Next.js) | `npx @costea/web serve [port]` |

---

## 스크립트 참조

| 스크립트 | 용도 |
|--------|---------|
| `parse-claudecode.sh` | Claude Code JSONL 파싱 (중복 제거 + 서브에이전트) |
| `parse-codex.sh` | Codex CLI rollout JSONL 파싱 (누적 델타) |
| `parse-openclaw.sh` | OpenClaw JSONL 파싱 (네이티브 비용) |
| `build-index.sh` | 모든 플랫폼의 작업 인덱스 빌드 |
| `estimate-cost.sh` | 예측을 위한 과거 데이터 및 집계 통계 |
| `receipt.sh` | JSON으로부터 터미널 영수증 렌더링 |
| `log-estimate.sh` | 정확도 추적을 위한 예측 및 실제값 기록 |
| `summarize-session.sh` | 세션 JSONL로부터 summary.json 생성 |
| `update-index.sh` | 전체 스캔 및 인덱스 재빌드 |
| `test-all.sh` | 회귀 테스트 스위트 실행 (9개 테스트) |
| `lib/cost.sh` | 공유 가격표 및 jq 헬퍼 |

---

## 데이터 디렉터리

모든 데이터는 `~/.costea/` 아래에 저장됩니다 — 삭제 후 재생성해도 안전합니다:

```
~/.costea/
├── sessions/{uuid}/
│   ├── session.jsonl      턴별 요약
│   ├── llm-calls.jsonl    API 호출별 레코드 (중복 제거됨)
│   ├── tools.jsonl        도구별 호출 기록
│   ├── agents.jsonl       서브에이전트 생명주기 이벤트
│   └── summary.json       집계된 세션 통계
├── task-index.json        작업 인덱스 (build-index.sh)
├── index.json             세션 인덱스 (update-index.sh)
└── estimates.jsonl        예측 기록 (log-estimate.sh)
```

---

## 라이선스

[Apache License 2.0](LICENSE)
