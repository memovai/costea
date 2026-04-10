import { NextResponse } from "next/server";
import { readFile, appendFile, readdir, stat } from "fs/promises";
import { existsSync } from "fs";
import path from "path";
import { homedir } from "os";

export const dynamic = "force-dynamic";

const COSTEA_DIR = path.join(homedir(), ".costea");
const ESTIMATES_FILE = path.join(COSTEA_DIR, "estimates.jsonl");
const CLAUDE_PROJECTS = path.join(homedir(), ".claude", "projects");

/** Price table (USD per million tokens) — same as lib/cost.sh */
const PRICES: Record<string, { input: number; output: number; cache_read: number; cache_write: number }> = {
  "claude-opus-4-6":   { input: 5,    output: 25,   cache_read: 0.50,  cache_write: 6.25 },
  "claude-opus-4-5":   { input: 5,    output: 25,   cache_read: 0.50,  cache_write: 6.25 },
  "claude-opus-4":     { input: 15,   output: 75,   cache_read: 1.50,  cache_write: 18.75 },
  "claude-sonnet-4-6": { input: 3,    output: 15,   cache_read: 0.30,  cache_write: 3.75 },
  "claude-sonnet-4":   { input: 3,    output: 15,   cache_read: 0.30,  cache_write: 3.75 },
  "claude-haiku-4-5":  { input: 1,    output: 5,    cache_read: 0.10,  cache_write: 1.25 },
};

function normalizeModel(model: string): string {
  const m = model.toLowerCase();
  if (m.includes("opus") && (m.includes("4-6") || m.includes("4.6"))) return "claude-opus-4-6";
  if (m.includes("opus") && (m.includes("4-5") || m.includes("4.5"))) return "claude-opus-4-5";
  if (m.includes("opus")) return "claude-opus-4";
  if (m.includes("sonnet") && (m.includes("4-6") || m.includes("4.6"))) return "claude-sonnet-4-6";
  if (m.includes("sonnet")) return "claude-sonnet-4";
  if (m.includes("haiku")) return "claude-haiku-4-5";
  return "claude-opus-4-6";
}

function calcCost(model: string, input: number, output: number, cacheRead: number, cacheWrite: number): number {
  const p = PRICES[normalizeModel(model)] || PRICES["claude-opus-4-6"];
  return (input * p.input + output * p.output + cacheRead * p.cache_read + cacheWrite * p.cache_write) / 1_000_000;
}

interface EstimateRecord {
  estimate_id: string;
  timestamp: string;
  status: string;
  predicted: { task: string; total_cost: number; input_tokens: number; output_tokens: number; tool_calls: number; confidence: number };
}

interface SessionMsg {
  type: string;
  timestamp?: string;
  message?: {
    id?: string;
    model?: string;
    usage?: {
      input_tokens?: number;
      output_tokens?: number;
      cache_read_input_tokens?: number;
      cache_creation_input_tokens?: number;
    };
    content?: { type: string }[];
  };
}

