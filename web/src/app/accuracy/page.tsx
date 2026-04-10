"use client";

import { useEffect, useState } from "react";

interface Estimate {
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

interface Summary {
  total: number;
  completed: number;
  pending: number;
  avg_cost_error: number | null;
  avg_accuracy: number | null;
  median_cost_error: number | null;
  over_estimates: number;
  under_estimates: number;
  within_10pct: number;
}

function fmt(n: number) { return n.toLocaleString(); }
function fmtCost(n: number) { return `$${n < 0.01 && n > 0 ? n.toFixed(4) : n.toFixed(2)}`; }
function pctColor(pct: number | null): string {
  if (pct === null) return "text-muted";
  const abs = Math.abs(pct);
  if (abs <= 10) return "text-green-700";
  if (abs <= 25) return "text-yellow-700";
  return "text-red-700";
}

/** SVG scatter plot: predicted cost (x) vs actual cost (y) */
function ScatterPlot({ data }: { data: { predicted: number; actual: number; task: string }[] }) {
  if (data.length === 0) return <p className="text-xs text-muted">No completed estimates yet.</p>;

  const W = 400, H = 300, P = 50;
  const maxVal = Math.max(...data.map(d => Math.max(d.predicted, d.actual)), 0.01) * 1.1;

  const toX = (v: number) => P + (v / maxVal) * (W - 2 * P);
  const toY = (v: number) => H - P - (v / maxVal) * (H - 2 * P);

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full max-w-[500px]" preserveAspectRatio="xMidYMid meet">
      {/* Grid */}
      {[0, 0.25, 0.5, 0.75, 1].map(pct => {
        const val = maxVal * pct;
        const x = toX(val), y = toY(val);
        return (
          <g key={pct}>
            <line x1={P} y1={y} x2={W - P} y2={y} stroke="var(--border)" strokeWidth="0.5" />
            <line x1={x} y1={P} x2={x} y2={H - P} stroke="var(--border)" strokeWidth="0.5" />
            <text x={P - 4} y={y + 3} textAnchor="end" fontSize="8" fill="var(--muted)">{fmtCost(val)}</text>
            <text x={x} y={H - P + 12} textAnchor="middle" fontSize="8" fill="var(--muted)">{fmtCost(val)}</text>
          </g>
        );
      })}

      {/* Perfect prediction line (y = x) */}
      <line x1={toX(0)} y1={toY(0)} x2={toX(maxVal)} y2={toY(maxVal)} stroke="var(--foreground)" strokeWidth="1" strokeDasharray="4,3" opacity="0.3" />

      {/* Data points */}
      {data.map((d, i) => (
        <circle key={i} cx={toX(d.predicted)} cy={toY(d.actual)} r="4" fill="var(--foreground)" opacity="0.7">
          <title>{`${d.task.slice(0, 40)}\nPredicted: ${fmtCost(d.predicted)}\nActual: ${fmtCost(d.actual)}`}</title>
        </circle>
      ))}

      {/* Axis labels */}
      <text x={W / 2} y={H - 5} textAnchor="middle" fontSize="9" fill="var(--muted)">Predicted Cost</text>
      <text x={12} y={H / 2} textAnchor="middle" fontSize="9" fill="var(--muted)" transform={`rotate(-90, 12, ${H / 2})`}>Actual Cost</text>
    </svg>
  );
}

