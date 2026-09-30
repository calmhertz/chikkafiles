#!/bin/bash

image_error(){
    echo "[E] - $1"
}

image_note(){
    echo "[I] - $1"
}

image_warn(){
    echo "[W] - $1"
}

image_mime(){
    file -ib "$1" 2>/dev/null | awk -F'[;/]' '{print $2}'
}

image_is_heif(){
    case "$(image_mime "$1")" in
        heic|heif|heif-sequence|heifs|avif|avifs) return 0 ;;
        *) return 1 ;;
    esac
}

image_is_encoder_native(){
    case "${1,,}" in
        *.jpg|*.jpeg|*.png) return 0 ;;
        *) return 1 ;;
    esac
}

image_valid_icc(){
    [[ "$(dd if="$1" bs=1 skip=36 count=4 2>/dev/null)" == "acsp" ]]
}

image_valid_exif(){
    local head
    head="$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')"
    case "$head" in
        49492a00|4d4d002a) return 0 ;;
        *) return 1 ;;
    esac
}

image_bit_depth(){
    case "$1" in
        *p12le|*p12be) echo 12 ;;
        *p10le|*p10be) echo 10 ;;
        *48le|*48be|*64le|*64be|*16le|*16be) echo 16 ;;
        *) echo 8 ;;
    esac
}

image_meta_of(){
    awk -F' : ' -v tag="$1" 'index($1, tag) { print $2; exit }' <<< "$img_meta"
}

image_probe_source(){
    img_meta="$(exiftool -fast -n -G1 -s \
        -ColorPrimaries -TransferCharacteristics -MatrixCoefficients \
        -AuxiliaryImageType \
        -XMP-hdrgm:Version \
        -XMP-GContainer:DirectoryItemSemantic \
        -ICC_Profile:ProfileDescription \
        -Orientation \
        "$1" 2>/dev/null)"

    img_src_primaries="$(image_meta_of ColorPrimaries)"
    img_src_transfer="$(image_meta_of TransferCharacteristics)"
    img_src_matrix="$(image_meta_of MatrixCoefficients)"
    img_src_aux="$(image_meta_of AuxiliaryImageType)"
    img_src_gainmap="$(image_meta_of Version)"
    img_src_semantic="$(image_meta_of DirectoryItemSemantic)"
    img_src_profile="$(image_meta_of ProfileDescription)"
    img_src_orientation="$(image_meta_of Orientation)"
    img_src_icc_bytes="$(exiftool -fast -b -ICC_Profile "$1" 2>/dev/null | wc -c)"
    img_src_exif_bytes="$(exiftool -fast -b -EXIF "$1" 2>/dev/null | wc -c)"
    img_src_xmp_bytes="$(exiftool -fast -b -XMP "$1" 2>/dev/null | wc -c)"
}

image_declared_size(){
    local size
    if image_is_heif "$1"; then
        size="$(heif-info "$1" 2>/dev/null |
            awk '$1 == "image:" && /primary/ { split($2, d, "x"); print d[1] "x" d[2]; exit }')"
    else
        size="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
            -of csv=p=0:s=x "$1" 2>/dev/null | head -n 1)"
    fi

    [[ "$size" =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]] || return 1
    echo "$size"
}

image_read_frame(){
    local probe
    probe="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,pix_fmt \
        -of csv=p=0 "$1" 2>/dev/null | head -n 1)"
    [[ -n "$probe" ]] || return 1

    IFS=, read -r img_width img_height img_pix_fmt <<< "$probe"
    [[ "$img_width" =~ ^[0-9]+$ && "$img_height" =~ ^[0-9]+$ ]] || return 1
    (( img_width > 0 && img_height > 0 )) || return 1
}

image_source_depth(){
    local src="$1" depth

    if image_is_heif "$src"; then
        depth="$(heif-info "$src" 2>/dev/null | awk '
            $1 == "image:" && /primary/ { primary = 1; next }
            primary && $1 == "image:" { primary = 0 }
            primary && $1 == "bit" && $2 == "depth:" { print $3; exit }')"
        if [[ "$depth" =~ ^[0-9]+$ ]]; then
            echo "$depth"
            return 0
        fi
    fi

    image_bit_depth "$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=pix_fmt -of csv=p=0 "$src" 2>/dev/null | head -n 1)"
}

