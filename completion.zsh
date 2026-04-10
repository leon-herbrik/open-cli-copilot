#!/bin/zsh

OPTIONS_FILE=$(find "${SCRIPT_DIR}/.tmp/" -name ".options_${pid}_??????" | head -n 1)
previous_suggestion=""
_copilot_correction=""

# Define a custom strategy for zsh-autosuggest (line 1 = prefix-matching completion)
_zsh_autosuggest_strategy_my_custom_suggestion() {
    typeset -g suggestion=$(sed -n '1p' "$OPTIONS_FILE" 2>/dev/null)
    # Only accept if it matches the current buffer prefix
    if [[ -n "$suggestion" && "${suggestion:l}" != "${BUFFER:l}"* ]]; then
        suggestion=""
    fi
}

# Read correction from line 2 of options file
_copilot_read_correction() {
    _copilot_correction=$(sed -n '2p' "$OPTIONS_FILE" 2>/dev/null)
}

# Display correction as yellow ghost text with a space gap
_copilot_show_correction() {
    _copilot_read_correction
    if [[ -n "$_copilot_correction" ]]; then
        local gap="  "
        POSTDISPLAY="${gap}${_copilot_correction}"
        local start=$(( ${#BUFFER} ))
        local end=$(( start + ${#POSTDISPLAY} ))
        region_highlight+=("${start} ${end} ${CORRECTION_STYLE:-fg=yellow}")
    fi
}

# Accept correction: replace buffer entirely
_copilot_accept_correction() {
    _copilot_read_correction
    if [[ -n "$_copilot_correction" ]]; then
        BUFFER="$_copilot_correction"
        CURSOR=${#BUFFER}
        POSTDISPLAY=""
        _copilot_correction=""
    fi
}
zle -N _copilot_accept_correction
bindkey "${CORRECTION_ACCEPT_KEY:-^Y}" _copilot_accept_correction

_update_postdisplay() {
    POSTDISPLAY="${suggestion#$BUFFER}"
    zle redisplay
}
zle -N _update_postdisplay_widget _update_postdisplay

TRAPALRM() {
    _zsh_autosuggest_strategy_my_custom_suggestion

    if [[ -n "$suggestion" ]]; then
        # Prefix match — let zsh-autosuggestions handle grey display
        if [[ "$suggestion" != "$previous_suggestion" ]]; then
            zle _update_postdisplay_widget
            previous_suggestion="$suggestion"
        fi
    else
        # No prefix match — check for correction
        _copilot_read_correction
        if [[ -n "$_copilot_correction" ]]; then
            _copilot_show_correction
            zle redisplay
        elif [[ -n "$POSTDISPLAY" ]]; then
            # Clear stale ghost text
            POSTDISPLAY=""
            zle redisplay
        fi
        previous_suggestion=""
    fi
}
TMOUT=1

# Add as the first strategy to zsh-autosuggest plugin
export ZSH_AUTOSUGGEST_STRATEGY=(my_custom_suggestion $ZSH_AUTOSUGGEST_STRATEGY)