export default function AccuracyPage() {
  const [data, setData] = useState<{ estimates: Estimate[]; summary: Summary } | null>(null);

  useEffect(() => {
    fetch("/api/estimates").then(r => r.json()).then(setData);
  }, []);

  if (!data) return <div className="max-w-4xl mx-auto px-6 py-16"><p className="text-muted">Loading...</p></div>;

  const { estimates, summary } = data;
  const completed = estimates.filter(e => e.status === "completed" && e.accuracy);
  const scatterData = completed.map(e => ({
    predicted: e.predicted.total_cost,
    actual: e.actual!.total_cost,
    task: e.predicted.task,
  }));

  return (
    <div className="max-w-6xl mx-auto px-6 py-12">
      <h1 className="text-3xl font-bold mb-2">Prediction Accuracy</h1>
      <p className="text-sm text-muted mb-10">
        How well /costea predicts actual token costs.
      </p>

      {/* Summary stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-10">
        <div className="bg-surface receipt-shadow rounded px-5 py-4">
          <p className="text-[10px] text-muted uppercase tracking-wider">Total Estimates</p>
          <p className="text-2xl font-bold font-mono mt-1">{summary.total}</p>
          <p className="text-[10px] text-muted mt-0.5">{summary.completed} completed, {summary.pending} pending</p>
        </div>
        <div className="bg-surface receipt-shadow rounded px-5 py-4">
          <p className="text-[10px] text-muted uppercase tracking-wider">Avg Cost Error</p>
          <p className="text-2xl font-bold font-mono mt-1">{summary.avg_cost_error !== null ? `${summary.avg_cost_error}%` : "—"}</p>
          <p className="text-[10px] text-muted mt-0.5">median: {summary.median_cost_error !== null ? `${summary.median_cost_error}%` : "—"}</p>
        </div>
        <div className="bg-surface receipt-shadow rounded px-5 py-4">
          <p className="text-[10px] text-muted uppercase tracking-wider">Within 10%</p>
          <p className="text-2xl font-bold font-mono mt-1">{summary.within_10pct}</p>
          <p className="text-[10px] text-muted mt-0.5">of {summary.completed} completed</p>
        </div>
        <div className="bg-surface receipt-shadow rounded px-5 py-4">
          <p className="text-[10px] text-muted uppercase tracking-wider">Over / Under</p>
          <p className="text-2xl font-bold font-mono mt-1">{summary.over_estimates} / {summary.under_estimates}</p>
          <p className="text-[10px] text-muted mt-0.5">over &gt;10% / under &gt;10%</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-10">
        {/* Scatter plot */}
        <div className="bg-surface receipt-shadow rounded p-6">
          <p className="text-xs text-muted uppercase tracking-wider mb-4">Predicted vs Actual Cost</p>
          <ScatterPlot data={scatterData} />
          <p className="text-[10px] text-muted mt-2">Dashed line = perfect prediction. Points above = under-estimated, below = over-estimated.</p>
        </div>

        {/* Error distribution */}
        <div className="bg-surface receipt-shadow rounded p-6">
          <p className="text-xs text-muted uppercase tracking-wider mb-4">Cost Error Distribution</p>
          {completed.length === 0 ? (
            <p className="text-xs text-muted">No completed estimates yet. Use /costea to make predictions, then the accuracy data will appear here.</p>
          ) : (
            <div className="space-y-1.5">
              {completed.slice(0, 20).map(e => {
                const err = e.accuracy?.cost_error_pct ?? 0;
                const barWidth = Math.min(Math.abs(err), 100);
                const isOver = err > 0;
                return (
                  <div key={e.estimate_id} className="flex items-center gap-2 text-[10px]">
                    <span className="w-[120px] truncate text-muted">{e.predicted.task.slice(0, 20)}</span>
                    <div className="flex-1 flex items-center h-3">
                      <div className="w-1/2 flex justify-end">
                        {!isOver && <div className="bg-foreground/40 h-3 rounded-l" style={{ width: `${barWidth}%` }} />}
                      </div>
                      <div className="w-px h-4 bg-foreground/30" />
                      <div className="w-1/2">
                        {isOver && <div className="bg-foreground h-3 rounded-r" style={{ width: `${barWidth}%` }} />}
                      </div>
                    </div>
                    <span className={`w-[50px] text-right font-mono ${pctColor(err)}`}>
                      {err > 0 ? "+" : ""}{err}%
                    </span>
                  </div>
                );
              })}
              <div className="flex justify-between text-[9px] text-muted mt-1 px-[120px]">
                <span>under-estimated</span>
                <span>over-estimated</span>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Estimates table */}
      <div className="bg-surface receipt-shadow rounded p-6">
        <p className="text-xs text-muted uppercase tracking-wider mb-4">All Estimates ({estimates.length})</p>
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-border text-left text-muted">
                <th className="pb-2 pr-4">Task</th>
                <th className="pb-2 pr-4">Method</th>
                <th className="pb-2 pr-4">Conf.</th>
                <th className="pb-2 pr-4">Est. Cost</th>
                <th className="pb-2 pr-4">Actual Cost</th>
                <th className="pb-2 pr-4">Error</th>
                <th className="pb-2">Status</th>
              </tr>
            </thead>
            <tbody>
              {estimates.slice(0, 50).map(e => (
                <tr key={e.estimate_id} className="border-b border-border/30">
                  <td className="py-2 pr-4 truncate max-w-[200px]">{e.predicted.task}</td>
                  <td className="py-2 pr-4 font-mono">{e.predicted.estimate_method}</td>
                  <td className="py-2 pr-4 font-mono">{e.predicted.confidence}%</td>
                  <td className="py-2 pr-4 font-mono">{fmtCost(e.predicted.total_cost)}</td>
                  <td className="py-2 pr-4 font-mono">{e.actual ? fmtCost(e.actual.total_cost) : "—"}</td>
                  <td className={`py-2 pr-4 font-mono font-medium ${pctColor(e.accuracy?.cost_error_pct ?? null)}`}>
                    {e.accuracy?.cost_error_pct !== null && e.accuracy?.cost_error_pct !== undefined
                      ? `${e.accuracy.cost_error_pct > 0 ? "+" : ""}${e.accuracy.cost_error_pct}%`
                      : "—"}
                  </td>
                  <td className="py-2">
                    <span className={`px-1.5 py-0.5 rounded text-[10px] ${e.status === "completed" ? "bg-foreground/10" : "bg-foreground/5 text-muted"}`}>
                      {e.status}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
