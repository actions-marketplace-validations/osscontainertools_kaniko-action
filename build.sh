#!/bin/sh
# Runs kaniko directly when the job already runs in a kaniko image, such as a
# Kubernetes runner, and in its own container through Docker otherwise.
set -eu

results="$RUNNER_TEMP/kaniko-$$"
mkdir -p "$results"
if [ -x /kaniko/executor ]; then
  direct=true
  root="$GITHUB_WORKSPACE"
  out="$results"
else
  direct=false
  root=/workspace
  out=/kaniko/out
fi

image="$INPUT_IMAGE"
if [ "$INPUT_BOOTSTRAP" = true ]; then
  image="$INPUT_BOOTSTRAP_IMAGE"
  KANIKO_DIR=/kaniko2
  export KANIKO_DIR
fi

# Without a checkout, as in a Kubernetes job that runs no JavaScript actions,
# kaniko clones the triggering commit itself.
if [ -d "$GITHUB_WORKSPACE/$INPUT_CONTEXT" ]; then
  context="$root/$INPUT_CONTEXT"
  case "$INPUT_DOCKERFILE" in
    /*) dockerfile="$INPUT_DOCKERFILE" ;;
    *) dockerfile="$context/$INPUT_DOCKERFILE" ;;
  esac
  set --
else
  context="git://${GITHUB_SERVER_URL#*://}/$GITHUB_REPOSITORY.git#$GITHUB_REF#$GITHUB_SHA"
  dockerfile="$INPUT_DOCKERFILE"
  set -- --context-sub-path="$INPUT_CONTEXT"
  GIT_USERNAME=x-access-token
  GIT_PASSWORD="$INPUT_GITHUB_TOKEN"
  export GIT_USERNAME GIT_PASSWORD
fi

set -- "$@" \
  --context="$context" \
  --dockerfile="$dockerfile" \
  --target="$INPUT_TARGET" \
  --push-retry="$INPUT_RETRIES" \
  --image-download-retry="$INPUT_RETRIES" \
  --image-fs-extract-retry="$INPUT_RETRIES" \
  --predefined-annotations="$INPUT_PREDEFINED_ANNOTATIONS" \
  --reproducible="$INPUT_REPRODUCIBLE" \
  --cache="$INPUT_CACHE" \
  --credential-helpers=env

while IFS= read -r arg; do
  if [ -n "$arg" ]; then
    set -- "$@" "--build-arg=$arg"
  fi
done <<EOF
$INPUT_BUILD_ARGS
EOF

# shellcheck disable=SC2086 # extra-args holds several flags
set -- "$@" $INPUT_EXTRA_ARGS

# Builds one image and writes it, pinned by digest, to $results/<name>/ref.
# Arguments: destination, platform or empty, name, then the shared flags.
build() {
  destination="$1"
  platform="$2"
  name="$3"
  shift 3
  set -- "$@" --destination="$destination" --image-name-with-digest-file="$out/$name/image"
  if [ -n "$platform" ]; then
    set -- "$@" --custom-platform="$platform"
  fi
  if [ "$INPUT_PUSH" = true ]; then
    if [ "$INPUT_PROVENANCE" = true ]; then
      set -- "$@" --provenance --index-file="$out/$name/index"
    fi
  else
    set -- "$@" --no-push --no-push-cache
  fi

  if [ "$direct" = true ]; then
    mkdir -p "$out/$name"
    /kaniko/executor "$@"
  else
    env_names="GITHUB_ACTIONS GITHUB_REPOSITORY GITHUB_SHA GITHUB_REF GITHUB_REF_NAME GITHUB_HEAD_REF GITHUB_SERVER_URL GITHUB_WORKFLOW GITHUB_JOB GITHUB_RUN_ID GITHUB_RUN_ATTEMPT KANIKO_GHCR_IO_USER KANIKO_GHCR_IO_PASSWORD GIT_USERNAME GIT_PASSWORD"
    env_names="$env_names $(env | sed -n 's/^\(\(FF_\)\{0,1\}KANIKO_[A-Z0-9_]*\)=.*/\1/p' | tr '\n' ' ')"
    env_flags=""
    for env_name in $env_names; do
      env_flags="$env_flags --env $env_name"
    done
    config_flags=""
    if [ -f "$HOME/.docker/config.json" ]; then
      config_flags="--volume $HOME/.docker/config.json:/kaniko/.docker/config.json:ro"
    fi
    # shellcheck disable=SC2086 # the flag lists are word-split on purpose
    cid=$(docker create $env_flags $config_flags --volume "$GITHUB_WORKSPACE:/workspace:ro" "$image" "$@")
    status=0
    docker start --attach "$cid" || status=$?
    if [ "$status" = 0 ]; then
      status=$(docker inspect --format '{{.State.ExitCode}}' "$cid")
    fi
    if [ "$status" = 0 ]; then
      docker cp "$cid:$out/." "$results"
    fi
    docker rm --force "$cid" > /dev/null
    if [ "$status" != 0 ]; then
      exit "$status"
    fi
  fi

  if [ "$INPUT_PUSH" = true ]; then
    ref=$(head -n 1 "$results/$name/image")
    if [ -s "$results/$name/index" ]; then
      ref="${ref%@*}@sha256:$(sha256sum "$results/$name/index" | cut -d ' ' -f 1)"
    fi
    echo "$ref" > "$results/$name/ref"
  fi
}

if [ -z "$INPUT_PLATFORMS" ]; then
  build "$INPUT_DESTINATION" "" image "$@"
  if [ "$INPUT_PUSH" = true ]; then
    echo "image=$(cat "$results/image/ref")" >> "$GITHUB_OUTPUT"
  fi
  exit 0
fi

if [ "$direct" = true ]; then
  echo "platforms needs a runner with Docker to emulate the other architectures. On Kubernetes, use the multiarch workflow with a native runner per platform." >&2
  exit 1
fi

platforms=$(echo "$INPUT_PLATFORMS" | tr ',' ' ')
arches=$(for platform in $platforms; do printf '%s,' "$(echo "$platform" | cut -d / -f 2)"; done)
docker run --privileged --rm "$INPUT_BINFMT_IMAGE" --install "${arches%,}"

leaves=""
for platform in $platforms; do
  suffix=$(echo "${platform#*/}" | tr '/' '-')
  build "$INPUT_DESTINATION-$suffix" "$platform" "$suffix" "$@"
  if [ "$INPUT_PUSH" = true ]; then
    leaves="$leaves $(cat "$results/$suffix/ref")"
  fi
done

if [ "$INPUT_PUSH" = true ]; then
  config_flags=""
  if [ -f "$HOME/.docker/config.json" ]; then
    config_flags="--volume $HOME/.docker/config.json:/docker-config/config.json:ro"
  fi
  # shellcheck disable=SC2086 # the flag list is word-split on purpose
  merged=$(docker run --rm $config_flags \
    --env MERGE_IMAGES="$leaves" --env MERGE_DESTINATION="$INPUT_DESTINATION" \
    --env KANIKO_GHCR_IO_USER --env KANIKO_GHCR_IO_PASSWORD \
    --volume "$GITHUB_ACTION_PATH/merge.sh:/merge.sh:ro" --entrypoint sh \
    "$INPUT_MERGE_IMAGE" /merge.sh)
  echo "image=$merged" >> "$GITHUB_OUTPUT"
fi
