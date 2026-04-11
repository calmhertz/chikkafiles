#!/bin/bash

if [[ ! -f "$INSTALL_DIR/meta.sh" ]]; then
    echo "[E] - Missing helper script. -> meta.sh"
    exit
fi
source "$INSTALL_DIR/meta.sh"

perform_cycle(){
    echo "[I] - Starting Cycle. -> "$1""

    if [[ ! -d $1 ]]; then
        echo "[E] - Directory does not exist. -> $1"
        exit
    fi

    for entry in "$1"/*; do
        leafdir="$(echo "$entry" | awk -F'/' '{print $NF}')"
        [ -e "$entry" ] || continue
        if [[ "$leafdir" == "original_files" || "$leafdir" == "chikkafiles" ]]; then
            continue
        fi

        if [[ -d "$entry" ]]; then
            perform_cycle "$entry"
        else
            needed="$(need_processing "$entry")"
            if [[ "$needed" == "yes" ]]; then
                perform_compression "$entry"
                sleep "$BREAK_TIME"
            fi
        fi
    done
}

daemon_run(){

    if [[ -z "$SLEEP_TIME" || "$SLEEP_TIME" == "" ]]; then
        echo "[E] - SLEEP_TIME environment variable not set, considering default 86400"
        SLEEP_TIME=86400
    fi
    if [[ -z "$BREAK_TIME" || "$BREAK_TIME" == "" ]]; then
        echo "[E] - BREAK_TIME environment variable not set, considering default 300"
        BREAK_TIME=300
    fi

    if [[ ! -f "$INSTALL_DIR/compress.sh" ]]; then
        echo "[E] - Missing helper script. -> compress.sh"
        exit
    fi

    if [[ -f "$INSTALL_DIR/process.lock" ]]; then
        retry_file="$(cat "$INSTALL_DIR/process.lock")"
        echo "[I] - process.lock found, retrying. -> $retry_file"
        mv "$INSTALL_DIR/process.lock" "$INSTALL_DIR/process.lock.back"
        if perform_compression "$retry_file"; then
            rm "$INSTALL_DIR/process.lock.back"
        fi
    fi

    while true; do
        perform_cycle "$CHIKKAFILES_DIR"
        echo "Going to Sleep"
        sleep "$SLEEP_TIME"
    done
}
