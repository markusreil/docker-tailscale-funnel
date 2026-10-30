# AGENTS.md

Short project rules for agents working in this repo. See `README.md` and
`DOCKER-IMAGE-SPEC.md` for detail.

- `Dockerfile` stays top-level; everything it copies lives under `docker/`.
- Shell behavior lives in sourced `docker/*.sh` modules (testable without a
  container); the entrypoint owns boot only (daemon, traps, readiness wait).
- Env defaults via `: "${VAR:=default}"`; `funnel_once` codes: `0` ok or
  disabled no-op, `1` serve failed (retried), `2` missing config.
- Every start resets funnel state first; total reset failure warns on stderr
  but never blocks boot. Disabled means nothing published.
- External CLIs go through `${TOOL_BIN}` variables; tests substitute the
  `test/mocks/` fakes (`MOCK_MODE`, `MOCK_FAIL_RESET`). No test may touch a
  real tailnet.
- Reports to `test/out/` (gitignored) via `robot --outputdir test/out test/`.
- Versions come from git tags (`vX.Y.Z`); `registries` is the tracked
  registry set, `./publish.sh` pushes to it. Dirty worktree never publishes;
  `latest` only from exact tags. `docker/` holds only image content.
- Keep `CHANGELOG.md` (Keep a Changelog, `## [Unreleased]`) updated with
  every change.
- Verify: `sh -n` on scripts, Robot suite, `docker build`.
