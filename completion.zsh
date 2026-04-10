#!/bin/zsh

OPTIONS_FILE=$(find "${SCRIPT_DIR}/.tmp/" -name ".options_${pid}_??????" | head -n 1)
_copilot_prev_suggestion=""
_copilot_prev_buffer=""

# Define a custom strategy for zsh-autosuggest
_zsh_autosuggest_strategy_my_custom_suggestion() {
    typeset -g suggestion=$(grep -i "^$BUFFER" "$OPTIONS_FILE" 2>/dev/null | head -n 1)
}

_copilot_update_postdisplay() {
    if [[ -n "$_copilot_suggestion" ]]; then
        POSTDISPLAY="${_copilot_suggestion#$BUFFER}"
    else
        POSTDISPLAY=""
    fi
    zle redisplay
}
zle -N _copilot_update_postdisplay_widget _copilot_update_postdisplay

TRAPALRM() {
    local cur_buffer="$BUFFER"
    _copilot_suggestion=$(grep -i "^${cur_buffer}" "$OPTIONS_FILE" 2>/dev/null | head -n 1)

    # Update display if suggestion changed OR buffer changed since last check
    if [[ "$_copilot_suggestion" != "$_copilot_prev_suggestion" || "$cur_buffer" != "$_copilot_prev_buffer" ]]; then
        zle _copilot_update_postdisplay_widget
        _copilot_prev_suggestion="$_copilot_suggestion"
        _copilot_prev_buffer="$cur_buffer"
    fi
}
TMOUT=1

# Add as the first strategy to zsh-autosuggest plugin
export ZSH_AUTOSUGGEST_STRATEGY=(my_custom_suggestion $ZSH_AUTOSUGGEST_STRATEGY)
