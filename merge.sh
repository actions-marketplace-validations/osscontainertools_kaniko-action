#!/bin/sh
# Merges the per-platform images in MERGE_IMAGES, one reference per line, into
# one index at MERGE_DESTINATION and prints it pinned by digest. Needs crane
# and jq, as in the merge image.
set -eu

if [ -f /docker-config/config.json ]; then
  mkdir -p "$HOME/.docker"
  cp /docker-config/config.json "$HOME/.docker/config.json"
fi
if [ -n "${KANIKO_GHCR_IO_PASSWORD:-}" ]; then
  echo "$KANIKO_GHCR_IO_PASSWORD" | crane auth login ghcr.io -u "$KANIKO_GHCR_IO_USER" --password-stdin > /dev/null 2>&1
fi

work=$(mktemp -d)
: > "$work/descriptors"
first=""
for ref in $MERGE_IMAGES; do
  crane manifest "$ref" > "$work/manifest.json"
  if [ -z "$first" ]; then
    first="$ref"
    cp "$work/manifest.json" "$work/first.json"
  fi
  if jq -e '.manifests' "$work/manifest.json" > /dev/null; then
    jq -c '.manifests[]' "$work/manifest.json" >> "$work/descriptors"
  else
    crane config "$ref" > "$work/config.json"
    jq -c --arg digest "$(crane digest "$ref")" --argjson size "$(wc -c < "$work/manifest.json")" --slurpfile config "$work/config.json" \
      '{mediaType, digest: $digest, size: $size, platform: ($config[0] | {os, architecture} + (if .variant then {variant} else {} end))}' \
      "$work/manifest.json" >> "$work/descriptors"
  fi
done
if [ -z "$first" ]; then
  echo "no per-platform images to merge" >&2
  exit 1
fi

jq -s --slurpfile first "$work/first.json" \
  '{schemaVersion: 2, mediaType: "application/vnd.oci.image.index.v1+json", manifests: .} + ($first[0] | if .annotations then {annotations} else {} end)' \
  "$work/descriptors" > "$work/index.json"
crane edit manifest "$first" --tag "$MERGE_DESTINATION" < "$work/index.json" > /dev/null

repo="${MERGE_DESTINATION%@*}"
case "${repo##*/}" in
  *:*) repo="${repo%:*}" ;;
esac
echo "$repo@$(crane digest "$MERGE_DESTINATION")"
