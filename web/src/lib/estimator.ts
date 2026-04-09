/**
 * Costea Estimator — predict token cost for a new task based on session history.
 *
 * Uses task-index.json (built by build-index.sh) for historical matching,
 * and session summaries for richer stats (cache patterns, model distributions).
 */

import { readFile } from "fs/promises";
import { existsSync } from "fs";
import path from "path";
import { homedir } from "os";
import { getIndex, getSessionSummary } from "./costea-data";

const COSTEA_DIR = path.join(homedir(), ".costea");
const TASK_INDEX = path.join(COSTEA_DIR, "task-index.json");

/** Multi-provider prices (USD per million tokens) */
const PROVIDERS = [
  { name: "Claude Sonnet 4.6", input: 3, output: 15 },
  { name: "Claude Opus 4.6", input: 5, output: 25 },
  { name: "Claude Haiku 4.5", input: 1, output: 5 },
  { name: "GPT-5.4", input: 2.5, output: 15 },
  { name: "GPT-5.2 Codex", input: 1.07, output: 8.5 },
  { name: "Gemini 2.5 Pro", input: 1.25, output: 5 },
  { name: "Gemini 2.5 Flash", input: 0.15, output: 0.6 },
];

interface TaskRecord {
  source: string;
  session_id: string;
  model: string;
  timestamp: string;
  is_skill: boolean;
  skill_name: string | null;
  user_prompt: string;
  token_usage: { input: number; output: number; cache_read: number; cache_write: number; total: number };
  cost: { total: number };
  tools: { name: string; count: number }[];
  total_tool_calls: number;
  assistant_message_count: number;
  reasoning: { tokens: number; count: number };
  tool_invocation: { tokens: number; count: number };
}

interface TaskIndex {
  tasks: TaskRecord[];
  task_count: number;
  total_tokens: number;
  built_at: string;
}

/** Simple keyword overlap scorer (0-1) */
function similarity(a: string, b: string): number {
  const normalize = (s: string) =>
    s.toLowerCase().replace(/[^a-z0-9\u4e00-\u9fff]+/g, " ").trim().split(/\s+/);
  const wordsA = new Set(normalize(a));
  const wordsB = new Set(normalize(b));
  if (wordsA.size === 0 || wordsB.size === 0) return 0;
  let overlap = 0;
  for (const w of wordsA) if (wordsB.has(w)) overlap++;
  return overlap / Math.max(wordsA.size, wordsB.size);
}

/** Classify task complexity from description */
function classifyTask(desc: string): "simple" | "read" | "modify" | "skill" | "refactor" | "feature" {
  const d = desc.toLowerCase();
  if (d.match(/^\/[a-z]/)) return "skill";
  if (d.match(/refactor|重构|rewrite|重写|migrate|迁移/)) return "refactor";
  if (d.match(/implement|实现|build|构建|create|创建|add feature|新功能/)) return "feature";
  if (d.match(/fix|修复|bug|error|报错|issue/)) return "modify";
  if (d.match(/read|看|explain|解释|what|how|为什么|分析|review/)) return "read";
  return "simple";
}

/** Baseline estimates by task type */
const BASELINES: Record<string, { input: number; output: number; tools: number; runtime: string }> = {
  simple:   { input: 8000,   output: 2000,  tools: 3,   runtime: "~30s" },
  read:     { input: 35000,  output: 5000,  tools: 8,   runtime: "~1 min" },
  modify:   { input: 50000,  output: 10000, tools: 15,  runtime: "~2 min" },
  skill:    { input: 120000, output: 30000, tools: 30,  runtime: "~5 min" },
  refactor: { input: 250000, output: 50000, tools: 50,  runtime: "~10 min" },
  feature:  { input: 500000, output: 100000, tools: 80, runtime: "~15 min" },
};

export interface EstimateResult {
  task: string;
  task_type: string;
  has_history: boolean;
  similar_tasks: {
    prompt: string;
    source: string;
    model: string;
    tokens: number;
    input: number;
    output: number;
    cache_read: number;
    cost_usd: number;
    tool_calls: number;
    tools: string[];
    similarity: number;
    reasoning_pct: number;
  }[];
  estimate: {
    input_tokens: number;
    output_tokens: number;
    cache_read_tokens: number;
    cache_hit_pct: number;
    tool_calls: number;
    est_runtime: string;
  };
  providers: { name: string; cost: number }[];
  total_cost: number;
  best_provider: string;
  confidence: number;
  stats: {
    total_sessions: number;
    total_historical_tasks: number;
    avg_tokens_per_task: number;
    avg_cost_per_task: number;
    models_used: string[];
    top_tools: string[];
    avg_cache_hit_pct: number;
  };
}

