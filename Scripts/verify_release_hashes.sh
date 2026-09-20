#!/usr/bin/env bash
# Verify that the release ZIP the website serves and the ZIP in dist/ are byte-identical.
# Run this AFTER the website deploy: Sparkle updates and the official Homebrew cask both
# download that ZIP, and a mismatch is only discovered when a user files an issue (Docs/29 §五).
# The cask sha256 is no longer ours to check — Homebrew's autobump computes it from the same ZIP.
#
# usage: Scripts/verify_release_hashes.sh <version>            e.g. 0.11.1
#   DOWNLOAD_BASE overrides the website download base (default https://tungstenedge.app/download)
set -euo pipefail

VERSION="${1:-}"
[[ -n "$VERSION" ]] || { echo "usage: $0 <version>" >&2; exit 2; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: version must look like X.Y.Z, got '$VERSION'" >&2; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_ZIP="$ROOT/dist/Tungsten-Edge-$VERSION.zip"
DOWNLOAD_BASE="${DOWNLOAD_BASE:-https://tungstenedge.app/download}"
REMOTE_URL="$DOWNLOAD_BASE/Tungsten-Edge-$VERSION.zip"

fail=0
note() { printf '%s\n' "$*"; }
bad()  { printf 'FAIL: %s\n' "$*" >&2; fail=1; }

sha_of() { shasum -a 256 "$1" | awk '{print $1}'; }

# 1. local artifact
if [[ -f "$LOCAL_ZIP" ]]; then
  LOCAL_SHA="$(sha_of "$LOCAL_ZIP")"
  note "local   $LOCAL_SHA  $LOCAL_ZIP"
else
  bad "local ZIP not found: $LOCAL_ZIP (run Scripts/package_release.sh first)"
  LOCAL_SHA=""
fi

# 2. what the website actually serves
TMP="$(mktemp -t tungsten-verify.XXXXXX)"
trap 'rm -f "$TMP"' EXIT
if curl -fsSL --retry 2 -o "$TMP" "$REMOTE_URL"; then
  REMOTE_SHA="$(sha_of "$TMP")"
  note "website $REMOTE_SHA  $REMOTE_URL"
else
  bad "could not download $REMOTE_URL (website not deployed yet?)"
  REMOTE_SHA=""
fi

if [[ -n "$LOCAL_SHA" && -n "$REMOTE_SHA" && "$LOCAL_SHA" != "$REMOTE_SHA" ]]; then
  bad "website ZIP differs from dist/ ZIP - the deploy did not upload this build"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "verify_release_hashes: FAIL" >&2
  exit 1
fi
echo "verify_release_hashes: PASS ($VERSION)"
