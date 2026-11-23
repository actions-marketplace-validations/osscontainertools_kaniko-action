#!/bin/sh
# Signs SIGN_IMAGE with cosign, unless it carries a signature of the same
# signer already. Keyless, the same signer is the same workflow and ref, read
# from SIGN_ID_TOKEN, and cosign requests its own ID token through
# ACTIONS_ID_TOKEN_REQUEST_URL. Needs cosign, crane and jq, as in the sign
# image.
set -euf

if [ -f /docker-config/config.json ]; then
  mkdir -p "$HOME/.docker"
  cp /docker-config/config.json "$HOME/.docker/config.json"
fi
if [ -n "${KANIKO_GHCR_IO_PASSWORD:-}" ]; then
  echo "$KANIKO_GHCR_IO_PASSWORD" | crane auth login ghcr.io -u "$KANIKO_GHCR_IO_USER" --password-stdin > /dev/null
fi

set -- --yes
verify_flags=""
if [ "$SIGN_TLOG" = false ]; then
  set -- "$@" --use-signing-config=false --tlog-upload=false
  verify_flags="--insecure-ignore-tlog"
fi
if [ "$SIGN_COSIGN" = key ]; then
  set -- "$@" --key "$SIGN_KEY"
  cosign public-key --key "$SIGN_KEY" > /tmp/cosign.pub
  verify_flags="$verify_flags --key /tmp/cosign.pub"
else
  verify_flags="$verify_flags $(printf %s "$SIGN_ID_TOKEN" | jq -rR --arg server "$SIGN_SERVER_URL" 'split(".")[1] | gsub("-"; "+") | gsub("_"; "/") | . + "==="[0:(4 - length % 4) % 4] | @base64d | fromjson |
    "--certificate-identity=\($server)/\(.job_workflow_ref) --certificate-oidc-issuer=\(.iss)"')"
fi

# shellcheck disable=SC2086 # the flag list is word-split on purpose
if cosign verify $verify_flags "$SIGN_IMAGE" > /dev/null 2>&1; then
  echo "$SIGN_IMAGE is signed already"
else
  cosign sign "$@" "$SIGN_IMAGE"
fi
