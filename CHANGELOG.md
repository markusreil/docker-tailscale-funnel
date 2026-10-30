# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.1.1] - 2026-10-30

### Fixed

- Resolve entrypoint symlink before locating `funnel.sh` so `/entrypoint.sh` starts instead of dying on line 4.

## [0.1.0] - 2026-10-30

### Added

- Reset retry on every start (`FUNNEL_RESET_RETRIES`/`FUNNEL_RESET_DELAY`), WARNING-loud on total failure.
- Version baked into the image (`VERSION`/`GIT_SHA` env plus OCI labels), resolved from git tags.
- `publish.sh` with per-project registry set in `registries`.
- Robot Framework suites with mock `tailscale`/`docker`, covering toggles, target/path changes, reset retry, retry-until-approval, backend wait, full entrypoint boot, and publish version resolution.

### Security

- Funnel state is reset on every start, so a disabled flag or changed target can never inherit a stale rule.
