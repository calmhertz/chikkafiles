#!/bin/bash

set -eo pipefail

source "./env"
if [[ ! -f "$INSTALL_DIR/runtime.sh" && ! -f "$INSTALL_DIR/setup.sh" ]]; then
    echo "[E] - Missing helper scripts. -> runtime.sh, setup.sh"
    exit
fi
source "$INSTALL_DIR/runtime.sh"
source "$INSTALL_DIR/setup.sh"

echo "CHIKKAFILES_DIR = $CHIKKAFILES_DIR"
echo "INSTALL_DIR = $INSTALL_DIR"
echo "SLEEP_TIME = $SLEEP_TIME"
echo "BREAK_TIME = $BREAK_TIME"


if [[ -z "$CHIKKAFILES_DIR" ]]; then
    echo "[E] - CHIKKAFILES_DIR environment variable not set."
    exit
fi

daemon_run 
