#!/bin/sh
set -eu
REPO_DIR=$(dirname "$0")

if ! git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  echo "not a git repository: versioning needs git tags" >&2
  exit 1
fi
if [ -n "$(git -C "$REPO_DIR" status --porcelain)" ]; then
  echo "refusing to publish from a dirty worktree" >&2
  exit 1
fi

GIT_SHA=$(git -C "$REPO_DIR" rev-parse --short HEAD)
if TAG=$(git -C "$REPO_DIR" describe --tags --exact-match 2>/dev/null); then
  VERSION=${TAG#v}
  MAJOR=${VERSION%%.*}
  REST=${VERSION#*.}
  MINOR=${REST%%.*}
  TAGS="$VERSION $MAJOR.$MINOR $MAJOR latest"
else
  VERSION="edge"
  TAGS="edge sha-$GIT_SHA"
fi

if [ "$#" -gt 0 ]; then
  REGISTRIES="$*"
else
  REGISTRIES=$(grep -v '^[[:space:]]*#' "$REPO_DIR/registries" | grep -v '^[[:space:]]*$' || true)
fi
if [ -z "$REGISTRIES" ]; then
  echo "no registries: add them to registries or pass them as args" >&2
  exit 1
fi

BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
set --
for registry in $REGISTRIES; do
  for tag in $TAGS; do
    set -- "$@" -t "$registry:$tag"
  done
done
docker build \
  --build-arg "BUILD_DATE=$BUILD_DATE" \
  --build-arg "VERSION=$VERSION" \
  --build-arg "GIT_SHA=$GIT_SHA" \
  "$@" \
  "$REPO_DIR"
for registry in $REGISTRIES; do
  for tag in $TAGS; do
    docker push "$registry:$tag"
  done
done

echo "published $VERSION ($GIT_SHA) to:$REGISTRIES"
