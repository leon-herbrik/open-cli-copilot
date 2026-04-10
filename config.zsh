#!/bin/zsh

# Load user config from ~/.config/open-cli-copilot/config
COPILOT_CONFIG_FILE="${HOME}/.config/open-cli-copilot/config"

if [[ -f "$COPILOT_CONFIG_FILE" ]]; then
    while IFS='=' read -r key value; do
        # Skip comments and blank lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key="${key// /}"
        value="${value// /}"
        case "$key" in
            OLLAMA_URL)           export OLLAMA_URL="$value" ;;
            OLLAMA_MODEL)         export OLLAMA_MODEL="$value" ;;
            INLINE_TIMEOUT_MS)    export INLINE_TIMEOUT_MS="$value" ;;
            NL_HOTKEY)            export NL_HOTKEY="$value" ;;
            CONTEXT_HISTORY_DEPTH) export CONTEXT_HISTORY_DEPTH="$value" ;;
            CONTEXT_DIR_LISTING)  export CONTEXT_DIR_LISTING="$value" ;;
        esac
    done < "$COPILOT_CONFIG_FILE"
fi

# Defaults
: ${OLLAMA_URL:=http://localhost:11434}
: ${OLLAMA_MODEL:=qwen3:4b}
: ${INLINE_TIMEOUT_MS:=300}
: ${NL_HOTKEY:=^K}
: ${CONTEXT_HISTORY_DEPTH:=10}
: ${CONTEXT_DIR_LISTING:=true}
