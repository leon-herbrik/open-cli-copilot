#!/bin/zsh

# Get the directory of the script
SCRIPT_DIR=${0:a:h}
# Get the process ID of the current terminal session
pid=$$

CONFIG_SCRIPT="$SCRIPT_DIR/config.zsh"
PYTHON_SCRIPT="$SCRIPT_DIR/generate_completion.py"
COMPLETION_SCRIPT="$SCRIPT_DIR/completion.zsh"
CONTEXT_SCRIPT="$SCRIPT_DIR/context.zsh"
NL_MODE_SCRIPT="$SCRIPT_DIR/nl_mode.zsh"

# Load config (sets defaults and reads ~/.config/open-cli-copilot/config)
source "$CONFIG_SCRIPT"

LOG_FILE="$SCRIPT_DIR/error.log"

OPTIONS_FILE=$(mktemp "$SCRIPT_DIR/.tmp/.options_${pid}_XXXXXX")
CONTEXT_FILE=$(mktemp "$SCRIPT_DIR/.tmp/.context_${pid}_XXXXXX")

# Check if the Python script is already running
if ! pgrep -f "$PYTHON_SCRIPT" > /dev/null; then
    # Start the Python daemon (no venv needed — stdlib only)
    $(nohup python3 "$PYTHON_SCRIPT" >/dev/null 2>>"$LOG_FILE" &)
fi

# Warm the Ollama model in the background so first completion is fast
(curl -s -o /dev/null "${OLLAMA_URL:-http://localhost:11434}/api/generate" \
    -d '{"model":"'"${OLLAMA_MODEL:-qwen3:4b}"'","prompt":"","keep_alive":-1}' &) 2>/dev/null

cleanup() {
    # Check if there are no other zsh sessions open
    if [ $(ps -eo pid,comm,tty,stat | grep -E 'zsh.*\+' | wc -l) -eq 1 ]; then
        # Kill the Python script
        PYTHON_PID=$(pgrep -f "$PYTHON_SCRIPT")
        kill "$PYTHON_PID"
    fi

    # Remove the temporary files
    rm -f "$OPTIONS_FILE"
    rm -f "$CONTEXT_FILE"
}

# Set up trap to kill Python script when the last zsh session is closed
trap cleanup EXIT

# Load the completion, context, and NL mode scripts
source "$COMPLETION_SCRIPT"
source "$CONTEXT_SCRIPT"
source "$NL_MODE_SCRIPT"
