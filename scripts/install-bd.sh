#!/bin/bash
set -euo pipefail

echo "::group::Installing bd CLI"

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
esac

echo "Detected platform: ${OS}_${ARCH}"

# Get latest release or use specified version
if [ "${BD_VERSION:-latest}" = "latest" ]; then
  RELEASE_URL="https://api.github.com/repos/steveyegge/beads/releases/latest"
else
  RELEASE_URL="https://api.github.com/repos/steveyegge/beads/releases/tags/${BD_VERSION}"
fi

# Download release asset
echo "Fetching release info from: $RELEASE_URL"
DOWNLOAD_URL=$(curl -sL "$RELEASE_URL" | jq -r ".assets[] | select(.name | test(\"beads_.*_${OS}_${ARCH}\")) | .browser_download_url")

if [ -z "$DOWNLOAD_URL" ]; then
  echo "::error::Could not find bd release for ${OS}_${ARCH}"
  echo "Available assets:"
  curl -sL "$RELEASE_URL" | jq -r '.assets[].name'
  exit 1
fi

echo "Downloading bd from: $DOWNLOAD_URL"
curl -sL "$DOWNLOAD_URL" -o /tmp/bd.tar.gz

echo "Extracting archive..."
tar -xzf /tmp/bd.tar.gz -C /tmp

echo "Installing to /usr/local/bin..."
sudo mv /tmp/bd /usr/local/bin/bd
sudo chmod +x /usr/local/bin/bd

BD_VERSION=$(bd --version)
echo "✅ Installed: $BD_VERSION"
echo "::endgroup::"
