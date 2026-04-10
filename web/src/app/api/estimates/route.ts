import { NextResponse } from "next/server";
import { readFile } from "fs/promises";
import { existsSync } from "fs";
import path from "path";
import { homedir } from "os";

export const dynamic = "force-dynamic";

const ESTIMATES_FILE = path.join(homedir(), ".costea", "estimates.jsonl");

interface EstimateRecord {
  record_type: string;
  estimate_id: string;
  timestamp: string;
  status: "pending" | "completed";
  predicted: {
    task: string;
    input_tokens: number;
    output_tokens: number;
    tool_calls: number;
    total_cost: number;
    confidence: number;
    estimate_method: string;
    similar_tasks: number;
  };
  actual: {
    input_tokens: number;
    output_tokens: number;
    tool_calls: number;
    total_cost: number;
  } | null;
  accuracy: {
    input_ratio: number | null;
    output_ratio: number | null;
    cost_ratio: number | null;
    tool_ratio: number | null;
    cost_error_pct: number | null;
  } | null;
}

export async function GET() {
  if (!existsSync(ESTIMATES_FILE)) {
    return NextResponse.json({
      estimates: [],
      summary: { total: 0, completed: 0, avg_cost_error: null, avg_accuracy: null },
    });
  }

  const raw = await readFile(ESTIMATES_FILE, "utf-8");
  const records: EstimateRecord[] = raw
    .split("\n")
    .filter((l) => l.trim())
    .map((l) => { try { return JSON.parse(l); } catch { return null; } })
    .filter(Boolean);

  // Deduplicate: for each estimate_id, keep the latest record (completed overrides pending)
  const byId = new Map<string, EstimateRecord>();
  for (const r of records) {
    const existing = byId.get(r.estimate_id);
    if (!existing || r.status === "completed") {
      byId.set(r.estimate_id, r);
    }
  }
  const estimates = [...byId.values()].sort(
    (a, b) => (b.timestamp || "").localeCompare(a.timestamp || "")
  );

  // Compute summary stats
  const completed = estimates.filter((e) => e.status === "completed" && e.accuracy);
  const costErrors = completed
    .map((e) => e.accuracy?.cost_error_pct)
    .filter((v): v is number => v !== null && v !== undefined);
  const costRatios = completed
    .map((e) => e.accuracy?.cost_ratio)
    .filter((v): v is number => v !== null && v !== undefined);

  const summary = {
    total: estimates.length,
    completed: completed.length,
    pending: estimates.filter((e) => e.status === "pending").length,
    avg_cost_error: costErrors.length > 0
      ? Math.round((costErrors.reduce((a, b) => a + Math.abs(b), 0) / costErrors.length) * 10) / 10
      : null,
    avg_accuracy: costRatios.length > 0
      ? Math.round(costRatios.reduce((a, b) => a + b, 0) / costRatios.length)
      : null,
    median_cost_error: costErrors.length > 0
      ? (() => { const s = [...costErrors].map(Math.abs).sort((a, b) => a - b); return s[Math.floor(s.length / 2)]; })()
      : null,
    over_estimates: costErrors.filter((e) => e > 10).length,
    under_estimates: costErrors.filter((e) => e < -10).length,
    within_10pct: costErrors.filter((e) => Math.abs(e) <= 10).length,
  };

  return NextResponse.json({ estimates, summary });
}
