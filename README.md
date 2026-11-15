# kaniko action

A GitHub Action that builds container images with [kaniko](https://github.com/osscontainertools/kaniko), without Docker privileges. kaniko's source and issue tracker are at [osscontainertools/kaniko](https://github.com/osscontainertools/kaniko).

The workflows in [`.github/workflows/`](.github/workflows/) are this repository's tests, and each one is a working example, see [Examples](#examples).

## Build an image

Builds `Dockerfile` in the workspace and pushes it to `ghcr.io/<owner>/<repo>:<branch or tag>`. Pushing to ghcr.io needs only `packages: write`.

```yaml
permissions:
  contents: read
  packages: write

jobs:
  image:
    runs-on: ubuntu-26.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - id: build
        uses: osscontainertools/kaniko-action@58c7a9b907d8c089ff81c5335d129107d57f8e25 # v1.0.0
      - run: echo "pushed ${{ steps.build.outputs.image }}"
```

The `image` output is the pushed image pinned by digest, `repo@sha256:...`. With provenance on, the default, it is the digest of the index that carries the attestation.

The action works the same on GitHub's hosted runners and on Kubernetes runners without Docker. On Kubernetes, run the job in the kaniko image. JavaScript actions such as `actions/checkout` do not run there, and without a checkout kaniko clones the triggering commit itself:

```yaml
jobs:
  image:
    runs-on: arc-runner-set
    container: ghcr.io/osscontainertools/kaniko:v1.29.1-debug
    steps:
      - uses: osscontainertools/kaniko-action@58c7a9b907d8c089ff81c5335d129107d57f8e25 # v1.0.0
```

## Build a multi-arch image

| | One job, emulated | One runner per platform |
|---|---|---|
| Use | the action with `platforms` | the reusable workflow `multiarch.yml` |
| Speed | native for the runner's platform, `RUN` steps of the others run under QEMU | native for every platform |
| Runners | one runner with Docker | one runner with Docker per platform |

Both push each platform as `<destination>-<arch>`, merge them into one index at `destination`, and hand it on as the `image` output.

One job, emulated:

```yaml
      - id: build
        uses: osscontainertools/kaniko-action@58c7a9b907d8c089ff81c5335d129107d57f8e25 # v1.0.0
        with:
          platforms: linux/amd64,linux/arm64
```

One runner per platform, at native speed. The workflow runs as a job of its own, and later jobs read `needs.<job>.outputs.image`:

```yaml
jobs:
  image:
    uses: osscontainertools/kaniko-action/.github/workflows/multiarch.yml@58c7a9b907d8c089ff81c5335d129107d57f8e25 # v1.0.0
    permissions:
      contents: read
      packages: write
  deploy:
    needs: image
    runs-on: ubuntu-26.04
    steps:
      - run: echo "deploying ${{ needs.image.outputs.image }}"
```

By default it builds `linux/amd64` and `linux/arm64` on GitHub's `ubuntu-26.04` and `ubuntu-26.04-arm` runners. On your own runners, set `runners`, for example `'{"linux/amd64": "arc-amd64", "linux/arm64": "arc-arm64"}'`.

## Defaults

The action retries pulls, base image extraction and the push three times, attaches a SLSA provenance attestation, and annotates the image with the commit it was built from. Each of these is an input, see [`action.yml`](action.yml).

## Examples

| Example | Shows |
|---|---|
| [`test-build.yml`](.github/workflows/test-build.yml) | Build args and a Dockerfile stage on a hosted runner |
| [`test-container.yml`](.github/workflows/test-container.yml) | A job inside the kaniko image, as on Kubernetes, without a checkout |
| [`test-multiarch-emulated.yml`](.github/workflows/test-multiarch-emulated.yml) | A multi-arch image in one job, emulated |
| [`test-multiarch.yml`](.github/workflows/test-multiarch.yml) | A multi-arch image with one runner per platform |
| [`test-bootstrap.yml`](.github/workflows/test-bootstrap.yml) | A build of kaniko itself, or of any image with files in `/kaniko` or `/busybox` |

For flags without an input, use `extra-args`, see kaniko's [flag reference](https://github.com/osscontainertools/kaniko#additional-flags). For registries other than ghcr.io, log in beforehand, for example with `docker/login-action`, or see [Pushing to Different Registries](https://github.com/osscontainertools/kaniko#pushing-to-different-registries).
