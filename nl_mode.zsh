#!/bin/zsh

# Natural-language hotkey mode: Ctrl+K sends BUFFER as a question to Ollama,
# replaces BUFFER with the returned shell command. Does NOT auto-execute.

NL_REQUEST_FILE=$(mktemp "$SCRIPT_DIR/.tmp/.nl_request_${pid}_XXXXXX")
NL_RESPONSE_FILE=$(mktemp "$SCRIPT_DIR/.tmp/.nl_response_${pid}_XXXXXX")

_copilot_nl_translate() {
    local query="$BUFFER"
    [[ -z "$query" ]] && return

    # Write the NL query to the request file
    print -r "$query" > "$NL_REQUEST_FILE"

    # Wait for the Python daemon to write a response (poll with short timeout)
    local timeout=50  # 50 * 0.1s = 5s max wait
    local i=0
    while (( i < timeout )); do
        if [[ "$NL_RESPONSE_FILE" -nt "$NL_REQUEST_FILE" ]]; then
            local result=$(<"$NL_RESPONSE_FILE")
            if [[ -n "$result" ]]; then
                BUFFER="$result"
                CURSOR=${#BUFFER}
                zle redisplay
                return
            fi
        fi
        sleep 0.1
        (( i++ ))
    done
}

zle -N _copilot_nl_translate_widget _copilot_nl_translate
bindkey "${NL_HOTKEY:-^K}" _copilot_nl_translate_widget

# Clean up NL temp files on exit
_nl_cleanup() {
    rm -f "$NL_REQUEST_FILE" "$NL_RESPONSE_FILE"
}
trap '_nl_cleanup' EXIT
