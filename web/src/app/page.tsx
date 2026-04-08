function ReceiptCard() {
  return (
    <div className="bg-surface receipt-shadow rounded max-w-[320px] w-full font-receipt text-sm">
      <div className="h-3 bg-[repeating-linear-gradient(90deg,transparent,transparent_4px,var(--surface)_4px,var(--surface)_8px)] rounded-t" />
      <div className="px-6 pt-6 pb-5 text-center">
        <p className="text-lg font-bold tracking-[0.3em] text-foreground">COSTEA</p>
        <p className="text-[10px] text-muted mt-1 tracking-[0.2em] uppercase">Agent Cost Receipt</p>
        <p className="text-[10px] text-muted-light mt-0.5">2026-03-25 14:32:07</p>
        <div className="receipt-dash my-4" />
        <div className="text-left">
          <p className="text-[10px] text-muted uppercase tracking-wider">Task</p>
          <p className="text-xs text-foreground mt-0.5 leading-snug">Refactor the auth module</p>
        </div>
        <div className="receipt-dash my-4" />
        <div className="space-y-1.5 text-[11px]">
          {[["Input tokens", "12,400"], ["Output tokens", "5,800"], ["Tool calls", "14"], ["Similar tasks matched", "3"], ["Est. runtime", "~2 min"]].map(([l, v]) => (
            <div key={l} className="flex justify-between"><span className="text-muted">{l}</span><span className="text-foreground">{v}</span></div>
          ))}
        </div>
        <div className="receipt-dash my-4" />
        <p className="text-[10px] text-muted uppercase tracking-wider text-left mb-2">Provider Estimates</p>
        <div className="space-y-1 text-[11px]">
          {[["Claude Sonnet 4", "$0.38"], ["GPT-4o", "$0.54"], ["Gemini 2.5 Pro", "$0.29"]].map(([n, c]) => (
            <div key={n} className="flex justify-between"><span className="text-foreground/70">{n}</span><span className="text-foreground">{c}</span></div>
          ))}
        </div>
        <div className="receipt-double my-4" />
        <div className="flex justify-between items-baseline">
          <span className="text-xs font-bold text-foreground uppercase tracking-wider">Estimated Total</span>
          <span className="text-xl font-bold text-foreground">$0.38</span>
        </div>
        <p className="text-[10px] text-muted-light text-right mt-0.5">best price: Gemini 2.5 Pro</p>
        <div className="receipt-dash my-4" />
        <div className="flex justify-between text-[11px]">
          <span className="text-muted">Confidence</span>
          <span className="text-foreground font-bold">96%</span>
        </div>
        <div className="receipt-dash my-4" />
        <div className="bg-surface-warm -mx-6 px-6 py-3">
          <p className="text-xs text-foreground">Proceed? <span className="font-bold">[Y/N]</span><span className="inline-block w-[6px] h-[13px] bg-foreground animate-pulse align-middle ml-1" /></p>
        </div>
        <p className="text-[9px] text-muted-light mt-4 tracking-wide">POWERED BY /COSTEA SKILL</p>
        <p className="text-[9px] text-muted-light mt-0.5">THANK YOU FOR BEING COST-CONSCIOUS</p>
        <div className="flex justify-center gap-[2px] mt-3">
          {[3,1,2,1,3,2,1,1,3,1,2,3,1,2,1,1,3,2,1,3,1,2,1,3,2,1,1,2,3,1].map((w, i) => (
            <div key={i} className="bg-foreground" style={{ width: `${w}px`, height: "20px" }} />
          ))}
        </div>
      </div>
      <div className="h-3 bg-[repeating-linear-gradient(90deg,transparent,transparent_4px,var(--surface)_4px,var(--surface)_8px)] rounded-b" />
    </div>
  );
}

function CodeBlock({ children }: { children: string }) {
  return (
    <pre className="bg-surface-warm rounded px-4 py-3 text-sm font-mono text-foreground overflow-x-auto">
      <code>{children}</code>
    </pre>
  );
}

