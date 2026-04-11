#!/bin/zsh

_copilot_nl_fd=""
_copilot_nl_child_pid=""
_copilot_nl_prev_query=""

_COPILOT_NL_SYSTEM_PROMPT='Translate this description into a single shell command. Output ONLY the raw command. Never use backticks, code fences, markdown, or quotes. Never explain.'

# Cancel pending NL request
_copilot_nl_cancel() {
    if [[ -n "$_copilot_nl_child_pid" ]]; then
        kill -TERM -$_copilot_nl_child_pid 2>/dev/null
        _copilot_nl_child_pid=""
    fi
    if [[ -n "$_copilot_nl_fd" ]]; then
        zle -F "$_copilot_nl_fd" 2>/dev/null
        exec {_copilot_nl_fd}<&- 2>/dev/null
        _copilot_nl_fd=""
    fi
}

# Callback when NL response arrives
_copilot_nl_response() {
    local fd="$1"
    local raw=""
    IFS='' read -rd '' -u $fd raw

    zle -F "$fd"
    exec {fd}<&-
    _copilot_nl_fd=""
    _copilot_nl_child_pid=""

    [[ -z "$raw" ]] && return

    local result
    result=$(printf '%s' "$raw" | command python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('response', '').strip(), end='')
except: pass
" 2>/dev/null)

    if [[ -n "$result" ]]; then
        BUFFER="$result"
        CURSOR=${#BUFFER}
        POSTDISPLAY=""
        region_highlight=()
        _copilot_prev_buffer="$BUFFER"
        zle -R
    fi
}

# Ctrl+K: translate natural language to command
_copilot_nl_translate() {
    local query="$BUFFER"
    [[ -z "$query" ]] && return

    _copilot_nl_prev_query="$query"
    _copilot_nl_cancel
    _copilot_cancel  # also cancel inline completion

    local escaped=$(_copilot_json_escape "$query")
    local escaped_sys=$(_copilot_json_escape "$_COPILOT_NL_SYSTEM_PROMPT")
    local url="${OLLAMA_URL:-http://localhost:11434}"
    local model="${OLLAMA_MODEL:-cli-copilot}"

    exec {_copilot_nl_fd}< <(
        curl -s --connect-timeout 5 "${url}/api/generate" \
            -d "{\"model\":\"${model}\",\"system\":\"${escaped_sys}\",\"prompt\":\"${escaped}\",\"stream\":false,\"keep_alive\":\"30s\",\"options\":{\"num_predict\":200,\"stop\":[\"\\n\"],\"temperature\":0.0,\"num_ctx\":2048}}" \
            2>/dev/null
    )
    _copilot_nl_child_pid=$!

    zle -F "$_copilot_nl_fd" _copilot_nl_response
}

# Ctrl+Z: undo NL translation
_copilot_nl_undo() {
    if [[ -n "$_copilot_nl_prev_query" ]]; then
        BUFFER="$_copilot_nl_prev_query"
        CURSOR=${#BUFFER}
        _copilot_nl_prev_query=""
        POSTDISPLAY=""
        region_highlight=()
        _copilot_prev_buffer="$BUFFER"
        zle -R
    fi
}

zle -N _copilot_nl_translate_widget _copilot_nl_translate
zle -N _copilot_nl_undo_widget _copilot_nl_undo
bindkey "${NL_HOTKEY:-^K}" _copilot_nl_translate_widget
bindkey "${NL_UNDO_KEY:-^Z}" _copilot_nl_undo_widget
