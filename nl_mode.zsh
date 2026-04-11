#!/bin/zsh

# Natural-language hotkey mode: Ctrl+K sends BUFFER as a question to Ollama,
# replaces BUFFER with the returned shell command. Does NOT auto-execute.
# Ctrl+Z (configurable) undoes the replacement and restores the original text.

NL_REQUEST_FILE=$(mktemp "$SCRIPT_DIR/.tmp/.nl_request_${pid}_XXXXXX")
NL_RESPONSE_FILE="${NL_REQUEST_FILE/.nl_request/.nl_response}"
touch "$NL_RESPONSE_FILE"

_copilot_nl_prev_query=""

_copilot_nl_translate() {
    local query="$BUFFER"
    [[ -z "$query" ]] && return

    # Save original text for undo
    _copilot_nl_prev_query="$query"

    # Write the NL query to the request file
    print -r "$query" > "$NL_REQUEST_FILE"

    # Poll for the daemon to write a response
    local timeout=50  # 50 * 0.1s = 5s max wait
    local i=0
    while (( i < timeout )); do
        if [[ "$NL_RESPONSE_FILE" -nt "$NL_REQUEST_FILE" ]]; then
            local result=$(<"$NL_RESPONSE_FILE")
            if [[ -n "$result" ]]; then
                BUFFER="$result"
                CURSOR=${#BUFFER}
                POSTDISPLAY=""
                region_highlight=()
                # Clear options file so inline completion doesn't show stale data
                : > "$OPTIONS_FILE"
                zle -R
                return
            fi
        fi
        sleep 0.1
        (( i++ ))
    done
}

# Undo: restore the original NL query text
_copilot_nl_undo() {
    if [[ -n "$_copilot_nl_prev_query" ]]; then
        BUFFER="$_copilot_nl_prev_query"
        CURSOR=${#BUFFER}
        _copilot_nl_prev_query=""
        POSTDISPLAY=""
        region_highlight=()
        : > "$OPTIONS_FILE"
        zle -R
    fi
}

zle -N _copilot_nl_translate_widget _copilot_nl_translate
zle -N _copilot_nl_undo_widget _copilot_nl_undo
bindkey "${NL_HOTKEY:-^K}" _copilot_nl_translate_widget
bindkey "${NL_UNDO_KEY:-^Z}" _copilot_nl_undo_widget

_nl_cleanup() {
    rm -f "$NL_REQUEST_FILE" "$NL_RESPONSE_FILE"
}
trap '_nl_cleanup' EXIT
