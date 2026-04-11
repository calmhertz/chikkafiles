#!/bin/bash

get_filetype() {
    file -ib "$1" | awk -F'/' '{print $1}'
}

std_title(){
    title="${1%.*}"
    snake_case="${title// /_}"
    lower_snake_case="${snake_case,,}"
    echo "$lower_snake_case"
}

perform_compression(){

    file_name="${1##*/}"
    dir_path="${1%/*}"

    if [[ -f "$INSTALL_DIR/process.lock" ]]; then
        echo "[E] - Last compression process did not exit gracefully."
        exit
    fi

    echo "$1" > "$INSTALL_DIR/process.lock" 
    chmod 700 "$INSTALL_DIR/process.lock"
    case "$(get_filetype "$1")" in
        "video")
            echo "Compressing $file_name"
            ffmpeg -y -i "$1" -c:v libaom-av1 -crf 30 -cpu-used 4 -tile-columns 2 -tile-rows 1 -vf "scale=-2:1080,fps=fps=30" -c:a libopus -b:a 64k "$dir_path/$(std_title "$file_name").mkv" > /dev/null 2>&1
            echo "Finished compressing $1"
            ;;

        "audio")
            echo "Compressing $1"
            ffmpeg -y -i "$1" -vn -c:a libopus -b:a 64k -vbr on "$dir_path/$(std_title "$file_name").opus" > /dev/null 2>&1
            echo "Finished compressing $1"
            ;;

        "image")
            echo "Compressing $1"
            ffmpeg -y -i "$1" -vf "scale='if(gt(min(iw,ih),2160),if(gt(iw,ih),-2,2160),iw)':'if(gt(min(iw,ih),2160),if(gt(iw,ih),2160,-2),ih)'" -c:v libaom-av1 -crf 34 -cpu-used 4 -pix_fmt yuv420p10 "$dir_path/$(std_title "$file_name").avif" > /dev/null 2>&1
            echo "Finished compressing $1"
            ;;

        *)
            echo "[E] - Unknown filetype. -> $1"
            ;;
    esac
    rm "$INSTALL_DIR/process.lock"

    if [[ ! -d "$dir_path/original_files" ]]; then
        mkdir -p "$dir_path/original_files"
    fi

    mv "$1" "$dir_path/original_files"
    return 0
}

