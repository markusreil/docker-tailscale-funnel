# DOCKER-IMAGE-SPEC.md

Guidance for creating a new single-image Docker project from scratch (no
compose file — the image is consumed by another cluster or run standalone).

Follow this document when scaffolding a new image project so the result is
consistent, predictable, and easy for other agents to work on. It mirrors
[COMPOSE-SPEC](COMPOSE-SPEC.md) where the two overlap; compose-specific
rules (proxy contract, `env.example`, profiles) do not apply here.

## Deliverable layout

```
Dockerfile             top-level; FROM, build args, COPY of docker/, HEALTHCHECK, ENTRYPOINT
.dockerignore          excludes test/out/, .git/, and anything not needed at build time
docker/                all context files copied into the image (scripts, templates, etc.)
docker/entrypoint.sh   container boot: daemon start, readiness wait, background setup
docker/*.sh            one file per concern, sourced by the entrypoint (each unit-testable)
                       (only image content lives here — host tooling stays out)
publish.sh             version resolution, multi-tag build, uniform push to every registry
                       (registries as CLI args, overridable default)
registries             the project's registry set, one per line (tracked; CLI args
                       override it for one-off pushes)
README.md              project overview, build steps, env vars, reasoning behind choices
CHANGELOG.md           notable changes, kept in sync with development (see below)
AGENTS.md              short, ongoing project rules for agents working in the repo (see below)
test/                  Robot Framework suite (see below)
test/mocks/            fake binaries standing in for external CLIs (e.g. tailscale)
test/requirements.txt  pinned test dependencies (robotframework>=7)
test/out/              test reports — generated, never tracked (gitignored)
.gitignore             must ignore `test/out/` (plus Robot's `.output.xml` / `.log.html` / `.report.html` fallbacks)
```

* The `Dockerfile` stays at the repo root; everything it copies in lives
  under `docker/`. No scripts, configs, or templates loose at the top level.
* Shell logic is split so every behavior is testable without a running
  container: the entrypoint owns process boot (daemon, traps, waits); each
  `docker/*.sh` module owns one concern and is sourced — never copy-pasted —
  by both the entrypoint and the tests.
* Modules take configuration from environment variables with explicit
  defaults (`: "${VAR:=default}"`), and required variables fail fast with a
  clear message on stderr and a non-zero exit (exit `2` for missing config,
  `1` for retryable operational failure, `0` for success including
  intentionally-disabled no-ops).
* `test/out/` is always gitignored; reports are regenerable via one command.

## Changelog

Create a `CHANGELOG.md` at the project root and follow the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) spec.

* Keep an `## [Unreleased]` section at the top and fill it in **as changes are
  made** — do not batch entries up for a later release.
* The `Unreleased` template carries the standard subsections: `Added`,
  `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`. Add each entry under
  the matching one and leave the unused ones empty.
* Newest entries first within a section; dates are ISO-8601 (`YYYY-MM-DD`).
* **Do not create a release section on your own.** When the user asks for a
  release, move the accumulated `Unreleased` entries into a new
  `## [<version>] - <date>` section (semantic version), leave a fresh empty
  `## [Unreleased]` above it, and keep the sections newest-first.

## AGENTS.md

Create an `AGENTS.md` at the project root: a short summary of this spec, scoped
to the rules that stay relevant **while working in the project**.

* Include the ongoing rules an agent must respect on every change: Dockerfile
  top-level / `docker/` context discipline, module sourcing (no duplicated
  shell logic), env-var defaults and fail-fast codes, mock-based testing
  (`test/out/` gitignored, no real external side effects), changelog
  discipline, and the verification commands.
* Keep it short — a summary, not a copy. Link back to `README.md` for detail
  instead of duplicating it.
* **Exclude anything that only matters during initial project creation**: the
  deliverable layout, the "Creating a new project" steps, and other one-time
  scaffolding guidance stay in this spec only.

## Non-negotiable rules

1. **Dockerfile at the root, context in `docker/`.** The build context files
   the image needs live under `docker/` and are copied with an explicit
   `COPY docker/<file> <dest>` (never `COPY .`). Scripts that must also be
   reachable at a canonical path get a symlink (e.g. `/entrypoint.sh`),
   not a second copy.
