#!/bin/bash

set -euo pipefail

error-msg() {
    echo "Setting date and time failed with status $?. Exiting..." | tee /dev/kmsg >&2
}

trap error-msg ERR

while [ ! -f "/home/.timezone_set" ]; do
    echo "Waiting for timezone to be set..." | tee /dev/kmsg
  sleep 5
done

set_date_time() {
    while true; do
        echo "Attempting to set date and time..." | tee /dev/kmsg
        DATE_TIME=$(curl -sI http://www.google.com | grep -Fi Date: | cut -d' ' -f3-6)
        FMT_DATE_TIME=$(date -d "$DATE_TIME GMT" '+%Y-%m-%d %H:%M:%S' || continue)
        echo "Retrieved time from Google: $FMT_DATE_TIME" | tee /dev/kmsg
        date -s "$FMT_DATE_TIME" && break
        sleep 5
    done
}

set_date_time

echo "Date and time set successfully..." | tee /dev/kmsg