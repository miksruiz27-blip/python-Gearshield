#!/bin/bash
TARGET_SIZE=7640952520
FILE="external_datasets/ASVspoof2019_LA/LA.zip"
URL="https://datashare.ed.ac.uk/bitstreams/a9f87c35-f055-4015-80e2-2fdff0d46269/download"
while true; do
  size=$(stat -c%s "$FILE" 2>/dev/null || echo 0)
  if [ "$size" -ge "$TARGET_SIZE" ]; then
    echo "DOWNLOAD_COMPLETE size=$size"
    break
  fi
  echo "[watchdog] intento nuevo, tamano actual=$size ($(date))"
  curl -L -C - --speed-time 20 --speed-limit 51200 --max-time 600 -o "$FILE" "$URL"
  sleep 3
done
