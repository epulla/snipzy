---
name: release
description: Use when user asks to cut or publish a release, or invokes /release.
---
# Release

1. Verify working tree clean, on `main`, and synced with `origin/main`: run `git fetch`, then compare local and remote commits.
2. Get latest tag: `git describe --tags --abbrev=0`.
3. Propose next semver from Conventional Commits since that tag (`feat` → minor, `fix` → patch, `!` or `BREAKING CHANGE` → major). Show commit list and get user confirmation of version.
4. Run `make test`.
5. Update README download link to `releases/download/vX.Y.Z/Snipzy-X.Y.Z.zip`, commit `docs: bump download link to vX.Y.Z` on `main`, then run `git push origin main`.
6. Create lightweight tag `git tag vX.Y.Z`, then push `git push origin vX.Y.Z`.
7. Get run ID with `gh run list --workflow release.yml -L 1`, then run `gh run watch <id> --exit-status`.
8. Confirm `gh release view vX.Y.Z` shows `.zip` and `.sha256` assets.

Never force-push or retag/move an existing tag. Stop and report on any failure.
