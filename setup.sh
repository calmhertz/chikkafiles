#!/bin/bash

install_packages(){
    local distro ffmpeg_pkg heif_pkg avif_pkg exiftool_pkg
    local install=()

    distro=$(awk -F'=' '/^ID=/ {print $2}' /etc/os-release)

    case "$distro" in
        "arch")
            ffmpeg_pkg="ffmpeg"
            heif_pkg="libheif"
            avif_pkg="libavif"
            exiftool_pkg="perl-image-exiftool"
            ;;
        "fedora")
            ffmpeg_pkg="ffmpeg"
            heif_pkg="libheif-tools"
            avif_pkg="libavif-tools"
            exiftool_pkg="perl-Image-ExifTool"
            ;;
        "debian")
            ffmpeg_pkg="ffmpeg"
            heif_pkg="libheif-examples"
            avif_pkg="libavif-bin"
            exiftool_pkg="libimage-exiftool-perl"
            ;;
        *)
            echo "[E] - Unknown or Unsupported Distro -> $distro"
            return
            ;;
    esac

    if ! command -v ffmpeg > /dev/null 2>&1; then
        echo "[I] - ffmpeg missing."
        install+=("$ffmpeg_pkg")
    fi
    if ! command -v heif-convert > /dev/null 2>&1; then
        echo "[I] - heif-convert missing."
        install+=("$heif_pkg")
    fi
    if ! command -v avifenc > /dev/null 2>&1; then
        echo "[I] - avifenc missing."
        install+=("$avif_pkg")
    fi
    if ! command -v exiftool > /dev/null 2>&1; then
        echo "[I] - exiftool missing."
        install+=("$exiftool_pkg")
    fi

    if [[ "${#install[@]}" -eq 0 ]]; then
        echo "[I] - ffmpeg, libheif, libavif and Image-ExifTool are installed."
        return
    fi

    sudo -v
    case "$distro" in
        "arch")
            sudo pacman -Syu "${install[@]}" --noconfirm
            ;;
        "fedora")
            sudo dnf update
            sudo dnf install -y "${install[@]}"
            ;;
        "debian")
            sudo apt-get update
            sudo apt-get install -y "${install[@]}"
            ;;
    esac
}

install_packages