image_plan_alpha(){
    local src="$1" fmt="$2" ymin

    case "$fmt" in
        rgba|argb|abgr|bgra|ya8|ya8le|gbrap|pal8|yuva*) ;;
        *) img_alpha="no"; return 0 ;;
    esac

    ymin="$(ffmpeg -v error -i "$src" -frames:v 1 \
        -vf "alphaextract,format=gray,signalstats,metadata=print:key=lavfi.signalstats.YMIN:file=-" \
        -f null - 2>/dev/null |
        sed -n 's/.*YMIN=\([0-9][0-9]*\).*/\1/p' | head -n 1)"

    if [[ -z "$ymin" ]]; then
        img_alpha="no"
    elif (( ymin >= 255 )); then
        img_alpha="no"
    else
        img_alpha="yes"
    fi
}

image_decode(){
    local src="$1" work="$2"

    if image_is_heif "$src"; then
        heif-convert --quiet "$src" "$work/source.png" > /dev/null 2>&1 || return 1
        img_input="$work/source.png"
        return 0
    fi

    if image_is_encoder_native "$src"; then
        img_input="$src"
        return 0
    fi

    ffmpeg -y -loglevel error -noautorotate -i "$src" -frames:v 1 -c:v png \
        "$work/source.png" > /dev/null 2>&1 || return 1
    img_input="$work/source.png"
}

image_resize(){
    local src="$1" out="$2" filter

    if (( img_width > img_height )); then
        filter="scale=-2:$IMAGE_MAX_EDGE"
    else
        filter="scale=$IMAGE_MAX_EDGE:-2"
    fi

    ffmpeg -y -loglevel error -i "$src" -vf "$filter" -frames:v 1 -c:v png \
        "$out" > /dev/null 2>&1 || return 1
    img_input="$out"
}

image_has_gainmap(){
    [[ "$img_src_aux" == *gainmap* || "$img_src_aux" == *GainMap* ||
        -n "$img_src_gainmap" || "$img_src_semantic" == *GainMap* ]]
}

image_classify(){
    if [[ "$img_src_transfer" == "16" || "$img_src_transfer" == "18" ]]; then
        img_colour="hdr"
    elif image_has_gainmap; then
        img_colour="gainmap"
    elif [[ -n "$img_src_transfer" && "$img_src_transfer" != "2" ]]; then
        img_colour="sdr"
    else
        img_colour="sdr-unsignalled"
    fi
}

image_plan_matrix(){
    if [[ -n "$img_src_matrix" && "$img_src_matrix" != "2" ]]; then
        img_matrix="$img_src_matrix"
    elif (( img_height > 576 )); then
        img_matrix=1
    else
        img_matrix=6
    fi
}

image_plan_cicp(){
    if [[ -n "$img_src_transfer" && "$img_src_transfer" != "2" ]]; then
        img_primaries="${img_src_primaries:-2}"
        if [[ "$img_primaries" == "2" ]]; then
            case "$img_src_transfer" in
                16|18) img_primaries=9 ;;
                *)
                    img_primaries=1
                    image_warn "colour primaries are unspecified, falling back to BT.709"
                    ;;
            esac
        fi
        img_cicp="$img_primaries/$img_src_transfer/$img_matrix"
    elif (( img_src_icc_bytes > 0 )); then
        img_cicp="2/2/$img_matrix"
    else
        img_cicp="1/13/$img_matrix"
        image_warn "no colour metadata found, falling back to sRGB"
    fi

    img_cicp_transfer="${img_cicp#*/}"
    img_cicp_transfer="${img_cicp_transfer%%/*}"
}

image_plan_encode(){
    img_quality="${IMAGE_QUALITY:-80}"
    img_speed="${IMAGE_SPEED:-6}"
    img_lossless=0
    img_yuv="420"

    [[ "$img_alpha" == "yes" ]] && img_yuv="444"

    if (( img_depth_src > 8 )); then
        img_depth=10
        (( img_depth_src >= 12 )) && img_depth=12
    else
        img_depth=8
    fi

    [[ "$img_colour" == "hdr" ]] && (( img_depth < 10 )) && img_depth=10

    if [[ "${IMAGE_LOSSLESS:-0}" == "1" ]]; then
        img_lossless=1
        img_yuv="444"
    fi
}

