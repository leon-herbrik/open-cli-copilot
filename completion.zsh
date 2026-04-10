#!/bin/zsh

OPTIONS_FILE=$(find "${SCRIPT_DIR}/.tmp/" -name ".options_${pid}_??????" | head -n 1)
_copilot_prev_suggestion=""
_copilot_prev_correction=""
_copilot_correction=""

# Custom strategy for zsh-autosuggestions (reads line 1 = prefix-matching completion)
_zsh_autosuggest_strategy_my_custom_suggestion() {
    typeset -g suggestion=$(sed -n '1p' "$OPTIONS_FILE" 2>/dev/null)
    if [[ -n "$suggestion" && "${suggestion:l}" != "${BUFFER:l}"* ]]; then
        suggestion=""
    fi
}

# Read correction from line 2 of options file
_copilot_read_correction() {
    _copilot_correction=$(sed -n '2p' "$OPTIONS_FILE" 2>/dev/null)
}

# Widget: show correction as yellow ghost text with gap
_copilot_show_correction_widget() {
    local gap="  "
    POSTDISPLAY="${gap}${_copilot_correction}"
    region_highlight=("${#BUFFER} $(( ${#BUFFER} + ${#POSTDISPLAY} )) ${CORRECTION_STYLE:-fg=yellow}")
}
zle -N _copilot_show_correction_widget

# Widget: clear ghost text
_copilot_clear_widget() {
    POSTDISPLAY=""
}
zle -N _copilot_clear_widget

# Accept correction: replace buffer entirely
_copilot_accept_correction() {
    _copilot_read_correction
    if [[ -n "$_copilot_correction" ]]; then
        BUFFER="$_copilot_correction"
        CURSOR=${#BUFFER}
        POSTDISPLAY=""
        _copilot_correction=""
        _copilot_prev_correction=""
    fi
}
zle -N _copilot_accept_correction
bindkey "${CORRECTION_ACCEPT_KEY:-^Y}" _copilot_accept_correction

TRAPALRM() {
    # Check for prefix-matching completion
    _zsh_autosuggest_strategy_my_custom_suggestion

    if [[ -n "$suggestion" ]]; then
        # Prefix match — let zsh-autosuggestions display it grey
        if [[ "$suggestion" != "$_copilot_prev_suggestion" ]]; then
            zle autosuggest-suggest -- "$suggestion"
            _copilot_prev_suggestion="$suggestion"
            _copilot_prev_correction=""
        fi
    else
        # No prefix match — check for correction
        _copilot_read_correction
        if [[ -n "$_copilot_correction" ]]; then
            if [[ "$_copilot_correction" != "$_copilot_prev_correction" ]]; then
                zle autosuggest-clear
                zle _copilot_show_correction_widget
                _copilot_prev_correction="$_copilot_correction"
                _copilot_prev_suggestion=""
            fi
        elif [[ -n "$_copilot_prev_suggestion" || -n "$_copilot_prev_correction" ]]; then
            zle autosuggest-clear
            _copilot_prev_suggestion=""
            _copilot_prev_correction=""
        fi
    fi
}
TMOUT=1

# Register as first strategy for zsh-autosuggestions
export ZSH_AUTOSUGGEST_STRATEGY=(my_custom_suggestion $ZSH_AUTOSUGGEST_STRATEGY)
