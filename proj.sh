#!/usr/bin/env sh
set -e

proj_log() {
    level="$1"
    message="$2"

    echo "[proj] [$level] $message"
}

proj_debug() {
    if [ "$PROJ_DEBUG" = "1" ]; then
        proj_log DEBUG "$1"
    fi
}

proj_info() {
    proj_log INFO "$1"
}

proj_fatal() {
    proj_log FATAL "$1" >&2
    exit 1
}

proj_has() {
    command -v rclone >/dev/null
}

proj_print() {
    printf "%s" "$1"
}

if [ ! -d "$PROJ_REPO" ]; then
    proj_fatal "\$PROJ_REPO is not set to a valid directory. \$PROJ_REPO='$PROJ_REPO'"
fi

PROJ_DEBUG=${PROJ_DEBUG:-0}
PROJ_CACHE=${PROJ_CACHE:-"$HOME/.cache/proj"}
PROJ_REMOTE_ROOT=${PROJ_REMOTE_ROOT:-"/proj"}

if [ ! -d "$PROJ_CACHE" ]; then
    proj_debug "creating cache directory. \$PROJ_CACHE='$PROJ_CACHE'"
    mkdir -p "$PROJ_CACHE"
fi

if [ -z "$PROJ_DEFAULT_REMOTE" ] && proj_has rclone; then
    PROJ_DEFAULT_REMOTE="$(rclone listremotes | grep -o '^[^:]*' | head -n1)"
fi

proj_arg0="$0"
proj_action="$1"

proj_help() {
    echo "USAGE"
    echo "  $proj_arg0 COMMAND PROJECT <REMOTE>"
    echo ""
    echo "COMMANDS"
    echo "  help     - display this message"
    echo "  visit    - open a new shell instance in an existing project"
    echo "  create   - create a new project"
    echo "  remove   - delete the project folder"
    echo "  upload   - upload a project to a remote service, using rclone"
    echo "  download - download a project from a remote service, using rclone"
    echo ""
    echo "ENVIRONMENT"
    echo "  PROJ_DEBUG          - set to 1 to enable debug logging [default: 0]"
    echo "  PROJ_CACHE          - path to the proj cache (mostly used for history files) [default: ~/.cache/proj]"
    echo "  PROJ_REMOTE_ROOT    - base path to use on remote targets [default: /proj]"
    echo "  PROJ_DEFAULT_REMOTE - rclone remote to use if <REMOTE> is unset [default: first remote from 'rclone listremotes']"
    echo "  PROJ_SHELL          - shell to call when visiting a project. [fallback: \$SHELL, sh]"

}

proj_binary() {
    default="$1"

    if [ "$default" = "y" ]; then
        yn="[Y/n]"
    elif [ "$default" = "n" ]; then
        yn="[y/N]"
    else
        yn="[y/n]"
    fi

    proj_print " $yn "
    while read -r response; do
        response="${response:="$default"}"
        case "$response" in
            [Yy] | [Yy][Ee][Ss])
                return 0
                ;;
            [Nn] | [Nn][Oo])
                return 1
                ;;
            *)
                proj_print " $yn "
                ;;
        esac
    done
}

proj_path_of() {
    project="$1"

    case "$project" in
        "")
            proj_fatal "project name is required!"
            ;;
        */*)
            proj_fatal "project names may not include a slash"
            ;;
    esac

    proj_print "$PROJ_REPO/$project"
}

proj_hist_id() {
    project="$1"
    shell="$2"
    shell_name="$(basename "$(readlink -f "$(command -v "$shell")")")"

    proj_print "proj_${project}.$shell_name"
}

proj_fish_hist_id() {
    # fish has strict requirements on how history files can be identified
    # to avoid that just md5sum the history ID
    proj_hist_id "$1" "$2" | md5sum | cut -d '-' -f 1 | tr -d '[:space:]'
}

proj_create() {
    project="$1"
    project_path="$(proj_path_of "$project")"

    if [ -d "$project_path" ]; then
        proj_print "$project already exists, overwrite it?"
        if proj_binary "n"; then
            proj_remove "$project"
        else
            proj_info "project '$project' has not been created"
            exit 0
        fi
    fi

    mkdir "$PROJ_REPO/$project"
    proj_info "project '$project' has been created"
}

proj_remove() {
    # TODO: optionally remove on remotes too

    project="$1"
    project_path="$(proj_path_of "$project")"

    if [ ! -d "$project_path" ]; then
        proj_fatal "project '$project' does not exist"
    fi

    proj_print "deleting '$project' at $project_path, continue?"
    if proj_binary "n"; then
        rm -rf "$project_path"
        proj_info "project '$project' has been deleted"
    else
        proj_info "project '$project' has not been deleted"
    fi
}

proj_excluded() {
    path="$1"

    if proj_has git && [ -d "$path/.git" ]; then
        wd="$PWD"
        cd "$path"
        git ls-files --others --ignored --exclude-standard --directory | sed 's/\/$/\/\*\*/'
        git ls-files --others --ignored --exclude-standard
        cd "$wd"
    fi
}

