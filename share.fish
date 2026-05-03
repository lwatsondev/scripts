#!/usr/bin/fish

function _notify
    command -q notify-send; and notify-send --app-name share $argv; or true
end

function _log
    set -f level $argv[1]
    set -f message $argv[2..]

    switch $level
        case INFO
            set level_color green
        case WARN
            set level_color yellow
        case ERROR
            set level_color red
        case DEBUG
            set level_color cyan
        case '*'
            log_error "Invalid log level "$level"" 1>&2
            return
    end

    begin
        printf "%s" "["
        isatty stderr; and set_color $level_color
        printf "%s" "$level"
        isatty stderr; and set_color normal
        printf "] %s\n" "$message"
    end 1>&2
end

function log_info
    _log INFO $argv
end

function log_warn
    _log WARN $argv
end

function log_error
    set -f options \
        (fish_opt --short e --long exit --required-val)

    argparse --stop-nonopt $options -- $argv
    or return

    _log ERROR $argv
    if set -q __notify_on_error
        _notify -u critical "share encountered an error." "$argv"
    end

    if set -q _flag_e
        exit $_flag_e
    end
end

function log_debug
    set -q WPSTE_DEBUG; and _log DEBUG $argv 1>&2
end

function _print_help
    log_info "A simple grimshot wrapper for https://github.com/TheReverend403/pste with support for editing before upload."
    log_info "Usage: share [-t|--target <active|screen|output|area|window>] [-c|--copy] [-n|--notify] [-e|--edit] [file]"
    exit 0
end

function _is_image
    set -f file $argv[1]
    set -f mimetype (xdg-mime query filetype "$file")
    string match "image/*" "$mimetype"
end

function _check_requirements
    set -f required_commands rehome-cli mpv notify-send grimshot wl-copy swappy oxipng

    if not set -q WAYLAND_DISPLAY
        log_error --exit 1 "WAYLAND_DISPLAY is not set. share expects a Wayland environment."
    end

    for requirement in $required_commands
        if not command -q "$requirement"
            log_error --exit 1 "Missing requirement: $requirement"
        else
            log_debug "Found requirement: $requirement"
        end
    end
end

function _play_sound
    set -f sound_file "camera-shutter.oga"
    set -f sound_file "/usr/share/sounds/freedesktop/stereo/$sound_file"

    if test -f "$sound_file"
        mpv --no-video --no-terminal "$sound_file" &
    else
        log_warn "_play_sound: $sound_file not found."
    end
end

function _take_screenshot
    set -f target $argv[1]
    set -f save_path (mktemp --tmpdir --suffix=.png XXXXX)

    set -f grimshot_output (grimshot save "$target" "$save_path" 2>&1)
    set -f grimshot_status $status
    log_debug "grimshot: $grimshot_output"
    if not test $grimshot_status -eq 0
        if string match -q "selection cancelled" "$grimshot_output"
            # Capitalise the s, add a period.
            log_info (string replace -r "^s" "S" "$grimshot_output.")
            exit 0
        end
        log_error --exit $grimshot_status "Grimshot error: $grimshot_output"
    end

    _play_sound
    set -f oxipng_output (oxipng --strip safe "$save_path" 2>&1); and log_debug "oxipng: $oxipng_output"
    echo "$save_path"
end

function _upload_file
    set -f options \
        (fish_opt --short f --long file --required-val)

    argparse $options -- $argv
    or return

    if not set -q _flag_f
        log_error --exit 2 "_upload_file: Expected --file."
    end

    if not test -f "$_flag_f"
        log_error --exit 1 "$_flag_f does not exist."
    end

    log_debug "Uploading $_flag_f"
    set -f url (rehome-cli "$_flag_f")
    set -f upload_status $status

    test $upload_status -eq 0; or log_error --exit $upload_status "$url"
    echo "$url"
end

function _copy_to_clipboard
    set -f options \
        (fish_opt --short f --long file --required-val) \
        (fish_opt --short t --long text --required-val)

    argparse $options -- $argv
    or return

    if not set -q _flag_f; and not set -q _flag_t
        log_error --exit 2 "_copy_to_clipboard: Expected at least one of --text or --file."
    end

    if set -q _flag_t
        wl-copy "$_flag_t"; or log_error --exit $status "Failed to copy $_flag_t to the clipboard."
    end

    if set -q _flag_f
        set -l mimetype (_is_image "$_flag_f")
        if test $status -eq 0
            log_debug "Copying $_flag_f to primary clipboard"
            # Hardcoded to image/png for now otherwise certain apps don't support pasting non-png images.
            # https://github.com/bugaevc/wl-clipboard/issues/8
            # https://github.com/bugaevc/wl-clipboard/issues/71
            wl-copy --primary --type image/png <"$_flag_f"; or log_error --exit $status "Failed to copy $_flag_f to the clipboard."
        else
            log_debug "$_flag_f is not an image. Not copying to clipboard."
        end
    end
end


function share_main
    _check_requirements

    set -f options \
        (fish_opt --short h --long help) \
        (fish_opt --short c --long copy) \
        (fish_opt --short n --long notify) \
        (fish_opt --short e --long edit) \
        (fish_opt --short t --long target --required-val)
    argparse --name=share --stop-nonopt $options -- $argv
    or return

    test (count $argv) -eq 1; and set -f _flag_f $argv[1]

    log_debug "_flag_h: $_flag_h"
    log_debug "_flag_c: $_flag_c"
    log_debug "_flag_n: $_flag_n"
    log_debug "_flag_t: $_flag_t"
    log_debug "_flag_f: $_flag_f"

    set -q _flag_h; and _print_help

    set -q _flag_n; and set -g __notify_on_error

    if set -q _flag_t
        set -l valid_targets active screen output area window
        if not contains "$_flag_t" $valid_targets
            set -l valid_targets (string join ", " $valid_targets)
            log_error --exit 2 -- "--target must be one of $valid_targets."
        end
    else
        set -f _flag_t output
    end

    if not set -q _flag_f
        set -f _flag_f (_take_screenshot "$_flag_t")
    end

    if set -q _flag_e
        if not _is_image "$_flag_f" >/dev/null
            log_warn "Ignoring --edit because $_flag_f is not an image."
        else
            swappy -f "$_flag_f" -o "$_flag_f"; or log_error --exit $status "Editing image failed."
        end
    end

    set -f url (_upload_file --file "$_flag_f")
    set url (string replace -r "^http:" "https:" "$url")

    if set -q _flag_c
        _copy_to_clipboard --text "$url" --file "$_flag_f"
        if set -q _flag_n
            set -l notification_title "URL copied to clipboard."
            set -l notification_args
            if _is_image "$_flag_f" >/dev/null
                set -p notification_title "Image and"
                set notification_args --icon "$_flag_f"
            end
            _notify $notification_args "$notification_title" "$url"
        end
    end

    echo "$url"
end

share_main $argv
