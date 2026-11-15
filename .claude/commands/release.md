---
model: sonnet
effort: medium
---

Release the kaniko GitHub Action.

Usage: `/release [<version>]`

Repository: `osscontainertools/kaniko-action` on github.com.

1. **Sync main.** `git switch main && git pull --ff-only`. Stop if the working tree is dirty.

2. **Require green workflows.** Every run for `main`'s HEAD must have succeeded:
   ```bash
   gh run list --repo osscontainertools/kaniko-action --commit "$(git rev-parse HEAD)" --json workflowName,conclusion --jq '.[] | "\(.workflowName) \(.conclusion)"'
   ```
   Stop on anything but `success`, and on a missing run.

3. **List the changes.** `prev=$(git describe --tags --abbrev=0 --match 'v*.*.*')`, then `git log --oneline $prev..HEAD` and `git diff $prev -- action.yml build.sh merge.sh .github/workflows/multiarch.yml`. Without a previous tag, the release is `v1.0.0`.

4. **Choose the version.** Tags are `v<major>.<minor>.<patch>`. If `<version>` was given, check it against these rules and stop on a mismatch:
   - Major: an input, output or workflow input removed or renamed, an accepted value removed, a default changed in a way that breaks existing workflows.
   - Minor: a new input, output, workflow input or accepted value.
   - Patch: fixes, pinned image bumps, docs and tests only.

5. **Check the pins.**
   - `gh actions-lock --no-fix` passes.
   - The `image` and `bootstrap-image` defaults in `action.yml` name the same kaniko version.
   - The `merge-image` defaults in `action.yml` and `.github/workflows/multiarch.yml` are identical and pull without credentials:
     ```bash
     ref=$(grep -A2 '^  merge-image:' action.yml | sed -n 's/.*default: //p')
     T=$(curl -s "https://gitlab.com/jwt/auth?service=container_registry&scope=repository:osscontainertools/components/kaniko/merge:pull" | jq -r .token)
     curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $T" -H "Accept: application/vnd.oci.image.index.v1+json" "https://registry.gitlab.com/v2/osscontainertools/components/kaniko/merge/manifests/${ref#*@}"
     ```
     Stop unless it prints `200`.
   - If `name` in `action.yml` changed, it must not match any Marketplace action (`https://github.com/marketplace?type=actions&query=<name>`), case-insensitively, nor a GitHub user or organization (`gh api users/<name>` must return 404).

6. **Write the release notes.** First line: `Ships kaniko v<kaniko-version>.` Then the sections that apply, in this order: `Breaking`, `Added`, `Fixed`, `Changed`. One line per change, naming the input, output or workflow and what a user observes. No em dashes, no semicolons. For a major, state for each breaking change what users have to edit in their workflows.

7. **Show the version and notes to the user and wait for approval.** Do not tag before.

8. **Tag.** The tag message becomes the release notes. `--cleanup=verbatim` keeps the `## ` headings. The `release` workflow then moves the major tag, such as `v1`, to the same commit and publishes the GitHub release:
   ```bash
   git tag -a --cleanup=verbatim <version> -F <notes-file>
   git push origin <version>
   ```
   Wait for the `release` run of the tag and stop if it fails.

9. **Publish to the Marketplace.** Ask the user to open the release's edit page, tick "Publish this Action to the GitHub Marketplace" and save. The CLI cannot do this.

10. **Pin the README examples.** Replace every `osscontainertools/kaniko-action@...` and `osscontainertools/kaniko-action/.github/workflows/multiarch.yml@...` reference in `README.md` with `@<commit> # <version>`, where `<commit>` is `git rev-parse <version>^{}`. Also update the comments in the test workflows that name what a user writes. Commit and push to `main`.

11. **Verify.** The release page shows the notes, `git ls-remote --tags origin` lists `<version>` and `<major>` on the same commit, and the Marketplace listing shows `<version>`. Report the release URL.