2. **Record build provenance in the image.** `ARG` inputs for the base or
   tool versions (with working defaults); `ARG BUILD_DATE=unknown` +
   `ENV BUILD_DATE=${BUILD_DATE}`, stamped at build time with
   `BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) docker build`. A hardcoded
   `ENV BASE_IMAGE=<image>` documents what the image was built `FROM`.
   The project's own version comes from git tags (see rule 9): `ARG
   VERSION=unknown` + `ARG GIT_SHA=unknown`, recorded as `ENV` and as OCI
   labels (`org.opencontainers.image.version`, `.revision`, `.created`).
   The wrapped tool's `--version` cannot identify the wrapper build; the
   labels can.
3. **A HEALTHCHECK that reflects the service.** It must exercise the real
   readiness signal (e.g. daemon status output), not just process existence.
4. **Entrypoint owns boot only; modules own behavior.** The entrypoint
   starts the daemon, traps `TERM`/`INT` for clean shutdown, waits for
   readiness with a bounded loop, then delegates to module functions in the
   background. No business logic inline in the entrypoint — if the tests
   cannot source it, it belongs in a module.
5. **State transitions reset first.** Any module that publishes external
   state (funnel rules, firewall entries, registrations) clears that state
   at the start of every run, so a changed config, a flipped enable flag, or
   a restart can never inherit a stale rule. Disabling a feature must leave
   no trace of it behind.
6. **Side-effecting CLIs are injectable.** Every external binary a module
   invokes goes through a `${TOOL_BIN:=tool}` variable (defaulting to the
   real binary), so tests can substitute a mock with zero code changes.
7. **Retry loops back off patiently and exit cleanly.** Operations that
   depend on out-of-band approval (e.g. admin consent) retry on a
   configurable delay (`RETRY_DELAY` env, sane default) and succeed exactly
   once; disabled features skip the loop entirely with an explanatory message.
8. **README documents build, env vars, and reasoning.** Build steps and args,
   every env var with its default and required-ness, and the reasoning behind
   non-obvious choices (especially security: what is exposed, what the
   defaults publish). Keep it in sync when behavior changes.
9. **Versions come from git tags; one build goes to every registry.**
   Releases are annotated tags `vX.Y.Z`. An exact tag publishes the full
   version plus floating `X.Y`, `X`, and `latest`; any other commit
   publishes `edge` (or `sha-<short>`) and never `latest`. A dirty worktree
   refuses to publish. The registry set differs per project and lives in
   tracked `registries` (one per line); `publish.sh` pushes
   the same tags — the same digest — to all of them. CLI args override the
   file for one-off pushes, never for a different version per remote.
   Registry credentials stay out of the repo (`docker login` beforehand).
   Which registries are official for the project is documented in the README,
   but the file is the source of truth the script reads.

## Testing

Every image project ships a Robot Framework suite. Tests run against the
exact code shipped in the image — never a reimplementation — and must never
produce real external side effects (no live funnels, registrations, or
network calls).

1. **Source the real modules.** Test keywords source `docker/*.sh` directly
   (e.g. `sh -c '. ${FUNNEL} && funnel_once'`) with env vars set per case.
   If a behavior cannot be tested this way, restructure the module until
   it can (see rule 4).
2. **Fake every external CLI.** `test/mocks/` holds executable fakes that
   record their argv to `$MOCK_LOG` and return canned responses selected by
   `$MOCK_MODE` (e.g. `ok`, `fail-once`, `fail-always`, `not-ready`). Modes
   cover success, transient failure (retry path), permanent failure, and
   missing prerequisites. The mock is pointed at via the `${TOOL_BIN}`
   variable from rule 6 — production code paths are untouched.
3. **Cover state transitions, not just steady states.** Beyond "enabled
   serves" / "disabled stays quiet": toggling the enable flag on and off
   across consecutive runs, changing targets/paths between runs, and
   asserting the old state was cleared (reset count, serve counts, and
   reset-before-serve ordering in the mock log).
4. **Reports go to `test/out/`.** Run with
   `robot --outputdir test/out test/`; the directory is gitignored. Pin
   `robotframework` in `test/requirements.txt`.
5. **Robot pitfalls to avoid.** Robot parses any literal `NAME=value` token
   as a named argument — build shell commands containing env assignments in
   a variable first (e.g. via `Catenate`), then pass the variable. Prefer
   `Should Contain X Times` for call counts and `Should Match Regexp` with
   `(?s)` for ordering assertions on the mock log.

## Creating a new project

1. **Nail down the requirements first** — what the image wraps, what it
   publishes or configures at boot, which configuration must be
   per-deployment env vars, and the security posture (what is exposed by
   default — default must be nothing). Write the spec down before scaffolding.
2. **Scaffold the layout**: `Dockerfile`, `.dockerignore`, `docker/` modules
   + entrypoint, `README.md`, `CHANGELOG.md`, `AGENTS.md`, `.gitignore`,
   `test/` suite + mocks + requirements.
3. **Write the modules bottom-up**: one concern per file, env defaults,
   fail-fast codes, reset-first transitions, injectable CLI variables.
   Then the entrypoint: boot, readiness wait, delegate.
4. **Write the Dockerfile**: versioned `ARG`s, provenance `ENV`s,
   explicit `COPY docker/...`, `HEALTHCHECK`, `ENTRYPOINT`.
5. **Write the tests alongside**: mocks first (all modes the modules
   branch on), then steady-state cases, then transition cases.
6. **Verify** (see below).

## Build / test / verify

```sh
pip install -r test/requirements.txt
robot --outputdir test/out test/   # unit suite; no external side effects
docker build -t <image>:test .     # image builds from the same docker/ context
sh -n docker/*.sh test/mocks/*     # shell syntax check (no file extension on mocks is fine)
```

Release path (version resolved from git tags, same digest to every registry):

```sh
docker login                       # once per registry host; credentials never in the repo
./publish.sh                # pushes to every registry in registries
./publish.sh <registry...>  # one-off override; still a single version everywhere
```

| Worktree state | Tags pushed |
| --- | --- |
| Exact annotated tag `vX.Y.Z` | `X.Y.Z`, `X.Y`, `X`, `latest` |
| Anything else | `edge` (or `sha-<short>`), never `latest` |
| Dirty worktree | publish refuses |

## Review checklist

Before finishing a project or change:

1. `Dockerfile` is top-level; nothing is copied from outside `docker/`.
2. Entrypoint contains boot logic only; all behavior lives in sourced modules.
3. Required env vars fail fast with message + distinct exit code; optional
   vars have documented defaults.
4. Every external state change is preceded by a reset; disable leaves nothing behind.
5. Every external CLI is invoked via its `${TOOL_BIN}` variable.
6. `HEALTHCHECK` exercises the real readiness signal.
7. Tests source the real modules, fake all external CLIs, and cover
   enable/disable toggles plus target/path changes with no-leftover assertions.
8. `docker/` holds only image content; host tooling (`publish.sh`,
   `registries`) lives at the root and is never copied into the image.
9. `test/out/` is gitignored; `test/requirements.txt` pins Robot.
10. `docker build` succeeds and the image contains the same files the tests sourced.
11. `CHANGELOG.md` exists, follows Keep a Changelog, and reflects the change
    in its `## [Unreleased]` section.
12. `AGENTS.md` exists and summarizes the ongoing project rules only — no
    one-time scaffolding guidance.
13. Version labels (`VERSION`/`GIT_SHA` + OCI labels) match the tag being
    published; `CHANGELOG.md` carries the release section for the tag.
    Spot-check with `docker buildx imagetools inspect` that every registry
    serves the same digest.
14. `README.md` documents build, env vars, and the reasoning behind
    non-obvious/security-relevant choices, and is in sync with the code.

## Common pitfalls

* Business logic inline in the entrypoint — untestable without booting the
  container; move it to a sourced module.
* Duplicating module logic in tests instead of sourcing the real files —
  tests pass while the shipped code is broken.
* Calling the real CLI in tests (missing `${TOOL_BIN}` override or mock not
  executable) — creates live external state from a test run.
* Publishing without reset-first — a changed target/path or flipped flag
  leaves the old rule live next to the new one.
* Entrypoints that overwrite existing config or state on every start —
  destroys user configuration on restarts.
* Retry loops with no way out when the feature is disabled — the container
  hangs at boot instead of staying quiet.
* `COPY .` in the Dockerfile — drags tests, git history, and reports into
  the image; copy `docker/` explicitly and fence the rest with `.dockerignore`.
* Tracking `test/out/` — regenerable reports pollute diffs; gitignore the
  whole directory.
* Pushing `latest` from a non-tag commit — `latest` must only ever point at
  a tagged release.
* Rebuilding per registry instead of pushing one build everywhere —
  produces divergent digests for the same version; build once, push N times.
