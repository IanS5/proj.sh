#!/usr/bin/bash

__proj_completions() {
    local sub_commands="list visit create remove upload download"
    local argc="$COMP_CWORD"
    if [ "$argc" -eq "1" ]; then
        COMPREPLY=($(compgen -W "$sub_commands" "${COMP_WORDS[1]}"))
    elif [ "$argc" -eq "2" ]; then
        COMPREPLY=($(compgen -W "$(proj list)" "${COMP_WORDS[2]}"))
    elif [ "$argc" -eq "3" ]; then
        COMPREPLY=($(compgen -W "$(rclone listremotes | grep -o '^[^:]*' | head -n1)" "${COMP_WORDS[3]}"))
    fi
}

complete -F __proj_completions proj
