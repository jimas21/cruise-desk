# Releasing

Every build that reaches TestFlight is named `X.Y.Z (N)`, for example `1.1.0 (3)`.

- **Version** `X.Y.Z`: `MARKETING_VERSION` in `project.yml`, three numbers, MAJOR.MINOR.PATCH. Only
  release-please changes it (the line carries the `x-release-please-version` marker).
- **Build** `N`: the run number of the TestFlight workflow, raised above any build App Store Connect already
  holds for that version (`ci/asc_setup.py`). It only goes up and is never reused.

The app shows both as "Version X.Y.Z (N)" in Settings and in the footer of the status sheet. The build number
is never part of the version.

## Every change that ships is its own release

A push to main is read as Conventional Commits.

- If it holds a `feat`, `fix` or `perf` commit (or a breaking change), the Release workflow makes a new
  version straight away. It opens the release pull request, merges it, tags `vX.Y.Z`, writes the GitHub
  release and the `CHANGELOG.md` entry, and starts the TestFlight workflow on that tag.
- TestFlight builds it as `X.Y.Z (N)`. The `vX.Y.Z` tag is the only tag. The TestFlight run stops if the tag
  and `project.yml` disagree.
- A push with only `ci`, `docs`, `chore`, `refactor`, `test`, `build` or `style` commits makes no release
  and no build.
- Several commits in one push make one release.

## The next number

From 1.0.0 on:

- `fix` or `perf` raises the last number (1.1.0 to 1.1.1).
- `feat` raises the middle number and resets the last (1.1.1 to 1.2.0).
- A breaking change (`feat!:` or a `BREAKING CHANGE:` footer) raises the first number (1.2.0 to 2.0.0).
- A push with several of these takes the biggest step.
- The build is at least the TestFlight workflow's latest run number plus one.

Before pushing, work out both, for example "this push makes 1.1.1 (4)".

## History

`release-please-config.json` has a `bootstrap-sha`: the commit build 1 was made from. Commits before it are
never counted. The manifest started at 1.0.0 because builds 1 and 2 were both called 1.0.0; build 2's artwork
rolled into 1.1.0.

## Building again without a change

Only when an upload failed. In Actions, pick TestFlight, then Run workflow, and choose the latest `vX.Y.Z`
tag (or run `gh workflow run testflight.yml --ref vX.Y.Z`). It repeats that version with the next build number.
Running it on `main` makes a build labelled "manual build", not a release. A real change ships as the next
release instead.

## If a run fails

- Release run: re-run it from the Actions tab. It tags a merged release pull request first, then starts the
  build.
- TestFlight run that hit an Apple network blip: re-run the failed job, or rebuild from the tag.
- A real defect ships as the next `fix` release.

## One-time repository settings

Settings > Actions > General > Workflow permissions: read and write, and "Allow GitHub Actions to create and
approve pull requests". The Release workflow needs both.

## Never

- Edit `MARKETING_VERSION` by hand.
- Create `v*` tags or GitHub releases by hand.
- Put the build number into the version.
