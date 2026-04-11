#!/bin/bash

distro=$(awk -F'=' '/^ID=/ {print $2}' /etc/os-release)

sudo -v
case "$distro" in
    "arch")
        if command -v ffmpeg > /dev/null 2>&1; then
            echo "FFMPEG exists."
        else
            sudo pacman -Syu ffmpeg --noconfirm
        fi
        ;;
    "fedora")
        if command -v ffmpeg > /dev/null 2>&1; then
            echo "FFMPEG exists."
        else
            sudo dnf update
            sudo dnf install ffmpeg -y
        fi
        ;;
    "debian")
        if command -v ffmpeg > /dev/null 2>&1; then
            echo "FFMPEG exists."
        else
            sudo apt-get update
            sudo apt-get install ffmpeg -y
        fi
        ;;
    *)
        echo "[E] - Unknown or Unsupported Distro -> $distro"
        ;;
esac