export async function estimateTask(taskDesc: string): Promise<EstimateResult> {
  // Load task index
  let taskIndex: TaskIndex | null = null;
  if (existsSync(TASK_INDEX)) {
    try {
      const raw = await readFile(TASK_INDEX, "utf-8");
      if (raw.trim()) taskIndex = JSON.parse(raw);
    } catch { /* corrupted or empty file — treat as no index */ }
  }

  // Load session index for stats
  const sessionIndex = await getIndex();

  const taskType = classifyTask(taskDesc);
  const baseline = BASELINES[taskType];

  // Find similar historical tasks
  const similarTasks: EstimateResult["similar_tasks"] = [];
  if (taskIndex && taskIndex.tasks.length > 0) {
    const scored = taskIndex.tasks
      .filter((t) => t.token_usage.total > 0)
      .map((t) => ({
        ...t,
        sim: similarity(taskDesc, t.user_prompt || ""),
        // Boost score for same skill type
        skillBoost: t.is_skill && taskDesc.startsWith("/") && t.skill_name === taskDesc.split(/\s/)[0].slice(1) ? 0.5 : 0,
      }))
      .map((t) => ({ ...t, score: t.sim + t.skillBoost }))
      .filter((t) => t.score > 0.05)
      .sort((a, b) => b.score - a.score)
      .slice(0, 10);

    for (const t of scored) {
      similarTasks.push({
        prompt: (t.user_prompt || "").slice(0, 120),
        source: t.source,
        model: t.model,
        tokens: t.token_usage.total,
        input: t.token_usage.input,
        output: t.token_usage.output,
        cache_read: t.token_usage.cache_read || 0,
        cost_usd: t.cost.total,
        tool_calls: t.total_tool_calls,
        tools: (t.tools || []).map((x) => x.name).slice(0, 8),
        similarity: Math.round(t.score * 100),
        reasoning_pct:
          t.token_usage.total > 0
            ? Math.round(((t.reasoning?.tokens || 0) / t.token_usage.total) * 100)
            : 0,
      });
    }
  }

  // Compute estimate: weighted average of similar tasks, fallback to baseline
  let estInput: number, estOutput: number, estCacheRead: number, estTools: number, estRuntime: string;
  let confidence: number;

  if (similarTasks.length >= 3) {
    // Weighted average by similarity score
    const totalWeight = similarTasks.slice(0, 5).reduce((s, t) => s + t.similarity, 0);
    const top = similarTasks.slice(0, 5);
    estInput = Math.round(top.reduce((s, t) => s + t.input * t.similarity, 0) / totalWeight);
    estOutput = Math.round(top.reduce((s, t) => s + t.output * t.similarity, 0) / totalWeight);
    estCacheRead = Math.round(top.reduce((s, t) => s + t.cache_read * t.similarity, 0) / totalWeight);
    estTools = Math.round(top.reduce((s, t) => s + t.tool_calls * t.similarity, 0) / totalWeight);
    const estTotalTokens = estInput + estOutput + estCacheRead;
    const estSeconds = Math.max(10, Math.round(estTotalTokens / 1200));
    estRuntime = estSeconds < 60 ? `~${estSeconds}s` : `~${Math.round(estSeconds / 60)} min`;
    confidence = Math.min(98, 70 + Math.min(similarTasks.length, 5) * 5 + Math.round(similarTasks[0].similarity * 0.1));
  } else if (similarTasks.length > 0) {
    // Some matches: blend with baseline
    const avg = similarTasks[0];
    estInput = Math.round((avg.input + baseline.input) / 2);
    estOutput = Math.round((avg.output + baseline.output) / 2);
    estCacheRead = Math.round(avg.cache_read / 2);
    estTools = Math.round((avg.tool_calls + baseline.tools) / 2);
    estRuntime = baseline.runtime;
    confidence = 50 + similarTasks.length * 10;
  } else {
    // Pure baseline
    estInput = baseline.input;
    estOutput = baseline.output;
    estCacheRead = 0;
    estTools = baseline.tools;
    estRuntime = baseline.runtime;
    confidence = 35;
  }

  const cacheHitPct = estInput + estOutput > 0
    ? Math.round((estCacheRead / (estInput + estOutput + estCacheRead)) * 100)
    : 0;

  // Multi-provider pricing
  const providerCosts = PROVIDERS.map((p) => ({
    name: p.name,
    cost: Math.round(((estInput * p.input + estOutput * p.output) / 1_000_000) * 10000) / 10000,
  })).sort((a, b) => a.cost - b.cost);

  const bestProvider = providerCosts[0];
  // Total cost = current model's likely cost (Sonnet 4.6 as default)
  const sonnet = providerCosts.find((p) => p.name.includes("Sonnet")) || providerCosts[0];

  // Aggregate stats from session index
  const stats = {
    total_sessions: sessionIndex?.session_count || 0,
    total_historical_tasks: taskIndex?.task_count || 0,
    avg_tokens_per_task: taskIndex && taskIndex.task_count > 0
      ? Math.round(taskIndex.total_tokens / taskIndex.task_count)
      : 0,
    avg_cost_per_task: sessionIndex && sessionIndex.session_count > 0
      ? Math.round((sessionIndex.total_cost_usd / sessionIndex.session_count) * 100) / 100
      : 0,
    models_used: [...new Set((taskIndex?.tasks || []).map((t) => t.model).filter(Boolean))].slice(0, 10),
    top_tools: [...new Set(
      (taskIndex?.tasks || []).flatMap((t) => (t.tools || []).map((x) => x.name))
    )].slice(0, 10),
    avg_cache_hit_pct: (() => {
      const tasks = (taskIndex?.tasks || []).filter((t) => t.token_usage.total > 0);
      if (tasks.length === 0) return 0;
      const totalCache = tasks.reduce((s, t) => s + (t.token_usage.cache_read || 0), 0);
      const totalTokens = tasks.reduce((s, t) => s + t.token_usage.total, 0);
      return Math.round((totalCache / totalTokens) * 100);
    })(),
  };

  return {
    task: taskDesc,
    task_type: taskType,
    has_history: similarTasks.length > 0,
    similar_tasks: similarTasks,
    estimate: {
      input_tokens: estInput,
      output_tokens: estOutput,
      cache_read_tokens: estCacheRead,
      cache_hit_pct: cacheHitPct,
      tool_calls: estTools,
      est_runtime: estRuntime,
    },
    providers: providerCosts.slice(0, 5),
    total_cost: sonnet.cost,
    best_provider: bestProvider.name,
    confidence,
    stats,
  };
}
