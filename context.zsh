#!/bin/zsh

CONTEXT_FILE=$(find "${SCRIPT_DIR}/.tmp/" -name ".context_${pid}_??????" | head -n 1)
OS=$(uname)

# Track last command's exit code
_copilot_last_exit_code=0
_copilot_preexec() { :; }
_copilot_precmd() { _copilot_last_exit_code=$?; }
autoload -U add-zsh-hook
add-zsh-hook precmd _copilot_precmd

# Update the context file with full context
update_context() {
    local depth="${CONTEXT_HISTORY_DEPTH:-10}"
    local his=$(fc -l -n -"$depth" 2>/dev/null)

    # Line 1: current buffer
    print -r "$BUFFER" > "$CONTEXT_FILE"
    # Line 2: working directory
    pwd >> "$CONTEXT_FILE"
    # Line 3: exit code of last command
    print -r "$_copilot_last_exit_code" >> "$CONTEXT_FILE"
    # Line 4: git branch + short status (empty if not a repo)
    local git_info=""
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        local branch=$(git branch --show-current 2>/dev/null)
        local status=$(git status --short 2>/dev/null | head -5)
        git_info="branch:${branch}"
        [[ -n "$status" ]] && git_info="${git_info} ${status}"
    fi
    print -r "$git_info" >> "$CONTEXT_FILE"
    # Line 5: env var names (no values, for security)
    print -r "$(env | cut -d= -f1 | head -30 | tr '\n' ' ')" >> "$CONTEXT_FILE"
    # Lines 6+: history
    print -r "$his" >> "$CONTEXT_FILE"
    # After history: directory listing
    if [[ "${CONTEXT_DIR_LISTING:-true}" == "true" ]]; then
        ls -1 | head -20 >> "$CONTEXT_FILE"
    fi
}

# Update only the buffer line (line 1) on each keystroke
update_context_buffer() {
    if [[ "$OS" == "Darwin" ]]; then
        sed -i '' "1s|.*|$(_zsh_autosuggest_escape_command "${BUFFER:-}")|" "$CONTEXT_FILE"
    else
        sed -i "1s|.*|$(_zsh_autosuggest_escape_command "${BUFFER:-}")|" "$CONTEXT_FILE"
    fi
}

autoload -U add-zle-hook-widget
add-zle-hook-widget line-init update_context
add-zle-hook-widget zle-line-pre-redraw update_context_buffer
