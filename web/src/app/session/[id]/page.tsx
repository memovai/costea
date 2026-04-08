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
  reasoning: { message_count: number; tokens: number };
  tool_invocation: { message_count: number; tokens: number };
  llm_call_count: number;
}

interface LLMCall {
  call_id: string;
  agent_id: string | null;
  turn_id: string;
  timestamp: string;
  model: string;
  model_short: string;
  usage: { input_tokens: number; output_tokens: number; cache_read_input_tokens: number; cache_creation_input_tokens: number };
  cost_usd: number;
  stop_reason: string;
  is_reasoning_turn: boolean;
  has_thinking: boolean;
  tool_calls: { tool_name: string; tool_use_id: string }[];
  dedup_siblings: number;
}

interface ModelInfo { model: string; call_count: number; input: number; output: number; cache_read: number; cache_write: number; cost_usd: number }
interface ToolInfo { tool: string; calls: number; category: string }
interface AgentInfo { agent_id: string; tokens: number; cost_usd: number; llm_call_count: number }

interface Summary {
  session_id: string;
  source: string;
  project_path: string;
  started_at: string;
  ended_at: string;
  turn_count: number;
  llm_call_count: number;
  tool_call_count: number;
  token_usage: { input: number; output: number; cache_read: number; cache_write: number; total: number; subagent_total: number; grand_total: number };
  cost: { total_usd: number; parent_usd: number; subagent_usd: number; by_model: Record<string, number> };
  by_model: ModelInfo[];
  by_skill: { skill: string; turns: number; tokens: number; cost_usd: number }[];
  top_tools: ToolInfo[];
  reasoning_vs_tools: { reasoning_pct: number; reasoning_tokens: number; reasoning_turns: number; tool_inv_tokens: number; tool_inv_turns: number };
  subagents: { count: number; total_tokens: number; total_cost_usd: number; agents: AgentInfo[] };
  top_turns_by_cost: { turn_id: string; prompt: string; tokens: number; cost_usd: number; timestamp: string }[];
}

function fmt(n: number) { return n.toLocaleString(); }
function fmtCost(n: number) { return `$${n < 0.01 && n > 0 ? n.toFixed(4) : n.toFixed(2)}`; }
function fmtTime(ts: string) { if (!ts) return "—"; try { return new Date(ts).toLocaleString(); } catch { return ts; } }
function duration(start: string, end: string) {
  if (!start || !end) return "—";
  const ms = new Date(end).getTime() - new Date(start).getTime();
  if (ms < 60000) return `${Math.round(ms / 1000)}s`;
  return `${Math.round(ms / 60000)} min`;
}

function Bar({ pct }: { pct: number }) {
  return (
    <div className="w-full bg-surface-warm rounded-full h-2">
      <div className="bg-foreground h-2 rounded-full transition-all" style={{ width: `${Math.min(pct, 100)}%` }} />
    </div>
  );
}

function HBar({ items }: { items: { label: string; value: number; display: string }[] }) {
  const max = Math.max(...items.map(i => i.value), 1);
  return (
    <div className="space-y-2.5">
      {items.map(item => (
        <div key={item.label}>
          <div className="flex justify-between text-xs mb-0.5">
            <span className="font-mono truncate max-w-[180px]">{item.label}</span>
            <span className="font-mono text-muted shrink-0 ml-2">{item.display}</span>
          </div>
          <Bar pct={(item.value / max) * 100} />
        </div>
      ))}
    </div>
  );
}

function Card({ title, children, className = "" }: { title: string; children: React.ReactNode; className?: string }) {
  return (
    <div className={`bg-surface receipt-shadow rounded p-5 ${className}`}>
      <p className="text-xs text-muted uppercase tracking-wider mb-4">{title}</p>
      {children}
    </div>
  );
}

