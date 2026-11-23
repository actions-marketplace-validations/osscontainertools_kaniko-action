#!/bin/sh
# Signs each image of SIGN_IMAGES, a JSON array or object of references, with
# cosign and, with SIGN_SBOM, attaches a signed SPDX SBOM to each of its
# platforms, unless they carry one of the same signer already.
# Keyless, the same signer is the same workflow and ref, and cosign requests an
# ID token for each signature, as a scan can outlast one. Needs cosign, crane,
# jq and syft, as in the sign image.
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

for image in $(printf '%s' "$SIGN_IMAGES" | jq -r '.[]'); do
  # shellcheck disable=SC2086 # the flag list is word-split on purpose
  if cosign verify $verify_flags "$image" > /dev/null 2>&1; then
    echo "$image is signed already"
  else
    cosign sign "$@" "$image"
  fi

  if [ "$SIGN_SBOM" != true ]; then
    continue
  fi
  platforms=$(crane manifest "$image" | jq -r --arg d "${image#*@}" \
    '[.manifests[]? | select(.platform.os != "unknown") | .digest] | if length == 0 then [$d] else . end | .[]')
  for digest in $platforms; do
    ref="${image%@*}@$digest"
    # shellcheck disable=SC2086 # the flag list is word-split on purpose
    if cosign verify-attestation --type spdxjson $verify_flags "$ref" > /dev/null 2>&1; then
      echo "$ref has an SBOM already"
      continue
    fi
    syft scan -q "registry:$ref" -o spdx-json=/tmp/sbom.json
    cosign attest "$@" --type spdxjson --predicate /tmp/sbom.json "$ref"
  done
done