export async function POST() {
  if (!existsSync(ESTIMATES_FILE)) {
    return NextResponse.json({ backfilled: 0, message: "No estimates file" });
  }

  const raw = await readFile(ESTIMATES_FILE, "utf-8");
  const records = raw.split("\n").filter(l => l.trim()).map(l => {
    try { return JSON.parse(l) as EstimateRecord; } catch { return null; }
  }).filter(Boolean) as EstimateRecord[];

  // Find pending estimates (not yet completed)
  const completedIds = new Set(records.filter(r => r.status === "completed").map(r => r.estimate_id));
  const pending = records.filter(r => r.status === "pending" && !completedIds.has(r.estimate_id));

  if (pending.length === 0) {
    return NextResponse.json({ backfilled: 0, message: "No pending estimates" });
  }

  // Find all session JSONL files
  const sessionFiles: { path: string; mtime: number }[] = [];
  if (existsSync(CLAUDE_PROJECTS)) {
    const projects = await readdir(CLAUDE_PROJECTS);
    for (const proj of projects) {
      const projDir = path.join(CLAUDE_PROJECTS, proj);
      const st = await stat(projDir).catch(() => null);
      if (!st?.isDirectory()) continue;
      const files = await readdir(projDir);
      for (const f of files) {
        if (!f.endsWith(".jsonl")) continue;
        if (f.includes("subagents")) continue;
        const fp = path.join(projDir, f);
        const fst = await stat(fp).catch(() => null);
        if (fst) sessionFiles.push({ path: fp, mtime: fst.mtimeMs });
      }
    }
  }

  let backfilled = 0;
  const results: { id: string; status: string; actual_cost?: number }[] = [];

  for (const est of pending) {
    const estTime = new Date(est.timestamp).getTime();

    // Find session files modified after the estimate
    let bestFile = "";
    let bestCount = 0;

    for (const sf of sessionFiles) {
      if (sf.mtime < estTime) continue;

      // Count assistant messages after estimate timestamp
      const content = await readFile(sf.path, "utf-8");
      const lines = content.split("\n").filter(l => l.trim());
      let count = 0;
      for (const line of lines) {
        try {
          const msg: SessionMsg = JSON.parse(line);
          if (msg.type === "assistant" && msg.message?.usage && (msg.timestamp || "") > est.timestamp) {
            count++;
          }
        } catch { /* skip */ }
      }

      if (count > bestCount) {
        bestCount = count;
        bestFile = sf.path;
      }
    }

    if (!bestFile || bestCount === 0) {
      results.push({ id: est.estimate_id, status: "skipped (no session found)" });
      continue;
    }

    // Extract real usage with message.id dedup
    const content = await readFile(bestFile, "utf-8");
    const lines = content.split("\n").filter(l => l.trim());
    const seenIds = new Set<string>();
    let totalInput = 0, totalOutput = 0, totalCacheRead = 0, totalCacheWrite = 0, toolCalls = 0;
    let model = "unknown";

    for (const line of lines) {
      try {
        const msg: SessionMsg = JSON.parse(line);
        if (msg.type !== "assistant" || !msg.message?.usage) continue;
        if ((msg.timestamp || "") <= est.timestamp) continue;

        const msgId = msg.message.id || `_noid_${msg.timestamp}`;
        if (seenIds.has(msgId)) continue; // dedup parallel tool calls
        seenIds.add(msgId);

        const u = msg.message.usage;
        totalInput += u.input_tokens || 0;
        totalOutput += u.output_tokens || 0;
        totalCacheRead += u.cache_read_input_tokens || 0;
        totalCacheWrite += u.cache_creation_input_tokens || 0;

        if (msg.message.model) model = msg.message.model;
        const tools = (msg.message.content || []).filter(c => c.type === "tool_use");
        toolCalls += tools.length;
      } catch { /* skip */ }
    }

    const actualCost = Math.round(calcCost(model, totalInput, totalOutput, totalCacheRead, totalCacheWrite) * 1000000) / 1000000;

    // Write completed record
    const actual = { input_tokens: totalInput, output_tokens: totalOutput, cache_read_tokens: totalCacheRead, tool_calls: toolCalls, total_cost: actualCost };
    const predicted = est.predicted;

    const accuracy = {
      input_ratio: predicted.input_tokens > 0 ? Math.round(totalInput / predicted.input_tokens * 100) : null,
      output_ratio: predicted.output_tokens > 0 ? Math.round(totalOutput / predicted.output_tokens * 100) : null,
      cost_ratio: predicted.total_cost > 0 ? Math.round(actualCost / predicted.total_cost * 100) : null,
      tool_ratio: predicted.tool_calls > 0 ? Math.round(toolCalls / predicted.tool_calls * 100) : null,
      cost_error_pct: predicted.total_cost > 0 ? Math.round(((actualCost - predicted.total_cost) / predicted.total_cost * 100) * 10) / 10 : null,
    };

    const completedRecord = { ...est, status: "completed", completed_at: new Date().toISOString(), actual, accuracy };
    await appendFile(ESTIMATES_FILE, JSON.stringify(completedRecord) + "\n");

    backfilled++;
    results.push({ id: est.estimate_id, status: "backfilled", actual_cost: actualCost });
  }

  return NextResponse.json({ backfilled, total_pending: pending.length, results });
}
