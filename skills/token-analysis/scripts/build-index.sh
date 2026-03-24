#!/usr/bin/env bash
set -euo pipefail

# Costea: Build task index from session JSONL files
# Supports: OpenClaw, Claude Code, Codex CLI
# Output: ~/.costea/task-index.json

COSTEA_DIR="$HOME/.costea"
INDEX_FILE="$COSTEA_DIR/task-index.json"

# Source directories
OPENCLAW_SESSIONS="${OPENCLAW_SESSIONS_DIR:-$HOME/.openclaw/agents/main/sessions}"
CLAUDE_PROJECTS="$HOME/.claude/projects"
CODEX_SESSIONS="$HOME/.codex/sessions"

mkdir -p "$COSTEA_DIR"

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install with: brew install jq" >&2
  exit 1
fi

all_tasks="[]"
sessions_scanned=0

merge_tasks() {
  local new_tasks="$1"
  if [[ -n "$new_tasks" && "$new_tasks" != "[]" && "$new_tasks" != "null" ]]; then
    all_tasks=$(echo "$all_tasks" "$new_tasks" | jq -s '.[0] + .[1]')
  fi
}

# ─────────────────────────────────────────────
# OpenClaw: ~/.openclaw/agents/main/sessions/
# Format: type:"message", message.role, message.usage, message.content[].type=="toolCall"
# ─────────────────────────────────────────────
process_openclaw() {
  local sessions_json="$OPENCLAW_SESSIONS/sessions.json"
  [[ ! -f "$sessions_json" ]] && return

  echo "  Scanning OpenClaw..." >&2

  while IFS=$'\t' read -r sid model; do
    local jsonl_file="$OPENCLAW_SESSIONS/${sid}.jsonl"
    [[ ! -f "$jsonl_file" ]] && continue
    sessions_scanned=$((sessions_scanned + 1))

    local tasks
    tasks=$(jq -s --arg sid "$sid" --arg smodel "$model" '
      [.[] | select(.type == "message")] |
      reduce .[] as $msg ({ tasks: [], current_task: null };
        if $msg.message.role == "user" then
          (if .current_task then .tasks + [.current_task] else .tasks end) as $ut |
          { tasks: $ut, current_task: {
            session_id: $sid, model: $smodel, source: "openclaw",
            user_message: ([$msg.message.content[]? | select(.type == "text") | .text] | join("\n") |
              gsub("Conversation info \\(untrusted metadata\\):\n```json\n[^`]*```\n\n"; "") |
              gsub("Sender \\(untrusted metadata\\):\n```json\n[^`]*```\n\n"; "") |
              gsub("^\\s+|\\s+$"; "")),
            timestamp: $msg.timestamp,
            assistant_messages: [], tool_results: []
          }}
        elif $msg.message.role == "assistant" and .current_task then
          .current_task.assistant_messages += [$msg.message] | .
        elif $msg.message.role == "toolResult" and .current_task then
          .current_task.tool_results += [$msg.message] | .
        else . end
      ) |
      (if .current_task then .tasks + [.current_task] else .tasks end) |
      map(
        (.user_message | test("^Use the \"[^\"]+\" skill for this request\\.")) as $is_skill |
        (if $is_skill then .user_message | capture("^Use the \"(?<name>[^\"]+)\" skill") | .name else null end) as $skill_name |
        (if $is_skill then .user_message | gsub("^Use the \"[^\"]+\" skill for this request\\.\\s*"; "") | gsub("^User input:\\s*"; "") | gsub("^\\s+|\\s+$"; "")
         else .user_message end) as $prompt |
        (.assistant_messages | map(select(.usage != null))) as $um |
        {
          source: "openclaw", session_id: .session_id,
          model: (.assistant_messages[0].model // .model), provider: (.assistant_messages[0].provider // "openclaw"),
          timestamp: .timestamp, is_skill: $is_skill, skill_name: $skill_name,
          user_prompt: $prompt,
          token_usage: {
            input: ([$um[].usage.input // 0] | add // 0),
            output: ([$um[].usage.output // 0] | add // 0),
            cache_read: ([$um[].usage.cacheRead // 0] | add // 0),
            cache_write: ([$um[].usage.cacheWrite // 0] | add // 0),
            total: ([$um[].usage.totalTokens // 0] | add // 0)
          },
          cost: { total: ([$um[].usage.cost.total // 0] | add // 0) },
          tools: ([$um[] | .content[]? | select(.type == "toolCall") | .name] | group_by(.) | map({name: .[0], count: length}) | sort_by(-.count)),
          total_tool_calls: ([$um[] | .content[]? | select(.type == "toolCall")] | length),
          assistant_message_count: ($um | length),
          tool_result_count: (.tool_results | length),
          reasoning: {
            tokens: ([$um[] | select(.stopReason == "stop") | .usage.totalTokens // 0] | add // 0),
            count: ([$um[] | select(.stopReason == "stop")] | length)
          },
          tool_invocation: {
            tokens: ([$um[] | select(.stopReason == "toolUse") | .usage.totalTokens // 0] | add // 0),
            count: ([$um[] | select(.stopReason == "toolUse")] | length)
          }
        }
      ) | map(select(.assistant_message_count > 0))
    ' "$jsonl_file" < /dev/null 2>/dev/null) || true

    merge_tasks "$tasks"
  done < <(jq -r 'to_entries[] | select(.value.sessionId != null) | .value | [.sessionId, (.model // "unknown")] | @tsv' "$sessions_json")
}

# ─────────────────────────────────────────────
# Claude Code: ~/.claude/projects/<project>/<session>.jsonl
# Format: type:"user"|"assistant", message.usage.{input_tokens,output_tokens,cache_read_input_tokens,cache_creation_input_tokens}
#         tool_use in message.content[].type=="tool_use", stop_reason:"tool_use"|"end_turn"
#         Subagents in <session>/subagents/agent-*.jsonl (separate files)
# ─────────────────────────────────────────────
process_claude_code() {
  [[ ! -d "$CLAUDE_PROJECTS" ]] && return

  echo "  Scanning Claude Code..." >&2

  # Find all session JSONL files (skip subagent files)
  while IFS= read -r jsonl_file; do
    [[ ! -f "$jsonl_file" ]] && continue
    local basename
    basename=$(basename "$jsonl_file" .jsonl)
    # Skip non-UUID filenames
    [[ ! "$basename" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] && continue

    sessions_scanned=$((sessions_scanned + 1))
    local sid="$basename"

    # Also scan subagent files for this session to get their token usage
    local subagent_tokens=0
    local subagent_dir
    subagent_dir="$(dirname "$jsonl_file")/${sid}/subagents"
    if [[ -d "$subagent_dir" ]]; then
      subagent_tokens=$(find "$subagent_dir" -name "agent-*.jsonl" -exec jq -c 'select(.type == "assistant") | .message.usage' {} + 2>/dev/null | \
        jq -s '[.[] | ((.input_tokens // 0) + (.output_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))] | add // 0' 2>/dev/null) || true
      subagent_tokens=${subagent_tokens:-0}
    fi

    local tasks
    tasks=$(jq -s --arg sid "$sid" --argjson sub_tokens "${subagent_tokens:-0}" '
      # Claude Code: type field is "user"/"assistant"/"system"/"progress"/etc
      [.[] | select(.type == "user" or .type == "assistant")] |

      reduce .[] as $msg ({ tasks: [], current_task: null };
        if $msg.type == "user" and ($msg.message.content | type) == "string" then
          # User text message (not tool_result which has array content)
          (if .current_task then .tasks + [.current_task] else .tasks end) as $ut |
          { tasks: $ut, current_task: {
            session_id: $sid, source: "claude-code",
            user_message: ($msg.message.content // ""),
            timestamp: $msg.timestamp,
            assistant_messages: []
          }}
        elif $msg.type == "assistant" and .current_task then
          .current_task.assistant_messages += [$msg] | .
        else . end
      ) |
      (if .current_task then .tasks + [.current_task] else .tasks end) |

      map(
        # Detect slash commands (Claude Code skills start with / in user message)
        (.user_message | test("^/[a-zA-Z]")) as $is_skill |
        (if $is_skill then .user_message | capture("^/(?<name>[a-zA-Z0-9_-]+)") | .name else null end) as $skill_name |
        (if $is_skill then .user_message | gsub("^/[a-zA-Z0-9_-]+\\s*"; "") else .user_message end) as $prompt |

        # Filter assistant messages with usage data
        (.assistant_messages | map(select(.message.usage != null))) as $um |

        {
          source: "claude-code", session_id: .session_id,
          model: ($um[0].message.model // "unknown"), provider: "anthropic",
          timestamp: .timestamp, is_skill: $is_skill, skill_name: $skill_name,
          user_prompt: $prompt,
          token_usage: {
            input: ([$um[].message.usage.input_tokens // 0] | add // 0),
            output: ([$um[].message.usage.output_tokens // 0] | add // 0),
            cache_read: ([$um[].message.usage.cache_read_input_tokens // 0] | add // 0),
            cache_write: ([$um[].message.usage.cache_creation_input_tokens // 0] | add // 0),
            total: ([$um[] | .message.usage | ((.input_tokens // 0) + (.output_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))] | add // 0),
            subagent_tokens: $sub_tokens
          },
          cost: {
            # Claude Code does not store per-message cost; will be estimated by LLM
            total: 0
          },
          tools: (
            [$um[] | .message.content[]? | select(.type == "tool_use") | .name] |
            group_by(.) | map({name: .[0], count: length}) | sort_by(-.count)
          ),
          total_tool_calls: ([$um[] | .message.content[]? | select(.type == "tool_use")] | length),
          assistant_message_count: ($um | length),
          tool_result_count: 0,
          reasoning: {
            tokens: ([$um[] | select(.message.stop_reason == "end_turn") | .message.usage | ((.input_tokens // 0) + (.output_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))] | add // 0),
            count: ([$um[] | select(.message.stop_reason == "end_turn")] | length)
          },
          tool_invocation: {
            tokens: ([$um[] | select(.message.stop_reason == "tool_use") | .message.usage | ((.input_tokens // 0) + (.output_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))] | add // 0),
            count: ([$um[] | select(.message.stop_reason == "tool_use")] | length)
          }
        }
      ) | map(select(.assistant_message_count > 0))
    ' "$jsonl_file" < /dev/null 2>/dev/null) || true

    merge_tasks "$tasks"
  done < <(find "$CLAUDE_PROJECTS" -maxdepth 2 -name "*.jsonl" -not -path "*/subagents/*" 2>/dev/null)
}

# ─────────────────────────────────────────────
# Codex CLI: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
# Format: type:"event_msg" with payload.type:"user_message"|"agent_message"|"token_count"
#         type:"response_item" with payload.type:"message"|"function_call"|"reasoning"
#         Token data in event_msg/token_count payload.info.total_token_usage
# ─────────────────────────────────────────────
process_codex() {
  [[ ! -d "$CODEX_SESSIONS" ]] && return

  echo "  Scanning Codex..." >&2

  while IFS= read -r jsonl_file; do
    [[ ! -f "$jsonl_file" ]] && continue
    sessions_scanned=$((sessions_scanned + 1))

    local sid
    sid=$(basename "$jsonl_file" .jsonl | sed 's/^rollout-//')

    local tasks
    tasks=$(jq -s --arg sid "$sid" '
      # Extract session metadata
      ((.[] | select(.type == "session_meta") | .payload) // {}) as $meta |

      # Extract user messages
      ([.[] | select(.type == "event_msg" and .payload.type == "user_message")] |
        map({ text: .payload.message, timestamp: .timestamp })) as $user_msgs |

      # Extract agent (assistant) messages
      ([.[] | select(.type == "event_msg" and .payload.type == "agent_message")] |
        map({ text: .payload.message, timestamp: .timestamp })) as $agent_msgs |

      # Extract token counts (last one has cumulative total)
      ([.[] | select(.type == "event_msg" and .payload.type == "token_count" and .payload.info != null)] |
        if length > 0 then last.payload.info.total_token_usage else null end) as $token_total |

      # Extract function calls from response_items
      ([.[] | select(.type == "response_item" and .payload.type == "function_call")] |
        map(.payload.name // "unknown")) as $tool_names |

      # Build tasks: for Codex, typically one user message per session = one task
      if ($user_msgs | length) == 0 then []
      else
        [$user_msgs | to_entries[] | {
          source: "codex", session_id: $sid,
          model: ($meta.model // "gpt-5.2-codex"), provider: "openai",
          timestamp: .value.timestamp,
          is_skill: false, skill_name: null,
          user_prompt: (.value.text[:500]),
          token_usage: (
            if $token_total then {
              input: ($token_total.input_tokens // 0),
              output: ($token_total.output_tokens // 0),
              cache_read: ($token_total.cached_input_tokens // 0),
              cache_write: 0,
              total: ($token_total.total_tokens // 0),
              reasoning_output: ($token_total.reasoning_output_tokens // 0)
            } else {
              input: 0, output: 0, cache_read: 0, cache_write: 0, total: 0
            } end
          ),
          cost: { total: 0 },
          tools: ($tool_names | group_by(.) | map({name: .[0], count: length}) | sort_by(-.count)),
          total_tool_calls: ($tool_names | length),
          assistant_message_count: ($agent_msgs | length),
          tool_result_count: 0,
          reasoning: {
            tokens: (if $token_total then ($token_total.reasoning_output_tokens // 0) else 0 end),
            count: (if ($token_total.reasoning_output_tokens // 0) > 0 then 1 else 0 end)
          },
          tool_invocation: {
            tokens: 0,
            count: ($tool_names | length)
          }
        }] | map(select(.assistant_message_count > 0 or .token_usage.total > 0))
      end
    ' "$jsonl_file" < /dev/null 2>/dev/null) || true

    merge_tasks "$tasks"
  done < <(find "$CODEX_SESSIONS" -name "rollout-*.jsonl" 2>/dev/null)
}

# ─────────────────────────────────────────────
# Main: scan all sources
# ─────────────────────────────────────────────
echo "Building task index..." >&2
process_openclaw
process_claude_code
process_codex

# Write index
jq -n \
  --argjson tasks "$all_tasks" \
  --argjson scanned "$sessions_scanned" \
  --arg built_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    tasks: ($tasks | sort_by(.timestamp) | reverse),
    built_at: $built_at,
    sessions_scanned: $scanned,
    task_count: ($tasks | length),
    total_tokens: ($tasks | map(.token_usage.total) | add // 0),
    total_cost: ($tasks | map(.cost.total) | add // 0),
    sources: ($tasks | group_by(.source) | map({source: .[0].source, count: length}) | sort_by(-.count))
  }' > "$INDEX_FILE"

echo "Index built: $INDEX_FILE" >&2
echo "  Sessions scanned: $sessions_scanned" >&2
echo "  Tasks found: $(echo "$all_tasks" | jq 'length')" >&2
echo "  Sources: $(echo "$all_tasks" | jq -r 'group_by(.source) | map("\(.[0].source):\(length)") | join(", ")')" >&2
