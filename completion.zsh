#!/bin/zsh

_copilot_fd=""
_copilot_child_pid=""
_copilot_suggestion=""
_copilot_correction=""
_copilot_prev_buffer=""
_copilot_last_exit=0

_COPILOT_SYSTEM_PROMPT='You are a shell command autocomplete engine. Given a partial command after "Complete this:", output the full completed command. CRITICAL: Your output MUST start with the EXACT text the user already typed. You are only appending to what they wrote. Output ONLY the raw command. Never use backticks, code fences, markdown, or quotes. Never explain. Single line only.'

# Track exit code
_copilot_precmd() { _copilot_last_exit=$?; }
autoload -U add-zsh-hook
add-zsh-hook precmd _copilot_precmd

# JSON-escape a string
_copilot_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# Build context prompt from live shell state
_copilot_build_prompt() {
    local buf="$1"
    local dir="$(pwd)"
    local depth="${CONTEXT_HISTORY_DEPTH:-10}"
    local hist="$(fc -l -n -"$depth" 2>/dev/null)"
    local files=""
    [[ "${CONTEXT_DIR_LISTING:-true}" == "true" ]] && files="$(command ls -1 2>/dev/null | head -20)"

    local git_info=""
    if command git rev-parse --is-inside-work-tree &>/dev/null; then
        local branch=$(command git branch --show-current 2>/dev/null)
        local status=$(command git status --short 2>/dev/null | head -5)
        git_info="Git: branch:${branch}"
        [[ -n "$status" ]] && git_info="${git_info} ${status}"
    fi

    local prompt="Directory: ${dir}"
    [[ -n "$git_info" ]] && prompt="${prompt}
${git_info}"
    [[ "$_copilot_last_exit" != "0" ]] && prompt="${prompt}
Last exit code: $_copilot_last_exit"
    prompt="${prompt}
Last commands:
${hist}"
    [[ -n "$files" ]] && prompt="${prompt}
Files:
${files}"
    prompt="${prompt}
Complete this: ${buf}"
    printf '%s' "$prompt"
}

# Cancel any in-flight request
_copilot_cancel() {
    if [[ -n "$_copilot_child_pid" ]]; then
        kill -TERM -$_copilot_child_pid 2>/dev/null
        _copilot_child_pid=""
    fi
    if [[ -n "$_copilot_fd" ]]; then
        zle -F "$_copilot_fd" 2>/dev/null
        exec {_copilot_fd}<&- 2>/dev/null
        _copilot_fd=""
    fi
}

# Callback when Ollama response arrives
_copilot_async_response() {
    local fd="$1"
    local raw=""
    IFS='' read -rd '' -u $fd raw

    zle -F "$fd"
    exec {fd}<&-
    _copilot_fd=""
    _copilot_child_pid=""


    local completion
    completion=$(printf '%s' "$raw" | command python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('response', '').strip(), end='')
except: pass
" 2>/dev/null)


    # Store completion — display widget will check BUFFER (not available in zle -F callbacks)
    _copilot_pending_completion="$completion"
    zle _copilot_display
}

# Fire debounced async request to Ollama
_copilot_fetch() {
    _copilot_cancel

    local buf="$BUFFER"
    [[ -z "$buf" ]] && return

    local prompt=$(_copilot_build_prompt "$buf")
    local escaped_prompt=$(_copilot_json_escape "$prompt")
    local escaped_system=$(_copilot_json_escape "$_COPILOT_SYSTEM_PROMPT")
    local url="${OLLAMA_URL:-http://localhost:11434}"
    local model="${OLLAMA_MODEL:-cli-copilot}"
    local -F debounce=$(( ${INLINE_TIMEOUT_MS:-0} / 1000.0 ))

    exec {_copilot_fd}< <(
        sleep $debounce
        curl -s --connect-timeout 5 "${url}/api/generate" \
            -d "{\"model\":\"${model}\",\"system\":\"${escaped_system}\",\"prompt\":\"${escaped_prompt}\",\"stream\":false,\"think\":false,\"keep_alive\":\"30s\",\"options\":{\"num_predict\":50,\"stop\":[\"\\n\"],\"temperature\":0.0,\"num_ctx\":2048}}" \
            2>/dev/null
    )
    _copilot_child_pid=$!

    zle -F "$_copilot_fd" _copilot_async_response
}

# Trigger fetch when buffer changes
_copilot_on_modify() {
    [[ "$BUFFER" == "$_copilot_prev_buffer" ]] && return
    _copilot_prev_buffer="$BUFFER"

    if [[ -z "$BUFFER" ]]; then
        _copilot_cancel
        POSTDISPLAY=""
        region_highlight=()
        return
    fi


    _copilot_fetch
}

# Widget to update display (called from async callback via zle)
# BUFFER is only available here, not in zle -F callbacks
_copilot_display() {
    local completion="$_copilot_pending_completion"
    local buf="$BUFFER"
    _copilot_pending_completion=""

    [[ -z "$completion" || -z "$buf" ]] && return

    if [[ "${completion:l}" == "${buf:l}"* ]]; then
        _copilot_suggestion="$completion"
        _copilot_correction=""
        POSTDISPLAY="${completion#$buf}"
        region_highlight=("${#buf} $(( ${#buf} + ${#POSTDISPLAY} )) ${ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE:-fg=8}")
    else
        _copilot_suggestion=""
        _copilot_correction="$completion"
        POSTDISPLAY="  ${completion}"
        region_highlight=("${#buf} $(( ${#buf} + ${#POSTDISPLAY} )) ${CORRECTION_STYLE:-fg=yellow}")
    fi

    zle -R
}
zle -N _copilot_display

# Accept correction: replace buffer entirely
_copilot_accept_correction() {
    if [[ -n "$_copilot_correction" ]]; then
        BUFFER="$_copilot_correction"
        CURSOR=${#BUFFER}
        POSTDISPLAY=""
        region_highlight=()
        _copilot_correction=""
        _copilot_prev_buffer="$BUFFER"
        zle -R
    fi
}
zle -N _copilot_accept_correction
bindkey "${CORRECTION_ACCEPT_KEY:-^Y}" _copilot_accept_correction

# Register hook
autoload -U add-zle-hook-widget
add-zle-hook-widget zle-line-pre-redraw _copilot_on_modify

# Register strategy for zsh-autosuggestions compatibility
_zsh_autosuggest_strategy_my_custom_suggestion() {
    [[ -n "$_copilot_suggestion" ]] && typeset -g suggestion="$_copilot_suggestion"
}
export ZSH_AUTOSUGGEST_STRATEGY=(my_custom_suggestion $ZSH_AUTOSUGGEST_STRATEGY)