export default function Home() {
  return (
    <div className="max-w-6xl mx-auto px-6 py-16">
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 items-start">
        <div>
          <h1 className="text-5xl md:text-6xl font-serif italic font-light leading-tight text-foreground">
            cost prediction<br />for ai agents
          </h1>

          <div className="mt-12">
            <p className="text-xs text-muted uppercase tracking-[0.15em] mb-3">What is Costea</p>
            <p className="text-base text-foreground/80 leading-relaxed max-w-lg">
              A set of AI agent skills that track, analyze, and estimate token consumption across Claude Code, Codex CLI, and OpenClaw.<br />
              Estimate costs <em>before</em> execution, review spending <em>after</em>.
            </p>
          </div>

          <div className="mt-12">
            <p className="text-xs text-muted uppercase tracking-[0.15em] mb-3">Install</p>
            <div className="space-y-3">
              <CodeBlock>npx @asklv/costea</CodeBlock>
              <CodeBlock>{`ln -s /path/to/costea/skills/costea\n  ~/.claude/skills/costea`}</CodeBlock>
            </div>
            <a href="https://github.com/memovai/costea" target="_blank" rel="noopener noreferrer"
              className="inline-block mt-4 px-4 py-2 border border-foreground rounded text-sm font-medium hover:bg-foreground hover:text-surface transition-colors">
              GitHub &rarr;
            </a>
          </div>

          <div className="mt-12">
            <p className="text-xs text-muted uppercase tracking-[0.15em] mb-3">Skills</p>
            <div className="space-y-4">
              <div>
                <p className="font-bold text-foreground">/costea</p>
                <p className="text-sm text-foreground/70">Estimates the token cost of a task <em>before</em> running it, then asks for your confirmation.</p>
              </div>
              <div>
                <p className="font-bold text-foreground">/costeamigo</p>
                <p className="text-sm text-foreground/70">Generates a multi-dimensional report of your historical token spending across all platforms.</p>
              </div>
            </div>
          </div>

          <div className="mt-12">
            <p className="text-xs text-muted uppercase tracking-[0.15em] mb-3">Usage</p>
            <div className="space-y-2">
              <CodeBlock>costea refactor the auth module</CodeBlock>
              <CodeBlock>{`costeamigo all\ncosteamigo claude\ncosteamigo codex`}</CodeBlock>
            </div>
          </div>

          <div className="mt-12">
            <p className="text-xs text-muted uppercase tracking-[0.15em] mb-3">Platforms</p>
            <div className="flex gap-6 text-sm text-foreground/70">
              <span>Claude Code</span>
              <span>Codex CLI</span>
              <span>OpenClaw</span>
            </div>
          </div>
        </div>

        <div className="flex justify-center lg:justify-end lg:sticky lg:top-24">
          <ReceiptCard />
        </div>
      </div>

      <div className="mt-24 border-t border-border pt-12">
        <p className="text-xs text-muted uppercase tracking-[0.15em] mb-6">How It Works</p>
        <pre className="bg-surface-warm rounded px-6 py-5 text-xs font-mono text-foreground/80 overflow-x-auto leading-relaxed">
{`Session JSONL (3 platforms)
      ↓  parse-claudecode.sh / parse-codex.sh / parse-openclaw.sh
~/.costea/sessions/{id}/
  session.jsonl · llm-calls.jsonl · tools.jsonl · agents.jsonl
      ↓  summarize-session.sh
summary.json
      ↓
  ┌───┴───┐
  ↓       ↓
/costea  /costeamigo
receipt  historical
+ Y/N    report`}
        </pre>
      </div>

      <div className="mt-16 border-t border-border pt-12">
        <p className="text-xs text-muted uppercase tracking-[0.15em] mb-6">Provider Pricing</p>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border text-left text-muted text-xs uppercase tracking-wider">
                <th className="pb-3 pr-8">Provider</th>
                <th className="pb-3 pr-8">Input ($/M)</th>
                <th className="pb-3">Output ($/M)</th>
              </tr>
            </thead>
            <tbody className="text-foreground/80">
              {[["Claude Opus 4.6","$5","$25"],["Claude Sonnet 4.6","$3","$15"],["Claude Haiku 4.5","$1","$5"],["GPT-5.4","$2.50","$15"],["GPT-5.2 Codex","$1.07","$8.50"],["Gemini 2.5 Pro","$1.25","$5"],["Gemini 2.5 Flash","$0.15","$0.60"]].map(([n, i, o]) => (
                <tr key={n} className="border-b border-border/50">
                  <td className="py-2.5 pr-8 font-medium">{n}</td>
                  <td className="py-2.5 pr-8 font-mono text-xs">{i}</td>
                  <td className="py-2.5 font-mono text-xs">{o}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