export default function SessionPage() {
  const { id } = useParams<{ id: string }>();
  const [data, setData] = useState<{ summary: Summary; turns: Turn[]; calls: LLMCall[] } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [expandedTurn, setExpandedTurn] = useState<string | null>(null);

  useEffect(() => {
    fetch(`/api/sessions/${id}`)
      .then(r => { if (!r.ok) throw new Error("Not found"); return r.json(); })
      .then(setData)
      .catch(e => setError(e.message));
  }, [id]);

  if (error) return <div className="max-w-4xl mx-auto px-6 py-16"><p className="text-muted">Session not found.</p></div>;
  if (!data) return <div className="max-w-4xl mx-auto px-6 py-16"><p className="text-muted">Loading...</p></div>;

  const { summary: s, turns, calls } = data;
  const maxTurnCost = Math.max(...turns.map(t => t.cost.total_usd), 0.001);
  const callsByTurn: Record<string, LLMCall[]> = {};
  for (const c of calls) {
    (callsByTurn[c.turn_id] ||= []).push(c);
  }

  const cacheHitRate = s.token_usage.total > 0
    ? Math.round((s.token_usage.cache_read / s.token_usage.total) * 100)
    : 0;

  return (
    <div className="max-w-6xl mx-auto px-6 py-12">
      <Link href="/dashboard" className="text-xs text-muted hover:text-foreground mb-4 inline-block">&larr; Dashboard</Link>

      {/* Header */}
      <div className="flex flex-wrap items-baseline gap-4 mb-2">
        <h1 className="text-2xl font-bold font-mono">{s.session_id.slice(0, 12)}...</h1>
        <span className="text-xs px-2 py-0.5 bg-foreground text-surface rounded">{s.source}</span>
      </div>
      {s.project_path && <p className="text-xs text-muted font-mono mb-1">{s.project_path}</p>}
      <p className="text-xs text-muted mb-8">
        {fmtTime(s.started_at)} &mdash; {fmtTime(s.ended_at)} &middot; Duration: {duration(s.started_at, s.ended_at)}
      </p>

      {/* Overview stat cards — 2 rows */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3 mb-4">
        {[
          ["Total Cost", fmtCost(s.cost.total_usd)],
          ["Total Tokens", fmt(s.token_usage.grand_total)],
          ["Turns", String(s.turn_count)],
          ["LLM Calls", String(s.llm_call_count)],
          ["Tool Calls", String(s.tool_call_count)],
        ].map(([label, value]) => (
          <div key={label} className="bg-surface receipt-shadow rounded px-4 py-3">
            <p className="text-[10px] text-muted uppercase tracking-wider">{label}</p>
            <p className="text-lg font-bold font-mono mt-0.5">{value}</p>
          </div>
        ))}
      </div>
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3 mb-10">
        {[
          ["Input Tokens", fmt(s.token_usage.input)],
          ["Output Tokens", fmt(s.token_usage.output)],
          ["Cache Read", fmt(s.token_usage.cache_read)],
          ["Cache Write", fmt(s.token_usage.cache_write)],
          ["Cache Hit Rate", `${cacheHitRate}%`],
        ].map(([label, value]) => (
          <div key={label} className="bg-surface receipt-shadow rounded px-4 py-3">
            <p className="text-[10px] text-muted uppercase tracking-wider">{label}</p>
            <p className="text-base font-bold font-mono mt-0.5">{value}</p>
          </div>
        ))}
      </div>

      {/* 2-column detail grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-10">

        {/* Model breakdown with token detail */}
        <Card title="By Model">
          {(s.by_model || []).map(m => (
            <div key={m.model} className="mb-4 last:mb-0">
              <div className="flex justify-between text-sm mb-1">
                <span className="font-mono text-xs">{m.model}</span>
                <span className="font-mono text-xs font-medium">{fmtCost(m.cost_usd)}</span>
              </div>
              <Bar pct={(m.cost_usd / (s.cost.total_usd || 1)) * 100} />
              <div className="flex gap-3 mt-1 text-[10px] text-muted">
                <span>{fmt(m.input)} in</span>
                <span>{fmt(m.output)} out</span>
                <span>{fmt(m.cache_read || 0)} cached</span>
                <span>{m.call_count} calls</span>
              </div>
            </div>
          ))}
        </Card>

        {/* Top tools with bars */}
        <Card title="Top Tools">
          <HBar items={(s.top_tools || []).slice(0, 12).map(t => ({
            label: t.tool,
            value: t.calls,
            display: `${t.calls} calls`
          }))} />
        </Card>

        {/* Token breakdown pie-like bar */}
        <Card title="Token Breakdown">
          <div className="flex h-6 rounded-full overflow-hidden mb-3">
            <div className="bg-foreground" style={{ width: `${(s.token_usage.input / (s.token_usage.grand_total || 1)) * 100}%` }} title="Input" />
            <div className="bg-foreground/60" style={{ width: `${(s.token_usage.output / (s.token_usage.grand_total || 1)) * 100}%` }} title="Output" />
            <div className="bg-foreground/30" style={{ width: `${(s.token_usage.cache_read / (s.token_usage.grand_total || 1)) * 100}%` }} title="Cache Read" />
            <div className="bg-foreground/15" style={{ width: `${(s.token_usage.cache_write / (s.token_usage.grand_total || 1)) * 100}%` }} title="Cache Write" />
          </div>
          <div className="grid grid-cols-2 gap-2 text-xs">
            <div className="flex items-center gap-2"><div className="w-3 h-3 rounded bg-foreground" /><span>Input: {fmt(s.token_usage.input)} ({Math.round((s.token_usage.input / (s.token_usage.grand_total || 1)) * 100)}%)</span></div>
            <div className="flex items-center gap-2"><div className="w-3 h-3 rounded bg-foreground/60" /><span>Output: {fmt(s.token_usage.output)} ({Math.round((s.token_usage.output / (s.token_usage.grand_total || 1)) * 100)}%)</span></div>
            <div className="flex items-center gap-2"><div className="w-3 h-3 rounded bg-foreground/30" /><span>Cache Read: {fmt(s.token_usage.cache_read)}</span></div>
            <div className="flex items-center gap-2"><div className="w-3 h-3 rounded bg-foreground/15 border border-border" /><span>Cache Write: {fmt(s.token_usage.cache_write)}</span></div>
          </div>
        </Card>

        {/* Reasoning vs Tools */}
        <Card title="Reasoning vs Tool Invocation">
          <div className="flex h-5 rounded-full overflow-hidden mb-2">
            <div className="bg-foreground" style={{ width: `${s.reasoning_vs_tools.reasoning_pct}%` }} />
            <div className="bg-foreground/25 flex-1" />
          </div>
          <div className="flex justify-between text-xs text-muted mb-4">
            <span>Reasoning {s.reasoning_vs_tools.reasoning_pct}%</span>
            <span>Tool invocation {100 - s.reasoning_vs_tools.reasoning_pct}%</span>
          </div>
          <div className="grid grid-cols-2 gap-4 text-xs">
            <div>
              <p className="text-muted mb-1">Reasoning</p>
              <p className="font-mono">{fmt(s.reasoning_vs_tools.reasoning_tokens || 0)} tokens</p>
              <p className="font-mono">{s.reasoning_vs_tools.reasoning_turns || 0} turns</p>
            </div>
            <div>
              <p className="text-muted mb-1">Tool Invocation</p>
              <p className="font-mono">{fmt(s.reasoning_vs_tools.tool_inv_tokens || 0)} tokens</p>
              <p className="font-mono">{s.reasoning_vs_tools.tool_inv_turns || 0} turns</p>
            </div>
          </div>
        </Card>

        {/* By Skill */}
        {(s.by_skill || []).length > 0 && (
          <Card title="By Skill">
            <div className="space-y-2">
              {s.by_skill.map(sk => (
                <div key={sk.skill} className="flex justify-between items-center text-sm">
                  <div>
                    <span className="font-mono text-xs">{sk.skill}</span>
                    <span className="text-[10px] text-muted ml-2">{sk.turns} turns</span>
                  </div>
                  <div className="text-right">
                    <span className="font-mono text-xs">{fmtCost(sk.cost_usd)}</span>
                    <span className="text-[10px] text-muted ml-2">{fmt(sk.tokens)} tok</span>
                  </div>
                </div>
              ))}
            </div>
          </Card>
        )}

        {/* Subagents */}
        {s.subagents.count > 0 && (
          <Card title={`Subagents (${s.subagents.count})`}>
            <div className="flex gap-6 text-sm mb-4">
              <div><p className="text-[10px] text-muted">Total Tokens</p><p className="font-mono font-medium">{fmt(s.subagents.total_tokens)}</p></div>
              <div><p className="text-[10px] text-muted">Total Cost</p><p className="font-mono font-medium">{fmtCost(s.subagents.total_cost_usd)}</p></div>
            </div>
            <div className="space-y-2">
              {(s.subagents.agents || []).map(a => (
                <div key={a.agent_id} className="flex justify-between text-xs border-b border-border/30 pb-1.5">
                  <span className="font-mono">{a.agent_id.slice(0, 12)}</span>
                  <div className="flex gap-3 text-muted">
                    <span>{fmt(a.tokens)} tok</span>
                    <span>{a.llm_call_count} calls</span>
                    <span className="font-medium text-foreground">{fmtCost(a.cost_usd)}</span>
                  </div>
                </div>
              ))}
            </div>
          </Card>
        )}

        {/* Most Expensive Turns */}
        {(s.top_turns_by_cost || []).length > 0 && (
          <Card title="Most Expensive Turns" className="lg:col-span-2">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b border-border text-muted">
                  <th className="text-left pb-2 pr-4">Prompt</th>
                  <th className="text-right pb-2 pr-4">Tokens</th>
                  <th className="text-right pb-2 pr-4">Cost</th>
                  <th className="text-right pb-2">Time</th>
                </tr>
              </thead>
              <tbody>
                {s.top_turns_by_cost.slice(0, 8).map((t, i) => (
                  <tr key={i} className="border-b border-border/30">
                    <td className="py-2 pr-4 truncate max-w-[300px]">{t.prompt || "(empty)"}</td>
                    <td className="py-2 pr-4 text-right font-mono">{fmt(t.tokens)}</td>
                    <td className="py-2 pr-4 text-right font-mono font-medium">{fmtCost(t.cost_usd)}</td>
                    <td className="py-2 text-right text-muted">{t.timestamp?.slice(11, 19) || "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Card>
        )}
      </div>

      {/* Turn-by-turn detail */}
      <div>
        <p className="text-xs text-muted uppercase tracking-wider mb-4">Turns ({turns.length})</p>
        <div className="space-y-2">
          {turns.map(t => {
            const turnCalls = callsByTurn[t.turn_id] || [];
            const isExpanded = expandedTurn === t.turn_id;
            return (
              <div key={t.turn_id} className="bg-surface receipt-shadow rounded">
                <button
                  onClick={() => setExpandedTurn(isExpanded ? null : t.turn_id)}
                  className="w-full text-left px-4 py-3 hover:bg-surface-warm/30 transition-colors"
                >
                  <div className="flex items-start justify-between gap-4">
                    <div className="flex-1 min-w-0">
                      <p className="text-sm">
                        {t.is_skill && <span className="text-[10px] bg-foreground/10 px-1 rounded mr-1 font-mono">/{t.skill_name}</span>}
                        <span className="truncate inline-block max-w-[400px] align-bottom">{t.user_prompt || "(empty)"}</span>
                      </p>
                      <div className="flex flex-wrap gap-x-4 gap-y-0.5 mt-1 text-[10px] text-muted">
                        <span>{fmt(t.token_usage.input)} in / {fmt(t.token_usage.output)} out</span>
                        <span>{fmt(t.token_usage.cache_read)} cached</span>
                        <span>{t.tools_summary.total_calls} tools</span>
                        <span>{t.llm_call_count} LLM calls</span>
                        <span>{t.timestamp?.slice(11, 19)}</span>
                      </div>
                    </div>
                    <div className="text-right shrink-0 w-24">
                      <p className="font-mono text-xs font-medium">{fmtCost(t.cost.total_usd)}</p>
                      <div className="mt-1"><Bar pct={(t.cost.total_usd / maxTurnCost) * 100} /></div>
                      <p className="text-[9px] text-muted mt-0.5">{fmt(t.token_usage.total)} tok</p>
                    </div>
                  </div>
                </button>

                {/* Expanded: show LLM calls and tool breakdown */}
                {isExpanded && (
                  <div className="border-t border-border/50 px-4 py-3 bg-surface-warm/20">
                    {/* Tool breakdown for this turn */}
                    {Object.keys(t.tools_summary.by_tool).length > 0 && (
                      <div className="mb-3">
                        <p className="text-[10px] text-muted uppercase tracking-wider mb-1">Tools Used</p>
                        <div className="flex flex-wrap gap-2">
                          {Object.entries(t.tools_summary.by_tool).sort(([,a],[,b]) => b - a).map(([name, count]) => (
                            <span key={name} className="text-[10px] bg-foreground/8 px-2 py-0.5 rounded font-mono">
                              {name} x{count}
                            </span>
                          ))}
                        </div>
                      </div>
                    )}

                    {/* LLM calls table */}
                    {turnCalls.length > 0 && (
                      <div>
                        <p className="text-[10px] text-muted uppercase tracking-wider mb-1">LLM Calls ({turnCalls.length})</p>
                        <table className="w-full text-[10px]">
                          <thead>
                            <tr className="text-muted border-b border-border/30">
                              <th className="text-left pb-1 pr-2">Model</th>
                              <th className="text-right pb-1 pr-2">Input</th>
                              <th className="text-right pb-1 pr-2">Output</th>
                              <th className="text-right pb-1 pr-2">Cached</th>
                              <th className="text-right pb-1 pr-2">Cost</th>
                              <th className="text-left pb-1 pr-2">Stop</th>
                              <th className="text-right pb-1">Tools</th>
                            </tr>
                          </thead>
                          <tbody>
                            {turnCalls.map((c, i) => (
                              <tr key={i} className="border-b border-border/15">
                                <td className="py-1 pr-2 font-mono">{c.model_short || c.model}</td>
                                <td className="py-1 pr-2 text-right font-mono">{fmt(c.usage.input_tokens)}</td>
                                <td className="py-1 pr-2 text-right font-mono">{fmt(c.usage.output_tokens)}</td>
                                <td className="py-1 pr-2 text-right font-mono">{fmt(c.usage.cache_read_input_tokens)}</td>
                                <td className="py-1 pr-2 text-right font-mono font-medium">{fmtCost(c.cost_usd)}</td>
                                <td className="py-1 pr-2">
                                  <span className={`px-1 rounded ${c.is_reasoning_turn ? 'bg-foreground/10' : 'bg-foreground/5'}`}>
                                    {c.stop_reason}
                                  </span>
                                </td>
                                <td className="py-1 text-right">{c.tool_calls?.length || 0}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    )}

                    {turnCalls.length === 0 && (
                      <p className="text-[10px] text-muted">No LLM call detail available for this turn.</p>
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
