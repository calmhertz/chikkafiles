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
