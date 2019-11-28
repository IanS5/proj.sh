#!/usr/bin/fish

function __ians5_argn_eq -d "check the current argument"
    test (commandline -opc | wc -l) -eq "$argv[1]"
end

set -l __ians5_proj_project_command c n mk new create make r rm del delete remove v visit u upload d download

complete -fc proj -n "__fish_use_subcommand" -a list
complete -fc proj -n "__fish_use_subcommand" -a visit
complete -fc proj -n "__fish_use_subcommand" -a create
complete -fc proj -n "__fish_use_subcommand" -a remove
complete -fc proj -n "__fish_use_subcommand" -a upload
complete -fc proj -n "__fish_use_subcommand" -a download

complete -c proj -n "__ians5_argn_eq 2 && __fish_seen_subcommand_from $__ians5_proj_project_command" -x -a "(proj list)" -d "Project"
complete -c proj -n "__ians5_argn_eq 3 && command -v rclone >/dev/null" -x -a "(rclone listremotes | grep -o '^[^:]*' | head -n1)"