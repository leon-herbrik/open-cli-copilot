#!/bin/zsh

SCRIPT_DIR=${0:a:h}
pid=$$

source "$SCRIPT_DIR/config.zsh"
source "$SCRIPT_DIR/completion.zsh"
source "$SCRIPT_DIR/nl_mode.zsh"

# Warm the Ollama model in the background
(curl -s -o /dev/null "${OLLAMA_URL:-http://localhost:11434}/api/generate" \
    -d '{"model":"'"${OLLAMA_MODEL:-cli-copilot}"'","prompt":"","keep_alive":"30s"}' &) 2>/dev/null
