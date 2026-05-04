#!/usr/bin/env bash

set -euo pipefail

__notify_on_error=0

_notify() {
    if command -v notify-send &>/dev/null; then
        notify-send --app-name share "$@" || true
    fi
}

_log() {
    local level="$1"
    shift
    local message="$*"
    local level_color="" reset=""

    if [ -t 2 ]; then
        case "$level" in
            INFO)  level_color=$(tput setaf 2) ;;
            WARN)  level_color=$(tput setaf 3) ;;
            ERROR) level_color=$(tput setaf 1) ;;
            DEBUG) level_color=$(tput setaf 6) ;;
            *)
                log_error "Invalid log level $level"
                return 1
                ;;
        esac
        reset=$(tput sgr0)
    fi

    printf "[%s%s%s] %s\n" "$level_color" "$level" "$reset" "$message" >&2
}

log_info()  { _log INFO  "$@"; }
log_warn()  { _log WARN  "$@"; }
log_debug() { [[ -n "${WPSTE_DEBUG:-}" ]] && _log DEBUG "$@" || true; }

log_error() {
    local exit_code=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -e|--exit) exit_code="$2"; shift 2 ;;
            --) shift; break ;;
            *) break ;;
        esac
    done

    _log ERROR "$@"

    if [[ "$__notify_on_error" -eq 1 ]]; then
        _notify -u critical "share.fish" "$*"
    fi

    if [[ -n "$exit_code" ]]; then
        exit "$exit_code"
    fi
}

_print_help() {
    log_info "A simple grimshot wrapper for rehome-cli with support for editing before upload."
    log_info "Usage: share [-t|--target <active|screen|output|area|window>] [-c|--copy] [-n|--notify] [-e|--edit] [file]"
    exit 0
}

_is_image() {
    local file="$1"
    local mimetype
    mimetype=$(xdg-mime query filetype "$file")
    [[ "$mimetype" == image/* ]]
}

_check_requirements() {
    local required_commands=(rehome-cli notify-send grimshot wl-copy)

    if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
        log_error --exit 1 "WAYLAND_DISPLAY is not set. share expects a Wayland environment."
    fi

    for requirement in "${required_commands[@]}"; do
        if ! command -v "$requirement" &>/dev/null; then
            log_error --exit 1 "Missing requirement: $requirement"
        else
            log_debug "Found requirement: $requirement"
        fi
    done
}

_play_sound() {
    local sound_file="/usr/share/sounds/freedesktop/stereo/camera-shutter.oga"

    if command -v mpv &>/dev/null && [[ -f "$sound_file" ]]; then
        mpv --no-video --no-terminal "$sound_file" &
    fi
}

_take_screenshot() {
    local target="$1"
    local save_path
    save_path=$(mktemp --tmpdir --suffix=.png share-XXXXX)

    local grimshot_output
    grimshot_output=$(grimshot save "$target" "$save_path" 2>&1)
    local grimshot_status=$?

    log_debug "grimshot: $grimshot_output"

    if [[ $grimshot_status -ne 0 ]]; then
        if [[ "$grimshot_output" == *"selection cancelled"* ]]; then
            log_info "${grimshot_output/s/S}."
            exit 0
        fi
        log_error --exit "$grimshot_status" "Grimshot error: $grimshot_output"
    fi

    _play_sound

    if command -v oxipng &>/dev/null; then
        local oxipng_output
        oxipng_output=$(oxipng --strip safe "$save_path" 2>&1) && log_debug "oxipng: $oxipng_output"
    fi

    echo "$save_path"
}

_upload_file() {
    local file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--file) file="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$file" ]]; then
        log_error --exit 2 "_upload_file: Expected --file."
    fi

    if [[ ! -f "$file" ]]; then
        log_error --exit 1 "$file does not exist."
    fi

    log_debug "Uploading $file"

    local output
    output=$(rehome-cli upload "$file")
    local upload_status=$?

    if [[ $upload_status -ne 0 ]]; then
        log_error --exit "$upload_status" "$output"
    fi

    echo "$output"
}

_copy_to_clipboard() {
    local file="" text=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--file) file="$2"; shift 2 ;;
            -t|--text) text="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$file" && -z "$text" ]]; then
        log_error --exit 2 "_copy_to_clipboard: Expected at least one of --text or --file."
    fi

    if [[ -n "$text" ]]; then
        wl-copy "$text" || log_error --exit $? "Failed to copy $text to the clipboard."
    fi

    if [[ -n "$file" ]]; then
        if _is_image "$file"; then
            log_debug "Copying $file to primary clipboard"
            # Hardcoded to image/png for now otherwise certain apps don't support pasting non-png images.
            # https://github.com/bugaevc/wl-clipboard/issues/8
            # https://github.com/bugaevc/wl-clipboard/issues/71
            wl-copy --primary --type image/png <"$file" || log_error --exit $? "Failed to copy $file to the clipboard."
        else
            log_debug "$file is not an image. Not copying to clipboard."
        fi
    fi
}

share_main() {
    _check_requirements

    local flag_help=0 flag_copy=0 flag_notify=0 flag_edit=0
    local flag_target="" flag_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)   flag_help=1;       shift ;;
            -c|--copy)   flag_copy=1;       shift ;;
            -n|--notify) flag_notify=1;     shift ;;
            -e|--edit)   flag_edit=1;       shift ;;
            -t|--target) flag_target="$2";  shift 2 ;;
            --)          shift; break ;;
            -*)          log_error --exit 2 "Unknown option: $1" ;;
            *)           flag_file="$1";    shift ;;
        esac
    done

    log_debug "flag_help: $flag_help"
    log_debug "flag_copy: $flag_copy"
    log_debug "flag_notify: $flag_notify"
    log_debug "flag_target: $flag_target"
    log_debug "flag_file: $flag_file"

    [[ "$flag_help" -eq 1 ]] && _print_help

    [[ "$flag_notify" -eq 1 ]] && __notify_on_error=1

    if [[ -n "$flag_target" ]]; then
        local valid_targets=(active screen output area window)
        local valid=0
        for target in "${valid_targets[@]}"; do
            [[ "$flag_target" == "$target" ]] && valid=1 && break
        done
        if [[ "$valid" -eq 0 ]]; then
            log_error --exit 2 "--target must be one of $(IFS=', '; echo "${valid_targets[*]}")."
        fi
    else
        flag_target="output"
    fi

    if [[ -z "$flag_file" ]]; then
        flag_file=$(_take_screenshot "$flag_target")
    fi

    if [[ "$flag_edit" -eq 1 ]]; then
        if ! command -v swappy &>/dev/null; then
            log_warn "Ignoring --edit because swappy is not installed."
        elif ! _is_image "$flag_file"; then
            log_warn "Ignoring --edit because $flag_file is not an image."
        else
            swappy -f "$flag_file" -o "$flag_file" || log_error --exit $? "Editing image failed."
        fi
    fi

    local url
    url=$(_upload_file --file "$flag_file")
    local upload_status=$?
    url="${url/http:/https:}"

    if [[ "$upload_status" -eq 0 && "$flag_copy" -eq 1 ]]; then
        _copy_to_clipboard --text "$url" --file "$flag_file"
        if [[ "$flag_notify" -eq 1 ]]; then
            local notification_args=()
            local notification_title
            notification_title=$(basename "$flag_file")
            local notification_body="URL copied to clipboard."
            if _is_image "$flag_file"; then
                notification_args=(--icon "$flag_file")
                notification_body="URL and image copied to clipboard."
            fi
            _notify "${notification_args[@]}" "$notification_title" "$notification_body"
        fi
    fi
}

share_main "$@"
