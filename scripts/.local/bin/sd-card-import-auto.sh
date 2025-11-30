#!/bin/bash
# Auto-triggered SD card import script
# Waits for SD card to be mounted, then runs the import script

set -euo pipefail

# Wait a bit for the system to mount the card
sleep 3

# Run the import script
exec "$HOME/.local/bin/sd-card-import.sh"