proj_sync() {
    if ! proj_has rclone; then
        proj_fatal "rclone is required for syncing (see: https://rclone.org)"
    fi

    direction="$1"
    project="$2"
    remote="${3:-"$PROJ_DEFAULT_REMOTE"}"
    project_path="$(proj_path_of "$project")"
    exclude_file_path="$PROJ_CACHE/exclude_$project"

    if [ -z "$remote" ]; then
        proj_fatal "no remote specified, and \$PROJ_DEFAULT_REMOTE is unset."
    fi

    proj_excluded "$project_path" >"$exclude_file_path"

    remote_path="$remote:$PROJ_REMOTE_ROOT/$project"

    proj_debug "\$remote_path=$remote_path"
    proj_debug "\$exclude_file_path=$exclude_file_path"

    case "$direction" in
        up)
            proj_info "sending to remote '$remote'"
            rclone sync "$project_path" "$remote_path" --progress --exclude-from="$exclude_file_path"
            ;;
        down)
            proj_info "pulling from remote '$remote'"
            rclone sync "$remote_path" "$project_path" --progress --exclude-from="$exclude_file_path"
            ;;
        *)
            rm "$exclude_file_path"
            proj_fatal "expecting 'up' or 'down' for direction. \$direction='$direction' \$project='$project' \$remote='$remote'"
            ;;
    esac

    rm "$exclude_file_path"
    proj_info "local project '$project' synced with '$remote'"

}

proj_visit() {
    project="$1"
    project_path="$(proj_path_of "$project")"

    if [ ! -d "$project_path" ]; then
        proj_fatal "project '$project' does not exist"
    fi

    if [ -n "$PROJ_SHELL" ] && proj_has "$PROJ_SHELL"; then
        shell="$PROJ_SHELL"
    elif [ -n "$SHELL" ] && proj_has "$SHELL"; then
        shell="$SHELL"
    elif proj_has sh; then
        shell="sh"
    else
        proj_fatal "could not determine system shell, please set \$PROJ_SHELL"
    fi

    # set all history variables here, just in case the shell is identified wrong
    #  some one could always `mv /bin/fish /bin/bash`
    # so we (kinda) account for that by setting all variables regardless of shell
    fish_history="$(proj_fish_hist_id "$project" "$shell")"
    HISTFILE="$PROJ_CACHE/history_$(proj_hist_id "$project" "$shell")"

    proj_debug "\$HISTFILE=$HISTFILE"
    proj_debug "\$fish_history=$fish_history"

    export fish_history
    export HISTFILE
    export PROJ_CURRENT_PROJECT_BASE="$project_path"
    export PROJ_CURRENT_PROJECT_NAME="$project"

    term_has_alt_screen=0
    if proj_has infocmp && [ "$(infocmp -1 | grep -c '[sr]mcup')" -ge "2" ]; then
        proj_debug "using terminal alternate screen"
        term_has_alt_screen=1
    fi

    wd="$PWD"
    proj_debug "will return to '$wd'"

    cd "$project_path"
    test $term_has_alt_screen -ne 0 && tput smcup
    "$shell"
    test $term_has_alt_screen -ne 0 && tput rmcup
    cd "$wd"
}

proj_list() {
    ls -1 "$PROJ_REPO"
}

case "$proj_action" in
    h | help | \? | -h | --help)
        proj_help
        exit 0
        ;;

    c | n | mk | new | create | make)
        proj_create "$2"
        ;;

    r | rm | rem | del | delete | remove)
        proj_remove "$2"
        ;;

    v | visit)
        proj_visit "$2"
        ;;

    u | up | upload)
        proj_sync up "$2" "$3"
        ;;

    d | down | download)
        proj_sync down "$2" "$3"
        ;;

    ls | list)
        proj_list
        ;;
esac
