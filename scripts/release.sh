#!/bin/bash
# Build the universal app on this Mac and publish it as a GitHub release.
#
#   ./scripts/release.sh v0.2.0          build, package, tag and upload
#   ./scripts/release.sh --build-only    only build dist/mac-initial-setup.tar.gz
#   ./scripts/release.sh --install       build and install it to ~/.mac-initial-setup, like the
#                                        one-liner does (refuses while a run from there is going)
#
# Needs Rust (rustup.rs) and, for publishing, the GitHub CLI (`brew install gh`, `gh auth login`).
set -euo pipefail
cd "$(dirname "$0")/.."

TAG=${1:-}
[ -n "$TAG" ] || { echo "Usage: $0 vX.Y.Z | --build-only | --install"; exit 1; }
case $TAG in v[0-9]*|--build-only|--install) ;; *) echo "Usage: $0 vX.Y.Z | --build-only | --install"; exit 1 ;; esac
DEST="$HOME/.mac-initial-setup"
if [ "$TAG" = --install ] && pgrep -f "$DEST/(bin/mac-setup|setup.sh)" >/dev/null; then
  echo "A setup run from $DEST is still going – try again when it has finished."; exit 1
fi
CARGO=$(command -v cargo || echo "$HOME/.cargo/bin/cargo")
RUSTUP=$(command -v rustup || echo "$HOME/.cargo/bin/rustup")

if [ "${TAG#v}" != "$TAG" ]; then
  version=$(sed -n 's/^version = "\(.*\)"/\1/p' app/Cargo.toml | head -1)
  [ "$TAG" = "v$version" ] || { echo "Tag $TAG doesn't match app/Cargo.toml version $version"; exit 1; }
  [ -z "$(git status --porcelain)" ] || { echo "Commit your changes first."; exit 1; }
  command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh && gh auth login"; exit 1; }
fi

echo "› Checking scripts"
for f in setup.sh install.sh catalog.sh lib/*.sh modules/*.sh; do /bin/bash -n "$f"; done
./setup.sh --json | python3 -m json.tool >/dev/null

echo "› Building (Apple Silicon + Intel)"
"$RUSTUP" target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null
(cd app
 "$CARGO" build --release --locked --target aarch64-apple-darwin
 "$CARGO" build --release --locked --target x86_64-apple-darwin
 lipo -create -output target/mac-setup-universal \
   target/aarch64-apple-darwin/release/mac-setup target/x86_64-apple-darwin/release/mac-setup)

echo "› Packaging"
# Staged in a temporary folder, so a run started from an earlier build never loses its files.
stage=$(mktemp -d); trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/mac-initial-setup/bin" dist
cp -R setup.sh install.sh catalog.sh lib modules docs README.md LICENSE "$stage/mac-initial-setup/"
cp app/target/mac-setup-universal "$stage/mac-initial-setup/bin/mac-setup"
tar -czf dist/mac-initial-setup.tar.gz -C "$stage" mac-initial-setup
(cd dist && shasum -a 256 mac-initial-setup.tar.gz > mac-initial-setup.tar.gz.sha256)
echo "✓ dist/mac-initial-setup.tar.gz ($(du -h dist/mac-initial-setup.tar.gz | cut -f1))"

if [ "$TAG" = --install ]; then
  rm -rf "$DEST" && mv "$stage/mac-initial-setup" "$DEST"
  echo "✓ Installed to $DEST – start it with: $DEST/bin/mac-setup"
  exit 0
fi
[ "$TAG" = --build-only ] && exit 0

echo "› Publishing $TAG"
git tag -a "$TAG" -m "$TAG"
git push origin HEAD "$TAG"
gh release create "$TAG" dist/mac-initial-setup.tar.gz dist/mac-initial-setup.tar.gz.sha256 --generate-notes
echo "✓ Released $TAG"
