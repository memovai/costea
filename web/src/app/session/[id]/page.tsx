"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";

interface Turn {
  turn_id: string;
  timestamp: string;
  user_prompt: string;
  is_skill: boolean;
  skill_name: string | null;
  token_usage: { input: number; output: number; cache_read: number; cache_write: number; total: number };
  cost: { total_usd: number; by_model: Record<string, number> };
  tools_summary: { total_calls: number; by_tool: Record<string, number> };
  llm_call_count: number;
}

interface Summary {
  session_id: string;
  source: string;
  project_path: string;
  started_at: string;
  ended_at: string;
  turn_count: number;
  llm_call_count: number;
  tool_call_count: number;
  token_usage: { input: number; output: number; cache_read: number; cache_write: number; total: number; grand_total: number };
  cost: { total_usd: number; by_model: Record<string, number> };
  by_model: { model: string; call_count: number; input: number; output: number; cost_usd: number }[];
  top_tools: { tool: string; calls: number; category: string }[];
  reasoning_vs_tools: { reasoning_pct: number; reasoning_tokens: number; tool_inv_tokens: number };
  subagents: { count: number; total_tokens: number; total_cost_usd: number };
}

function fmt(n: number) { return n.toLocaleString(); }
function fmtCost(n: number) { return `$${n < 0.01 ? n.toFixed(4) : n.toFixed(2)}`; }

function Bar({ pct, color = "bg-foreground" }: { pct: number; color?: string }) {
  return (
    <div className="w-full bg-surface-warm rounded-full h-2">
      <div className={`${color} h-2 rounded-full transition-all`} style={{ width: `${Math.min(pct, 100)}%` }} />
    </div>
  );
}

export default function SessionPage() {
  const { id } = useParams<{ id: string }>();
  const [data, setData] = useState<{ summary: Summary; turns: Turn[] } | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch(`/api/sessions/${id}`)
      .then((r) => { if (!r.ok) throw new Error("Not found"); return r.json(); })
      .then(setData)
      .catch((e) => setError(e.message));
  }, [id]);

  if (error) return <div className="max-w-4xl mx-auto px-6 py-16"><p className="text-muted">Session not found.</p></div>;
  if (!data) return <div className="max-w-4xl mx-auto px-6 py-16"><p className="text-muted">Loading...</p></div>;

  const { summary: s, turns } = data;
  const maxTurnCost = Math.max(...turns.map((t) => t.cost.total_usd), 0.001);

  return (
    <div className="max-w-6xl mx-auto px-6 py-12">
      <Link href="/dashboard" className="text-xs text-muted hover:text-foreground mb-4 inline-block">&larr; Dashboard</Link>

      {/* Header */}
      <div className="flex items-baseline gap-4 mb-8">
        <h1 className="text-2xl font-bold font-mono">{s.session_id.slice(0, 12)}...</h1>
        <span className="text-xs px-2 py-0.5 bg-foreground text-surface rounded">{s.source}</span>
      </div>

      {/* Overview cards */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-4 mb-10">
        {[
          ["Total Cost", fmtCost(s.cost.total_usd)],
          ["Tokens", fmt(s.token_usage.grand_total)],
          ["Turns", String(s.turn_count)],
          ["LLM Calls", String(s.llm_call_count)],
          ["Tools", String(s.tool_call_count)],
        ].map(([label, value]) => (
          <div key={label} className="bg-surface receipt-shadow rounded px-4 py-3">
            <p className="text-[10px] text-muted uppercase tracking-wider">{label}</p>
            <p className="text-lg font-bold font-mono mt-0.5">{value}</p>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        {/* Model breakdown */}
        <div className="bg-surface receipt-shadow rounded p-5">
          <p className="text-xs text-muted uppercase tracking-wider mb-4">By Model</p>
          <div className="space-y-3">
            {(s.by_model || []).map((m) => (
              <div key={m.model}>
                <div className="flex justify-between text-sm mb-1">
                  <span className="font-mono text-xs">{m.model}</span>
                  <span className="font-mono text-xs">{fmtCost(m.cost_usd)}</span>
                </div>
                <Bar pct={(m.cost_usd / (s.cost.total_usd || 1)) * 100} />
              </div>
            ))}
          </div>
        </div>

        {/* Top tools */}
        <div className="bg-surface receipt-shadow rounded p-5">
          <p className="text-xs text-muted uppercase tracking-wider mb-4">Top Tools</p>
          <div className="space-y-2">
            {(s.top_tools || []).slice(0, 10).map((t) => (
              <div key={t.tool} className="flex justify-between text-sm">
                <span>{t.tool}</span>
                <span className="font-mono text-xs text-muted">{t.calls} calls</span>
              </div>
            ))}
          </div>
        </div>

        {/* Reasoning vs Tools */}
        <div className="bg-surface receipt-shadow rounded p-5">
          <p className="text-xs text-muted uppercase tracking-wider mb-4">Reasoning vs Tool Invocation</p>
          <div className="flex gap-2 items-center">
            <div className="bg-foreground h-4 rounded-l" style={{ width: `${s.reasoning_vs_tools.reasoning_pct}%` }} />
            <div className="bg-foreground/30 h-4 rounded-r flex-1" />
          </div>
          <div className="flex justify-between text-xs text-muted mt-2">
            <span>Reasoning {s.reasoning_vs_tools.reasoning_pct}%</span>
            <span>Tool invocation {100 - s.reasoning_vs_tools.reasoning_pct}%</span>
          </div>
        </div>

        {/* Subagents */}
        {s.subagents.count > 0 && (
          <div className="bg-surface receipt-shadow rounded p-5">
            <p className="text-xs text-muted uppercase tracking-wider mb-4">Subagents</p>
            <p className="text-sm">{s.subagents.count} agents, {fmt(s.subagents.total_tokens)} tokens, {fmtCost(s.subagents.total_cost_usd)}</p>
          </div>
        )}
      </div>

      {/* Turn-by-turn */}
      <div className="mt-10">
        <p className="text-xs text-muted uppercase tracking-wider mb-4">Turns ({turns.length})</p>
        <div className="space-y-2">
          {turns.map((t) => (
            <div key={t.turn_id} className="bg-surface receipt-shadow rounded px-4 py-3">
              <div className="flex items-start justify-between gap-4">
                <div className="flex-1 min-w-0">
                  <p className="text-sm truncate">
                    {t.is_skill && <span className="text-xs bg-foreground/10 px-1 rounded mr-1">/{t.skill_name}</span>}
                    {t.user_prompt || "(empty)"}
                  </p>
                  <div className="flex gap-4 mt-1 text-[10px] text-muted">
                    <span>{fmt(t.token_usage.total)} tok</span>
                    <span>{t.tools_summary.total_calls} tools</span>
                    <span>{t.llm_call_count} calls</span>
                  </div>
                </div>
                <div className="text-right shrink-0">
                  <p className="font-mono text-xs font-medium">{fmtCost(t.cost.total_usd)}</p>
                  <Bar pct={(t.cost.total_usd / maxTurnCost) * 100} />
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
