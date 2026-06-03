#!/bin/sh

LOG_FILE="/home/ubuntu/.uur/log/uur.log"
LOCK_FILE="/tmp/logtrim_uur.lock"

MAX_SIZE=$((1024 * 1024))       # 1 MB
TARGET_SIZE=$((MAX_SIZE / 4))   # 25% of 1 MB (256 KB)

# Use flock to prevent concurrent execution
exec 9>"$LOCK_FILE"
flock -n 9 || {
    echo "[INFO] Another instance is running. Exiting."
    exit 0
}

# Exit if file doesn't exist
[ -f "$LOG_FILE" ] || exit 0

# Get file size in bytes
FILE_SIZE=$(wc -c < "$LOG_FILE")

# If under limit, do nothing
[ "$FILE_SIZE" -le "$MAX_SIZE" ] && exit 0

echo "[INFO] Log file exceeds 1MB. Trimming to 25% using binary search..."

TMP_FILE=$(mktemp)

# Get separator line numbers
set -- $(grep -n '^========== .* ==========$' "$LOG_FILE" | cut -d: -f1)

SEP_COUNT=$#

# If fewer than 2 separators, don't trim
[ "$SEP_COUNT" -lt 2 ] && {
    echo "[WARN] Not enough separators to safely trim."
    rm -f "$TMP_FILE"
    exit 0
}

# Binary search bounds
LOW=1
HIGH=$SEP_COUNT
BEST_LINE=""

while [ "$LOW" -le "$HIGH" ]; do
    MID=$(( (LOW + HIGH) / 2 ))

    eval "LINE=\${$MID}"

    tail -n +"$LINE" "$LOG_FILE" > "$TMP_FILE"
    NEW_SIZE=$(wc -c < "$TMP_FILE")

    if [ "$NEW_SIZE" -le "$TARGET_SIZE" ]; then
        BEST_LINE=$LINE
        HIGH=$((MID - 1))
    else
        LOW=$((MID + 1))
    fi
done

if [ -n "$BEST_LINE" ]; then
    tail -n +"$BEST_LINE" "$LOG_FILE" > "$TMP_FILE"
    FINAL_SIZE=$(wc -c < "$TMP_FILE")

    mv "$TMP_FILE" "$LOG_FILE"
    echo "[INFO] Log trimmed successfully. New size: $FINAL_SIZE bytes"
    exit 0
fi

echo "[WARN] Could not trim enough data while preserving structure."
rm -f "$TMP_FILE"
exit 1
