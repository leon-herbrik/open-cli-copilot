#!/bin/zsh

OPTIONS_FILE=$(find "${SCRIPT_DIR}/.tmp/" -name ".options_${pid}_??????" | head -n 1)
previous_suggestion=""
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
    _copilot_read_correction
    if [[ -n "$_copilot_correction" ]]; then
        local gap="  "
        POSTDISPLAY="${gap}${_copilot_correction}"
        region_highlight=("${#BUFFER} $(( ${#BUFFER} + ${#POSTDISPLAY} )) ${CORRECTION_STYLE:-fg=yellow}")
    else
        POSTDISPLAY=""
        region_highlight=()
    fi
    zle -R
}
zle -N _copilot_show_correction_widget

# Widget: show completion as grey ghost text
_copilot_show_completion_widget() {
    POSTDISPLAY="${suggestion#$BUFFER}"
    region_highlight=("${#BUFFER} $(( ${#BUFFER} + ${#POSTDISPLAY} )) ${ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE:-fg=8}")
    zle -R
}
zle -N _copilot_show_completion_widget

# Accept correction: replace buffer entirely
_copilot_accept_correction() {
    _copilot_read_correction
    if [[ -n "$_copilot_correction" ]]; then
        BUFFER="$_copilot_correction"
        CURSOR=${#BUFFER}
        POSTDISPLAY=""
        region_highlight=()
        _copilot_correction=""
        # Clear options file so stale correction doesn't re-appear
        : > "$OPTIONS_FILE"
        zle -R
    fi
}
zle -N _copilot_accept_correction
bindkey "${CORRECTION_ACCEPT_KEY:-^Y}" _copilot_accept_correction

TRAPALRM() {
    _zsh_autosuggest_strategy_my_custom_suggestion

    if [[ -n "$suggestion" ]]; then
        # Prefix match — show grey completion
        if [[ "$suggestion" != "$previous_suggestion" ]]; then
            zle _copilot_show_completion_widget
            previous_suggestion="$suggestion"
        fi
    else
        # No prefix match — always re-apply correction (zsh-autosuggestions may have cleared it)
        zle _copilot_show_correction_widget
        previous_suggestion=""
    fi
}
TMOUT=1

# Register as first strategy for zsh-autosuggestions
export ZSH_AUTOSUGGEST_STRATEGY=(my_custom_suggestion $ZSH_AUTOSUGGEST_STRATEGY)
