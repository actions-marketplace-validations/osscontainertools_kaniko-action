#!/bin/sh
# Runs kaniko directly when the job already runs in a kaniko image, such as a
# Kubernetes runner, and in its own container through Docker otherwise.
set -eu

if [ -x /kaniko/executor ]; then
  root="$GITHUB_WORKSPACE"
  out="$RUNNER_TEMP/kaniko-$$"
  results="$out"
else
  root=/workspace
  out=/kaniko/out
  results="$RUNNER_TEMP/kaniko-$$"
fi
mkdir -p "$results"

case "$INPUT_DOCKERFILE" in
  /*) dockerfile="$INPUT_DOCKERFILE" ;;
  *) dockerfile="$root/$INPUT_CONTEXT/$INPUT_DOCKERFILE" ;;
esac

set -- \
  --context="$root/$INPUT_CONTEXT" \
  --dockerfile="$dockerfile" \
  --destination="$INPUT_DESTINATION" \
  --target="$INPUT_TARGET" \
  --push-retry="$INPUT_RETRIES" \
  --image-download-retry="$INPUT_RETRIES" \
  --image-fs-extract-retry="$INPUT_RETRIES" \
  --predefined-annotations="$INPUT_PREDEFINED_ANNOTATIONS" \
  --reproducible="$INPUT_REPRODUCIBLE" \
  --cache="$INPUT_CACHE" \
  --credential-helpers=env \
  --image-name-with-digest-file="$out/image"

while IFS= read -r arg; do
  if [ -n "$arg" ]; then
    set -- "$@" "--build-arg=$arg"
  fi
done <<EOF
$INPUT_BUILD_ARGS
EOF

if [ "$INPUT_PUSH" = true ]; then
  if [ "$INPUT_PROVENANCE" = true ]; then
    set -- "$@" --provenance --index-file="$out/index"
  fi
else
  set -- "$@" --no-push --no-push-cache
fi

# shellcheck disable=SC2086 # extra-args holds several flags
set -- "$@" $INPUT_EXTRA_ARGS

if [ -x /kaniko/executor ]; then
  /kaniko/executor "$@"
else
  env_names="GITHUB_ACTIONS GITHUB_REPOSITORY GITHUB_SHA GITHUB_REF GITHUB_REF_NAME GITHUB_HEAD_REF GITHUB_SERVER_URL GITHUB_WORKFLOW GITHUB_JOB GITHUB_RUN_ID GITHUB_RUN_ATTEMPT KANIKO_GHCR_IO_USER KANIKO_GHCR_IO_PASSWORD"
  env_names="$env_names $(env | sed -n 's/^\(\(FF_\)\{0,1\}KANIKO_[A-Z0-9_]*\)=.*/\1/p' | tr '\n' ' ')"
  env_flags=""
  for name in $env_names; do
    env_flags="$env_flags --env $name"
  done
  config_flags=""
  if [ -f "$HOME/.docker/config.json" ]; then
    config_flags="--volume $HOME/.docker/config.json:/kaniko/.docker/config.json:ro"
  fi
  # shellcheck disable=SC2086 # the flag lists are word-split on purpose
  cid=$(docker create $env_flags $config_flags --volume "$GITHUB_WORKSPACE:/workspace:ro" "$INPUT_IMAGE" "$@")
  trap 'docker rm --force "$cid" > /dev/null' EXIT
  docker start --attach "$cid"
  status=$(docker inspect --format '{{.State.ExitCode}}' "$cid")
  if [ "$status" != 0 ]; then
    exit "$status"
  fi
  docker cp "$cid:$out/." "$results"
fi

if [ "$INPUT_PUSH" = true ]; then
  ref=$(head -n 1 "$results/image")
  if [ -s "$results/index" ]; then
    ref="${ref%@*}@sha256:$(sha256sum "$results/index" | cut -d ' ' -f 1)"
  fi
  echo "image=$ref" >> "$GITHUB_OUTPUT"
fi
