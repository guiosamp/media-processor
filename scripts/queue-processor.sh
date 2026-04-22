#!/bin/bash

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
QUEUE_DIR="${SCRIPT_DIR}/queue"
HOOK_SCRIPT="${SCRIPT_DIR}/qbittorrent-hook-host.sh"

mkdir -p "$QUEUE_DIR"

for job in "${QUEUE_DIR}"/*.job; do
  [ -f "$job" ] || continue

  content_path=$(grep '^PATH='     "$job" | cut -d'=' -f2-)
  torrent_hash=$(grep '^HASH='     "$job" | cut -d'=' -f2-)
  category=$(    grep '^CATEGORY=' "$job" | cut -d'=' -f2-)

  rm -f "$job"

  [ -z "$content_path" ] && continue

  "$HOOK_SCRIPT" "$content_path" "$torrent_hash" "${category:-filmes}"
done
