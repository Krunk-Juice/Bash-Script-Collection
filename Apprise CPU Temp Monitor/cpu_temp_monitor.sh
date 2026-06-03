#!/bin/bash

# Function to get the CPU temperature
get_cpu_temp() {
    # Get the CPU temperature, remove the decimals and return it
    temp=$(vcgencmd measure_temp | egrep -o '[0-9]*\.[0-9]*')
    echo "$temp"
}

# Set the temperature threshold
TEMP_THRESHOLD=50.0

# Apprise API endpoint on the host
APPRISE_API_URL="http://localhost:8001/notify/----------------------------------------------------------------"

# Main loop to continuously monitor temperature
while true; do
    # Get current CPU temperature
    temp=$(get_cpu_temp)
    
    # Check if the temperature is equal to or exceeds the threshold
    if (( $(echo "$temp >= $TEMP_THRESHOLD" | bc -l) )); then
        # Prepare the notification message with the Discord webhook in the body
        notification_data=$(cat << _EOF
{
    "urls": "discord://-------------------/------------------------------------------------------------------------------------",
    "title": "Raspberry Pi CPU Temperature Alert!",
    "body": "**Warning:** CPU reached temperature threshold: **$TEMP_THRESHOLD°C**\n\n### Current Temperature:\n> $temp°C"
}
_EOF
        )
        
        # Send the notification using Apprise API via a POST request
        curl -X POST "$APPRISE_API_URL" \
             -H "Content-Type: application/json" \
             -d "$notification_data"
    fi

    # Sleep for a while before checking again (e.g., every 60 seconds)
    sleep 60
done
