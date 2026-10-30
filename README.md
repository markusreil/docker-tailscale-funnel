# tailscale sidecar

Wraps the upstream `tailscale/tailscale` image. Upstream `containerboot` still
owns the daemon and login (all `TS_*` env handling untouched); the wrapper
only ensures the funnel rule (`--bg`, idempotent) on every start, retrying
until Funnel is approved tailnet-side, then gets out of the way.

Every start clears funnel state first, so a changed target/path, a flipped
`FUNNEL_ENABLED`, or a restart can never inherit a stale rule. Reset is
retried (`FUNNEL_RESET_RETRIES`, default 5); total failure is WARNING-loud
on stderr but never blocks boot. Nothing is published unless
`FUNNEL_ENABLED=true`.

Shares HA's network namespace (`network_mode: service:homeassistant`), so the
funnel target is HA itself. Restart `homeassistant` always breaks this
container's network (stale namespace) — restart this sidecar afterwards.

## Layout

- `Dockerfile` (top-level) — wraps `tailscale/tailscale`, copies the
  `docker/` context, adds a HEALTHCHECK on `tailscale status`.
- `docker/entrypoint.sh` — boots upstream `containerboot`, waits for
  `BackendState: Running`, then ensures the funnel rule in the background.
- `docker/funnel.sh` — the funnel logic (`funnel_reset`, `funnel_once`,
  `ensure_funnel`), sourced by the entrypoint and by the tests.
- `test/` — Robot Framework suite; `test/out/` holds reports (gitignored).

## Build

```sh
BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) docker build -t tailscale-funnel:local .
```

Build args: `TAILSCALE_VERSION` (default `stable`), `BUILD_DATE` (default
`unknown`, stamped as above and recorded in the image).

## Tests

No test ever touches a real tailnet: `test/mocks/tailscale` is a fake
`tailscale` binary that records its argv to `$MOCK_LOG` and returns canned
responses (`MOCK_MODE`: `ok`, `fail-funnel-once`, `fail-funnel-always`,
`no-backend`; plus `MOCK_FAIL_RESET` with `0`, a failure count, or `always`
for the reset path, `MOCK_BACKEND_DELAY` for the daemon readiness wait).
The suite sources `docker/funnel.sh` with `TAILSCALE_BIN` pointed at the
mock, so assertions run against the exact code shipped in the image. Beyond
steady states it covers enable/disable toggles, target/path changes across
consecutive runs (asserting the old rule was cleared), reset retry and
WARNING paths, the retry-until-approval loop, the backend wait
(ready/delayed/never), and a full entrypoint boot with a fake
`containerboot`. A second suite (`test/publish.robot`) covers publish
version resolution in throwaway git repos with a fake `docker` binary: exact
tags yield full/floating/`latest` tags, untagged commits yield `edge` and
never `latest`, CLI registries override the file, and dirty worktrees or an
empty registry set refuse without invoking docker.

```sh
pip install -r test/requirements.txt
robot --outputdir test/out test/
```

## Publishing

Versions come from git tags: an annotated `vX.Y.Z` tag publishes `X.Y.Z`,
`X.Y`, `X`, and `latest`; any other commit publishes `edge` and never
`latest`. A dirty worktree refuses to publish. The version and short SHA
are baked into the image (`VERSION`/`GIT_SHA` env plus OCI labels).

```sh
docker login                       # once per registry host; credentials never in the repo
./publish.sh                # same tags, same digest, to every registry below
./publish.sh <registry...>  # one-off override; still one version everywhere
```

The registry set lives in tracked `registries` (one per line) —
that file is what the script reads; the list below is documentation. Add
both Docker Hub and local entries there, e.g.
`docker.io/<namespace>/tailscale-funnel` and
`registry.max.home.arpa/tailscale-funnel`. This project publishes to
`registry.max.home.arpa/tailscale-funnel` (no login required).

## Integrate into a compose cluster

Pull a released tag (never `edge` for production):

```yaml
services:
  tailscale:
    image: registry.max.home.arpa/tailscale-funnel:1
    network_mode: service:<app>   # share the app's namespace; funnel target is the app itself
    depends_on:
      <app>:
        condition: service_started
    devices:
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
    environment:
      TS_AUTHKEY: ${TS_AUTHKEY:?}          # one-off tagged key; revoke after first join
      TS_HOSTNAME: ${TS_HOSTNAME:?}   # name it after the exposed app, e.g. homeassistant
      TS_STATE_DIR: /var/lib/tailscale
      FUNNEL_ENABLED: ${FUNNEL_ENABLED:-false}
      FUNNEL_TARGET: ${FUNNEL_TARGET:-localhost:8123}   # required when enabled
      FUNNEL_PATH: ${FUNNEL_PATH:-/}
    volumes:
      - tailscale-state:/var/lib/tailscale
    restart: unless-stopped

volumes:
  tailscale-state:
```

Notes for the integrator:

- `network_mode: service:<app>` means this container sees the app's
  `localhost`; point `FUNNEL_TARGET` at the app's own port. Restarting
  `<app>` breaks the shared namespace — restart this sidecar afterwards.
- Keep `TS_STATE_DIR` on a named volume so rejoining the tailnet does not
  burn a fresh auth key on every recreate.
- No `ports:`, no proxy variables: the only public surface is the funnel
  rule itself, and only when `FUNNEL_ENABLED=true`.
- `FUNNEL_TARGET` is required only when enabled; when disabled the
  container joins the tailnet and stays unpublished.

## Env vars

- `TS_AUTHKEY` (required) — one-off tagged auth key; revoke after first join.
- `TS_HOSTNAME` (required) — tailnet hostname. Name it after the app being
  exposed (e.g. `homeassistant`); the image ships no default.
- `TS_STATE_DIR` — daemon state (backed by the `tailscale-state` volume).
- `TS_EXTRA_ARGS` — extra `tailscaled` flags (empty default).
- `FUNNEL_ENABLED` — publish via funnel (default `false`: an unset flag never
  exposes anything); set `true` only where intended.
- `FUNNEL_TARGET` (required when enabled) — funnel backend,
  `localhost:8123` (HA itself via the shared namespace).
- `FUNNEL_PATH` — funnel path (default `/`).
- `FUNNEL_RESET_RETRIES` — reset attempts per start (default `5`); total
  failure warns on stderr and continues, never blocking boot.
- `FUNNEL_RESET_DELAY` — seconds between reset attempts (default `10`).
- `FUNNEL_RETRY_DELAY` — seconds between serve retries while Funnel awaits
  tailnet approval (default `300`).
- `TAILSCALE_BIN` — tailscale binary (default `tailscale`); the tests point
  it at the mock. Not set in production.

Exit codes from `funnel_once`: `0` success (including intentionally-disabled
no-op), `1` serve failed (entrypoint retries), `2` `FUNNEL_TARGET` missing
while enabled.
