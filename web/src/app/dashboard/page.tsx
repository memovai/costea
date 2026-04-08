"use client";

import { useEffect, useState } from "react";
import Link from "next/link";

interface SessionEntry {
  session_id: string;
  source: string;
  project_path: string;
  started_at: string;
  total_tokens: number;
  total_cost_usd: number;
  turn_count: number;
  llm_call_count: number;
  tool_call_count: number;
}

interface IndexData {
  session_count: number;
  total_tokens: number;
  total_cost_usd: number;
  sources: { source: string; count: number }[];
  sessions: SessionEntry[];
}

function fmt(n: number) {
  return n.toLocaleString();
}

function fmtCost(n: number) {
  return `$${n < 0.01 ? n.toFixed(4) : n.toFixed(2)}`;
}

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-surface receipt-shadow rounded px-5 py-4">
      <p className="text-xs text-muted uppercase tracking-wider">{label}</p>
      <p className="text-2xl font-bold text-foreground mt-1 font-mono">{value}</p>
    </div>
  );
}

const SOURCE_COLORS: Record<string, string> = {
  "claude-code": "bg-foreground text-surface",
  codex: "bg-foreground/70 text-surface",
  openclaw: "bg-foreground/50 text-surface",
};

export default function DashboardPage() {
  const [data, setData] = useState<IndexData | null>(null);
  const [filter, setFilter] = useState<string>("all");
  const [sort, setSort] = useState<"cost" | "tokens" | "date">("date");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/sessions")
      .then((r) => {
        if (!r.ok) throw new Error("No data");
        return r.json();
      })
      .then(setData)
      .catch((e) => setError(e.message));
  }, []);

  if (error) {
    return (
      <div className="max-w-4xl mx-auto px-6 py-16">
        <h1 className="text-3xl font-bold mb-4">Dashboard</h1>
        <div className="bg-surface-warm rounded p-6 text-sm">
          <p className="font-bold mb-2">No data found</p>
          <p className="text-muted">Run the index builder first:</p>
          <pre className="mt-2 bg-surface rounded px-3 py-2 text-xs font-mono">
            bash ~/.claude/skills/costea/scripts/update-index.sh
          </pre>
        </div>
      </div>
    );
  }

  if (!data) {
    return (
      <div className="max-w-4xl mx-auto px-6 py-16">
        <p className="text-muted">Loading...</p>
      </div>
    );
  }

  const sessions = data.sessions
    .filter((s) => filter === "all" || s.source === filter)
    .sort((a, b) => {
      if (sort === "cost") return (b.total_cost_usd || 0) - (a.total_cost_usd || 0);
      if (sort === "tokens") return (b.total_tokens || 0) - (a.total_tokens || 0);
      return (b.started_at || "").localeCompare(a.started_at || "");
    });

  return (
    <div className="max-w-6xl mx-auto px-6 py-12">
      {/* Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-10">
        <StatCard label="Total Cost" value={fmtCost(data.total_cost_usd)} />
        <StatCard label="Total Tokens" value={fmt(data.total_tokens)} />
        <StatCard label="Sessions" value={fmt(data.session_count)} />
        <StatCard
          label="Platforms"
          value={data.sources.map((s) => s.source).join(", ")}
        />
      </div>

      {/* Filters */}
      <div className="flex items-center gap-4 mb-6">
        <div className="flex items-center gap-2">
          <span className="text-xs text-muted uppercase tracking-wider">Filter</span>
          <select
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            className="text-sm border border-border rounded px-2 py-1 bg-surface"
          >
            <option value="all">All platforms</option>
            <option value="claude-code">Claude Code</option>
            <option value="codex">Codex CLI</option>
            <option value="openclaw">OpenClaw</option>
          </select>
        </div>
        <div className="flex items-center gap-2">
          <span className="text-xs text-muted uppercase tracking-wider">Sort</span>
          <select
            value={sort}
            onChange={(e) => setSort(e.target.value as typeof sort)}
            className="text-sm border border-border rounded px-2 py-1 bg-surface"
          >
            <option value="date">Date (Recent)</option>
            <option value="cost">Cost (High)</option>
            <option value="tokens">Tokens (High)</option>
          </select>
        </div>
        <span className="text-xs text-muted ml-auto">
          {sessions.length} sessions
        </span>
      </div>

      {/* Session table */}
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border text-left text-xs text-muted uppercase tracking-wider">
              <th className="pb-3 pr-4">Session</th>
              <th className="pb-3 pr-4">Platform</th>
              <th className="pb-3 pr-4">Turns</th>
              <th className="pb-3 pr-4">Tokens</th>
              <th className="pb-3 pr-4">Cost</th>
              <th className="pb-3">Date</th>
            </tr>
          </thead>
          <tbody>
            {sessions.slice(0, 100).map((s) => (
              <tr key={s.session_id} className="border-b border-border/30 hover:bg-surface-warm/50 transition-colors">
                <td className="py-3 pr-4">
                  <Link
                    href={`/session/${s.session_id}`}
                    className="font-mono text-xs hover:underline"
                  >
                    {s.session_id.slice(0, 8)}...
                  </Link>
                  {s.project_path && (
                    <p className="text-[10px] text-muted mt-0.5 truncate max-w-[200px]">
                      {s.project_path.replace(/.*\//, "")}
                    </p>
                  )}
                </td>
                <td className="py-3 pr-4">
                  <span
                    className={`text-[10px] px-1.5 py-0.5 rounded ${SOURCE_COLORS[s.source] || "bg-muted text-surface"}`}
                  >
                    {s.source}
                  </span>
                </td>
                <td className="py-3 pr-4 font-mono text-xs">{s.turn_count}</td>
                <td className="py-3 pr-4 font-mono text-xs">{fmt(s.total_tokens)}</td>
                <td className="py-3 pr-4 font-mono text-xs font-medium">
                  {fmtCost(s.total_cost_usd)}
                </td>
                <td className="py-3 text-xs text-muted">
                  {s.started_at?.slice(0, 10) || "—"}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
