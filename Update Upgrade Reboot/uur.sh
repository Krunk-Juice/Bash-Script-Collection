#!/bin/bash

LOGFILE="/home/ubuntu/.uur/log/uur.log"
WEBHOOK_FILE="/home/ubuntu/.uur/.webhook"

HOSTNAME=$(hostname)
UPTIME=$(uptime -p)

REBOOT_REQUIRED=false

touch "$LOGFILE"

echo "========== $(date) ==========" >> $LOGFILE

log() {
    echo "$1" | tee -a $LOGFILE
}

# Read webhook URL
if [ -f "$WEBHOOK_FILE" ]; then
    WEBHOOK_URL=$(cat "$WEBHOOK_FILE")
else
    log "[ERROR] Webhook file not found!"
    exit 1
fi

send_discord_embed() {
    TITLE="$1"
    DESCRIPTION="$2"
    COLOR="$3"

    curl -s -H "Content-Type: application/json" -X POST \
    -d "{
        \"embeds\": [{
            \"title\": \"$TITLE\",
            \"description\": \"$DESCRIPTION\",
            \"color\": $COLOR,
            \"footer\": {
                \"text\": \"Server: $HOSTNAME | Uptime: $UPTIME\"
            },
            \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
        }]
    }" \
    "$WEBHOOK_URL" > /dev/null
}

log "[INFO] Running apt update..."

if ! sudo apt update >> $LOGFILE 2>&1; then
    log "[ERROR] apt update failed"
    send_discord_embed "❌ Update Failed" \
    "apt update failed. Check logs on VPS." 16711680
    exit 1
fi

# DRY RUN
log "[INFO] Running dry-run upgrade check..."

DRY_RUN_OUTPUT=$(sudo apt upgrade -s 2>&1)
echo "$DRY_RUN_OUTPUT" >> $LOGFILE

# Extract package list
UPGRADE_LIST=$(echo "$DRY_RUN_OUTPUT" | awk '/^Inst / {print $2}' | tr '\n' ',' | sed 's/,$//')

# Detect risky situations
if echo "$DRY_RUN_OUTPUT" | grep -qE "The following packages have been kept back"; then
    log "[WARNING] Packages held back (manual review recommended)"

    send_discord_embed "⚠️ Manual Intervention Required" \
    "Some packages were kept back.\n\nPackages:\n\`\`\`$UPGRADE_LIST\`\`\`\n\nRun:\n\`\`\`sudo apt full-upgrade\`\`\`" \
    16776960

    exit 0
fi

# Check if upgrades exist
APT_UPDATED=false

if echo "$DRY_RUN_OUTPUT" | grep -q "0 upgraded, 0 newly installed"; then
    log "[INFO] No packages to upgrade"

    UPGRADE_LIST="None"

else
    log "[INFO] Packages to upgrade: $UPGRADE_LIST"

    APT_UPDATED=true
    REBOOT_REQUIRED=true
fi

# REAL UPGRADE
if [ "$APT_UPDATED" = true ]; then

    log "[INFO] Performing upgrade..."

    UPGRADE_OUTPUT=$(timeout --preserve-status 1800 sudo apt upgrade -y 2>&1)
    UPGRADE_EXIT=$?

    echo "$UPGRADE_OUTPUT" >> $LOGFILE

    if [ $UPGRADE_EXIT -eq 124 ]; then
        log "[ERROR] apt upgrade timed out"

        send_discord_embed "⚠️ Upgrade Stuck (Timeout)" \
        "Upgrade likely waiting for input." \
        16776960

        exit 1

    elif [ $UPGRADE_EXIT -ne 0 ]; then
        log "[ERROR] apt upgrade failed"

        send_discord_embed "❌ Upgrade Failed" \
        "apt upgrade failed." \
        16711680

        exit 1
    fi

else
    log "[INFO] Skipping apt upgrade"
fi
UPGRADE_EXIT=$?

echo "$UPGRADE_OUTPUT" >> $LOGFILE

if [ $UPGRADE_EXIT -eq 124 ]; then
    log "[ERROR] apt upgrade timed out (likely waiting for input)"

    send_discord_embed "⚠️ Upgrade Stuck (Timeout)" \
    "Upgrade likely waiting for input.\n\nRun:\n\`\`\`sudo apt upgrade\`\`\`" \
    16776960

    exit 1

elif [ $UPGRADE_EXIT -ne 0 ]; then
    log "[ERROR] apt upgrade failed"

    send_discord_embed "❌ Upgrade Failed" \
    "apt upgrade failed. Check logs." \
    16711680

    exit 1
fi

# CLEANUP
log "[INFO] Cleaning up..."
sudo apt autoremove -y >> $LOGFILE 2>&1
sudo apt autoclean >> $LOGFILE 2>&1

# DOCKER TRACKING (BEFORE)
log "[INFO] Capturing Docker state (before)..."
BEFORE=$(docker ps --format "{{.Names}} {{.Image}} {{.ID}}")

# DOCKER UPDATE
log "[INFO] Running Docker update script..."
if ! bash /home/ubuntu/bin/compose.sh >> "$LOGFILE" 2>&1; then
    log "[ERROR] Docker update failed"
    send_discord_embed "❌ Docker Update Failed" \
    "Docker update script failed." 16711680
    exit 1
fi

# DOCKER TRACKING (AFTER)
log "[INFO] Capturing Docker state (after)..."
AFTER=$(docker ps --format "{{.Names}} {{.Image}} {{.ID}}")

# Compare and find updated containers
UPDATED_CONTAINERS=""

while read -r line; do
    NAME=$(echo "$line" | awk '{print $1}')
    IMAGE=$(echo "$line" | awk '{print $2}')
    ID=$(echo "$line" | awk '{print $3}')

    OLD_ENTRY=$(echo "$BEFORE" | awk -v name="$NAME" '$1 == name')

    if [ -n "$OLD_ENTRY" ]; then
        OLD_ID=$(echo "$OLD_ENTRY" | awk '{print $3}')

        if [ "$ID" != "$OLD_ID" ]; then
            UPDATED_CONTAINERS+="$NAME ($IMAGE)\n"
        fi
    fi
done <<< "$AFTER"

log "[INFO] Update complete."

# Build final message
DESCRIPTION="Updated packages:\n\`\`\`$UPGRADE_LIST\`\`\`"

if [ -n "$UPDATED_CONTAINERS" ]; then
    DESCRIPTION+="\nUpdated containers:\n\`\`\`\n$UPDATED_CONTAINERS\`\`\`"
    REBOOT_REQUIRED=true
else
    DESCRIPTION+="\nNo containers were updated."
fi

send_discord_embed "✅ Update Successful" "$DESCRIPTION" 65280

# REBOOT CHECK
if [ "$REBOOT_REQUIRED" = true ]; then
    log "[INFO] Changes detected. Rebooting system..."

    send_discord_embed "🔄 Rebooting VPS" \
    "Reboot triggered due to updates.\n\nPackages:\n\`\`\`$UPGRADE_LIST\`\`\`\nContainers:\n\`\`\`\n$UPDATED_CONTAINERS\`\`\`" \
    3447003

    sudo reboot
else
    log "[INFO] No changes detected. No reboot required."
fi
