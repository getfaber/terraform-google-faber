# Contributing

Thanks for helping. For anything bigger than a small fix, please [open an issue](https://github.com/getfaber/terraform-google-faber/issues) first so we can agree on the approach.

## Checks

CI runs these on every pull request. To run them locally:

```sh
terraform fmt -recursive
terraform init -backend=false && terraform validate
terraform test                 # Terraform 1.11 or later; plan-only, no cloud credentials needed
tflint --init && tflint --recursive
trivy config .
shellcheck scripts/setup.sh
terraform-docs .               # refreshes the inputs/outputs tables in README.md
```

Keep `scripts/setup.sh` in step with the module: the same defaults, validation and handoff output.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org): `fix:` for a patch release, `feat:` for a minor release, and `feat!:` or a `BREAKING CHANGE:` footer for a major release. `chore:`, `docs:`, `ci:` and `test:` don't trigger a release.

## Releases

[release-please](https://github.com/googleapis/release-please) opens a release pull request whenever releasable commits land on `main`. Merging it tags the release (`vX.Y.Z`), which the Terraform Registry picks up automatically. It also updates `CHANGELOG.md` and the version in `locals.tf` and `scripts/setup.sh`.

To force a specific version, push a commit to `main` with a `Release-As: X.Y.Z` footer.

Repository setup this relies on:

- **Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests"** must be on.
- Release pull requests are opened with the default `GITHUB_TOKEN`, so CI doesn't run on them automatically. If branch protection requires checks, re-run CI on the release PR (for example, close and reopen it) or use a GitHub App token in `.github/workflows/release-please.yml`.
