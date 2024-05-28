#!/bin/sh

USERNAME="${WM_USERNAME:-dave_voutila_redpanda}"
PASSWORD="${WM_PASSWORD}"
RAW_TOKEN=token.json

if [ -z "${PASSWORD}" ]; then
    echo "you didn't set your password (WM_PASSWORD env var)" 1>&2
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "jq not found" 1>&2
    exit 1
fi

# TODO: check if token needs refresh or not
if [ ! -f "${RAW_TOKEN}" ]; then
    curl -L https://auth.enterprise.wikimedia.com/v1/login \
         -H "Content-Type: application/json" \
         -d "{\"username\":\"${USERNAME}\", \"password\":\"${PASSWORD}\"}" \
        | tee "${RAW_TOKEN}"
fi

# Split token into key parts
for key in `jq -r 'keys[]' < "${RAW_TOKEN}"`; do
    jq -r ".${key}" < "${RAW_TOKEN}" > "auth/${key}"
done
