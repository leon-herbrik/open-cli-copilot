import os
import sys
import time
import json
import urllib.request
from pathlib import Path
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TMP_FILES_DIR = os.path.join(SCRIPT_DIR, ".tmp")
tmp_files_dir_path = Path(TMP_FILES_DIR)

CHECK_INTERVAL = 0.1

def load_config():
    """Load config from ~/.config/open-cli-copilot/config, return as dict."""
    config = {}
    config_path = Path.home() / ".config" / "open-cli-copilot" / "config"
    if config_path.exists():
        for line in config_path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, value = line.split("=", 1)
                config[key.strip()] = value.strip()
    return config

_config = load_config()
OLLAMA_URL = os.environ.get("OLLAMA_URL", _config.get("OLLAMA_URL", "http://localhost:11434"))
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", _config.get("OLLAMA_MODEL", "qwen2.5-coder:1.5b"))
MIN_IDLE_TIME = int(os.environ.get("INLINE_TIMEOUT_MS", _config.get("INLINE_TIMEOUT_MS", "300"))) / 1000

SYSTEM_PROMPT = """\
You are a shell command autocomplete engine. \
Given a partial command after "Complete this:", output the full completed command. \
CRITICAL: Your output MUST start with the EXACT text the user already typed. \
You are only appending to what they wrote. \
Output ONLY the raw command. Never use backticks, code fences, markdown, or quotes. \
Never explain. Single line only."""

NL_SYSTEM_PROMPT = """\
Translate this description into a single shell command. \
Output ONLY the raw command. Never use backticks, code fences, markdown, or quotes. \
Never explain."""

CONTEXT_HISTORY_DEPTH = int(os.environ.get(
    "CONTEXT_HISTORY_DEPTH", _config.get("CONTEXT_HISTORY_DEPTH", "10")
))

prompt_template = """\
Directory: {current_directory}
{git_info}{exit_code}Last commands:
{command_history}
Files: {ls_output}
Complete this: {current_prompt}"""


def parse_file(file_path):
    with open(file_path, "r") as file:
        lines = file.readlines()

    if not lines:
        return None, None

    current_prompt = lines[0].strip()
    if not current_prompt:
        return None, None

    current_directory = lines[1].strip() if len(lines) > 1 else ""
    exit_code = lines[2].strip() if len(lines) > 2 else "0"
    git_info = lines[3].strip() if len(lines) > 3 else ""
    # line 4 is env var names — available but kept brief, skip for inline prompt
    # lines 5+ are history, then dir listing
    history_start = 5
    history_end = history_start + CONTEXT_HISTORY_DEPTH
    command_history = "".join(lines[history_start:history_end]).strip()
    ls_output = "".join(lines[history_end:]).strip()

    git_str = f"Git: {git_info}\n" if git_info else ""
    exit_str = f"Last exit code: {exit_code}\n" if exit_code != "0" else ""

    prompt = prompt_template.format(
        command_history=command_history,
        ls_output=ls_output,
        current_directory=current_directory,
        current_prompt=current_prompt,
        git_info=git_str,
        exit_code=exit_str,
    )
    return current_prompt, prompt


def call_ollama(prompt, system=None, max_tokens=50):
    """Call Ollama /api/generate with streaming, return first line of output."""
    payload = json.dumps({
        "model": OLLAMA_MODEL,
        "system": system or SYSTEM_PROMPT,
        "prompt": prompt,
        "stream": True,
        "keep_alive": "30s",
        "options": {
            "num_predict": max_tokens,
            "stop": ["\n"],
            "temperature": 0.0,
            "num_ctx": 2048,
        },
    }).encode("utf-8")

    req = urllib.request.Request(
        f"{OLLAMA_URL}/api/generate",
        data=payload,
        headers={"Content-Type": "application/json"},
    )

    result = []
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            for line in resp:
                chunk = json.loads(line)
                token = chunk.get("response", "")
                if "\n" in token:
                    result.append(token.split("\n")[0])
                    break
                result.append(token)
                if chunk.get("done", False):
                    break
    except Exception:
        return None

    return "".join(result).strip()


def serve_terminal_session(context_file_path, option_file_path):
    context_modification_time = os.path.getmtime(context_file_path)
    options_modification_time = os.path.getmtime(option_file_path)

    if (
        context_modification_time >= options_modification_time
        and (time.time() - context_modification_time) > MIN_IDLE_TIME
    ):
        current_prompt, prompt = parse_file(context_file_path)

        if not prompt:
            return

        completion = call_ollama(prompt)
        if not completion:
            return

        # Line 1: prefix-matching completion, Line 2: correction (non-matching)
        if completion.lower().startswith(current_prompt.lower()):
            with open(option_file_path, "w") as file:
                file.write(completion + "\n")
        else:
            with open(option_file_path, "w") as file:
                file.write("\n" + completion)


def serve_nl_request(request_file_path, response_file_path):
    """Handle a natural-language-to-command request."""
    req_mtime = os.path.getmtime(request_file_path)
    resp_mtime = os.path.getmtime(response_file_path)

    if req_mtime <= resp_mtime:
        return

    with open(request_file_path, "r") as f:
        query = f.read().strip()

    if not query:
        return

    result = call_ollama(query, system=NL_SYSTEM_PROMPT, max_tokens=200)
    if result:
        with open(response_file_path, "w") as f:
            f.write(result)


def handle_tmp_files(directory):
    context_files = list(tmp_files_dir_path.glob("*.context*"))
    nl_request_files = list(tmp_files_dir_path.glob("*.nl_request*"))

    if not context_files and not nl_request_files:
        sys.exit(1)

    # Handle inline completion requests
    for f in context_files:
        context_file_path = os.path.join(directory, f.name)

        option_file_path = None
        for option_f in tmp_files_dir_path.glob(
            f.name.replace(".context", ".options")[:-6] + "*"
        ):
            option_file_path = os.path.join(directory, option_f)

        if not option_file_path:
            continue

        try:
            serve_terminal_session(context_file_path, option_file_path)
        except Exception as e:
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            sys.stderr.write(f"{timestamp} \t ERROR: {str(e)}\n")

    # Handle NL-to-command requests
    for f in nl_request_files:
        request_path = os.path.join(directory, f.name)
        # Response file has same name with .nl_request replaced by .nl_response
        response_name = f.name.replace(".nl_request", ".nl_response")
        response_path = os.path.join(directory, response_name)

        try:
            serve_nl_request(request_path, response_path)
        except Exception as e:
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            sys.stderr.write(f"{timestamp} \t NL ERROR: {str(e)}\n")


def watch_files():
    while True:
        handle_tmp_files(TMP_FILES_DIR)
        time.sleep(CHECK_INTERVAL)


if __name__ == "__main__":
    watch_files()