image_plan_metadata(){
    local work="$1"

    img_icc_file=""
    if (( img_src_icc_bytes > 0 )); then
        exiftool -fast -b -ICC_Profile "$img_source" > "$work/profile.icc" 2>/dev/null
        image_valid_icc "$work/profile.icc" && img_icc_file="$work/profile.icc"
    fi

    img_exif_file=""
    if (( img_src_exif_bytes > 0 )); then
        exiftool -fast -b -EXIF "$img_source" > "$work/source.exif" 2>/dev/null
        image_valid_exif "$work/source.exif" && img_exif_file="$work/source.exif"
    fi

    img_xmp_file=""
    if (( img_src_xmp_bytes > 0 )); then
        exiftool -fast -b -XMP "$img_source" > "$work/source.xmp" 2>/dev/null
        [[ -s "$work/source.xmp" ]] && img_xmp_file="$work/source.xmp"
    fi
}

image_encode(){
    local out="$1"
    local args=(-s "$img_speed")

    if [[ "$img_lossless" == "1" ]]; then
        args+=(-l)
    else
        args+=(-q "$img_quality" --qalpha 100 -d "$img_depth" --yuv "$img_yuv")
    fi

    [[ -n "$img_icc_file" ]] && args+=(--icc "$img_icc_file")
    [[ -n "$img_cicp" ]] && args+=(--cicp "$img_cicp")
    [[ -n "$img_exif_file" ]] && args+=(--exif "$img_exif_file")

    if image_has_gainmap; then
        args+=(--ignore-xmp)
    else
        [[ -n "$img_xmp_file" ]] && args+=(--xmp "$img_xmp_file")
    fi

    avifenc "${args[@]}" "$img_input" "$out" > /dev/null 2>&1
}

image_verify(){
    local out="$1" info field

    [[ -s "$out" ]] || { image_error "encoder produced no output"; return 1; }

    info="$(avifdec --info "$out" 2>/dev/null)"
    [[ -n "$info" ]] || { image_error "output is not a decodable AVIF"; return 1; }

    field="$(sed -n 's/^ \* Resolution *: //p' <<< "$info")"
    if [[ "$field" != "${img_width}x${img_height}" ]]; then
        image_error "output is $field, expected ${img_width}x${img_height}"
        return 1
    fi

    field="$(sed -n 's/^ \* Bit Depth *: //p' <<< "$info")"
    if [[ "$field" != "$img_depth" ]]; then
        image_error "output bit depth is $field, expected $img_depth"
        return 1
    fi

    field="$(sed -n 's/^ \* Alpha *: //p' <<< "$info")"
    if [[ "$img_alpha" == "yes" && "$field" == "Absent" ]]; then
        image_error "alpha channel was dropped"
        return 1
    fi
    if [[ "$img_alpha" == "no" && "$field" != "Absent" ]]; then
        image_error "output has an alpha channel the source did not have"
        return 1
    fi

    if (( img_src_icc_bytes > 0 )); then
        field="$(sed -n 's/^ \* ICC Profile *: //p' <<< "$info")"
        if [[ "$field" != Present* ]]; then
            image_error "embedded ICC profile was not carried into the output"
            return 1
        fi
    fi

    field="$(sed -n 's/^ \* Transfer Char[.] *: //p' <<< "$info")"
    if [[ "$field" != "$img_cicp_transfer" ]]; then
        image_error "output transfer characteristic is $field, expected $img_cicp_transfer"
        return 1
    fi
}

