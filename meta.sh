#!/bin/bash

if [[ ! -f "$INSTALL_DIR/compress.sh" ]]; then
    echo "[E] - Missing helper script. -> compress.sh"
    exit
fi
source "$INSTALL_DIR/compress.sh"

need_processing() {
    format=""
    case "$(get_filetype "$1")" in
        "video")
            format="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$1")"
            ;;

        "audio")
            format="$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$1")"
            ;;

        "image")
            format="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$1")"
            ;;

        *)
            format="unknown"
            echo "unknown"
            return
            ;;
    esac

    if [[ "$format" != "av1" && "$format" != "opus" && "$format" != "avif" ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

check_time() {
    local cur_h=$((10#$(date +%H)))
    local cur_m=$((10#$(date +%M)))
    local cur_s=$((10#$(date +%S)))
    local cur=$(( (cur_h * 3600) + (cur_m * 60) + cur_s ))

    local start_h=$((10#${START_TIME:0:2}))
    local start_m=$((10#${START_TIME:2:2}))
    local start=$(( (start_h * 3600) + (start_m * 60) ))

    local end_h=$((10#${END_TIME:0:2}))
    local end_m=$((10#${END_TIME:2:2}))
    local end=$(( (end_h * 3600) + (end_m * 60) ))

    local in_range=0
    if (( start <= end )); then
        [[ $cur -ge $start && $cur -le $end ]] && in_range=1
    else
        [[ $cur -ge $start || $cur -le $end ]] && in_range=1
    fi

    if (( in_range == 1 )); then
        echo "yes"
    elif (( cur < start )); then
        if (( start <= end || cur > end )); then
            echo $(( start - cur ))
        else
            echo "yes"
        fi
    else
        echo $(( (86400 - cur) + start ))
    fi
}
