#!/bin/sh

: ${FAKE_EMAIL_SPOOL:=/messages}

mkdir -p "$FAKE_EMAIL_SPOOL"

count=$(cat /email/.index 2> /dev/null || echo 1)
filename=$(printf "%s/msg-%04d.txt" "$FAKE_EMAIL_SPOOL" "$count")
echo "Writing message to $filename"
cat > "$filename"