image_report(){
    case "$img_colour" in
        hdr)
            image_note "HDR source kept HDR as a $img_depth-bit AVIF, transfer $img_cicp_transfer"
            ;;
        gainmap)
            image_note "gain-map source encoded as its $img_depth-bit base rendition"
            ;;
        sdr)
            image_note "SDR source kept as a $img_depth-bit AVIF"
            ;;
        sdr-unsignalled)
            image_note "no HDR signalling found, encoded as a $img_depth-bit AVIF"
            ;;
    esac

    if image_has_gainmap; then
        if [[ "$img_colour" == "hdr" ]]; then
            image_warn "the gain map is not carried over, this output only has the base rendition's headroom"
        else
            image_warn "the gain map is not carried over, this output is SDR and will not gain HDR headroom"
        fi
    fi

    (( img_src_icc_bytes > 0 )) &&
        image_note "ICC profile kept -> ${img_src_profile:-unnamed profile}"

    if [[ -n "$img_src_orientation" && "$img_src_orientation" != "1" ]]; then
        image_note "orientation $img_src_orientation kept in metadata, pixels left unrotated"
    fi

    image_note "wrote $1"
}

image_convert(){
    local src="$1" dst="$2" work="$3" declared

    img_source="$src"
    IMAGE_MAX_EDGE="${IMAGE_MAX_EDGE:-0}"
    [[ "$IMAGE_MAX_EDGE" =~ ^[0-9]+$ ]] || IMAGE_MAX_EDGE=0

    [[ -f "$src" && -r "$src" ]] || { image_error "input is not a readable file -> $src"; return 1; }

    image_probe_source "$src"

    img_depth_src="$(image_source_depth "$src")"

    declared="$(image_declared_size "$src")"
    if [[ -z "$declared" ]]; then
        image_error "could not determine the resolution of the primary image -> $src"
        return 1
    fi

    image_decode "$src" "$work" || { image_error "could not decode $src"; return 1; }

    image_read_frame "$img_input" || { image_error "decoded frame of $src is unreadable"; return 1; }

    if [[ "$declared" != "${img_width}x${img_height}" ]]; then
        image_error "decoded ${img_width}x${img_height} but the primary image is $declared, refusing to convert a reduced image"
        return 1
    fi

    if (( IMAGE_MAX_EDGE > 0 )); then
        local shortest="$img_width"
        (( img_height < shortest )) && shortest="$img_height"
        if (( shortest > IMAGE_MAX_EDGE )); then
            image_resize "$img_input" "$work/resized.png" ||
                { image_error "could not resize $src"; return 1; }
            image_read_frame "$img_input" || { image_error "resized frame is unreadable"; return 1; }
            image_note "short edge limited to $IMAGE_MAX_EDGE, now ${img_width}x${img_height}"
        fi
    fi

    image_plan_alpha "$img_input" "$img_pix_fmt"

    image_classify
    image_plan_matrix
    image_plan_cicp
    image_plan_encode
    image_plan_metadata "$work"

    if [[ "$img_colour" == "hdr" && "$img_cicp_transfer" != "16" && "$img_cicp_transfer" != "18" ]]; then
        image_error "HDR source would lose its transfer function, refusing to write an SDR output"
        return 1
    fi

    image_encode "$work/output.avif" || { image_error "avifenc failed on $src"; return 1; }

    image_verify "$work/output.avif" || return 1

    mv "$work/output.avif" "$dst" || { image_error "could not place the output -> $dst"; return 1; }

    image_report "$dst"
}

convert_image(){
    local src="$1" dst="$2" work dir tool
    local required_tools="ffmpeg ffprobe heif-convert heif-info avifenc avifdec exiftool"

    [[ -n "$dst" ]] || { image_error "no output path given for $src"; return 1; }
    [[ -f "$src" && -r "$src" ]] || { image_error "input is not a readable file -> $src"; return 1; }

    for tool in $required_tools; do
        command -v "$tool" > /dev/null 2>&1 ||
            { image_error "required tool is not installed -> $tool"; return 1; }
    done

    dir="${dst%/*}"
    [[ "$dir" == "$dst" ]] && dir="."

    work="$(mktemp -d "$dir/.chikkaimage.XXXXXX")" ||
        { image_error "could not create a work directory in $dir"; return 1; }

    if image_convert "$src" "$dst" "$work"; then
        rm -rf "$work"
        return 0
    fi

    rm -rf "$work"
    return 1
}
