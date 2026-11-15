# kaniko action

A GitHub Action that builds container images with [kaniko](https://github.com/osscontainertools/kaniko), without Docker privileges. kaniko's source and issue tracker are on GitHub at [osscontainertools/kaniko](https://github.com/osscontainertools/kaniko).

The workflows in [`.github/workflows/`](.github/workflows/) are this repository's tests, and each one is a working example, see [Examples](#examples).

## Usage

Builds `Dockerfile` in the workspace and pushes it to `ghcr.io/<owner>/<repo>:<branch or tag>`. Pushing to ghcr.io needs only `packages: write`.

```yaml
permissions:
  contents: read
  packages: write

jobs:
  image:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - id: build
        uses: osscontainertools/kaniko-action@v1
      - run: echo "pushed ${{ steps.build.outputs.image }}"
```

The `image` output is the pushed image pinned by digest, `repo@sha256:...`. With provenance on, the default, it is the digest of the index that carries the attestation.

## Runners

The action works on two kinds of runners:

- **Virtual machines** with Docker, such as GitHub's hosted runners. The action runs kaniko in its own container. `image` selects the kaniko version.
- **Kubernetes**, such as runner scale sets without Docker. The job runs in the kaniko image, and the action runs kaniko directly:

  ```yaml
  jobs:
    image:
      runs-on: arc-runner-set
      container: ghcr.io/osscontainertools/kaniko:v1.29.1-debug
      steps:
        - uses: osscontainertools/kaniko-action@v1
  ```

  JavaScript actions such as `actions/checkout` do not run in the kaniko image. Without a checkout, kaniko clones the triggering commit itself and builds `context` from it.

## Defaults

The action retries pulls, base image extraction and the push three times, attaches a SLSA provenance attestation, and annotates the image with the commit it was built from. Each of these is an input, see [`action.yml`](action.yml).

## Examples

| Example | Shows |
|---|---|
| [`test-build.yml`](.github/workflows/test-build.yml) | Build args and a Dockerfile stage on a hosted runner |
| [`test-container.yml`](.github/workflows/test-container.yml) | A job inside the kaniko image, as on Kubernetes, without a checkout |

For flags without an input, use `extra-args`, see kaniko's [flag reference](https://github.com/osscontainertools/kaniko#additional-flags). For registries other than ghcr.io, log in beforehand, for example with `docker/login-action`, or see [Pushing to Different Registries](https://github.com/osscontainertools/kaniko#pushing-to-different-registries).
