#!/bin/sh
#
# Common utilities for bootstrap and maintenance scripts
#
# This file is sourced by scripts that need shared functionality.
# When sourced, variables like $0 and $@ refer to the calling script.
#

# ==============================================================================
# ROOT CHECK
# ==============================================================================
# Ensure the script runs as root, re-execute with elevated privileges if needed
# This must be executed (not a function) because it uses exec to replace the process

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root."
    
    # Try doas first (preferred on Alpine)
    if command -v doas >/dev/null 2>&1; then
        echo "Re-executing with doas..."
        exec doas "$0" "$@"
    # Try sudo next
    elif command -v sudo >/dev/null 2>&1; then
        echo "Re-executing with sudo..."
        exec sudo "$0" "$@"
    # Fall back to su (requires root password)
    else
        echo "Re-executing with su..."
        exec su -c "'$0' $*"
    fi
fi
