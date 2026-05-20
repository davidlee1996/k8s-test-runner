#!/usr/bin/env bash
# setup.sh — runs once when the codespace is first created.
#
# What this does:
#   1. Installs Kind (not in any of the standard devcontainer features)
#   2. Installs Playwright browser deps (Chromium specifically)
#   3. Verifies all expected tools are available
#   4. Prints next-steps guidance

set -uo pipefail

echo "════════════════════════════════════════════════════════════"
echo "  Setting up k8s-test-runner codespace..."
echo "════════════════════════════════════════════════════════════"

# --- Install Kind ---
echo ""
echo "→ Installing Kind..."
if ! command -v kind > /dev/null; then
  KIND_VERSION="v0.27.0"
  ARCH=$(uname -m)
  case "${ARCH}" in
    x86_64)  KIND_ARCH="amd64" ;;
    aarch64) KIND_ARCH="arm64" ;;
    *)       echo "Unsupported architecture: ${ARCH}"; exit 1 ;;
  esac
  curl -Lo /tmp/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${KIND_ARCH}"
  chmod +x /tmp/kind
  sudo mv /tmp/kind /usr/local/bin/kind
  echo "  ✓ Kind ${KIND_VERSION} installed"
else
  echo "  ✓ Kind already installed: $(kind version)"
fi

# --- Install Playwright browser deps (just Chromium) ---
echo ""
echo "→ Installing Playwright browser dependencies..."
if [ -f runner/package.json ]; then
  cd runner
  npm install
  npx playwright install --with-deps chromium
  cd ..
  echo "  ✓ Playwright + Chromium ready"
else
  echo "  ⚠ runner/package.json not found, skipping (expected on fresh clone)"
fi

# --- Verify tools ---
echo ""
echo "→ Verifying installed tools:"
for tool in docker kind kubectl node npm aws terraform envsubst; do
  if command -v "${tool}" > /dev/null; then
    echo "  ✓ ${tool}: $(command -v "${tool}")"
  else
    echo "  ✗ ${tool}: NOT FOUND"
  fi
done

# --- AWS credentials check ---
echo ""
echo "→ Checking AWS credentials..."
if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "  ✓ AWS credentials available via Codespaces secrets"

  # Build the local credentials file from env vars (for compatibility with existing scripts)
  cat > "${HOME}/.k8s-test-runner-credentials" <<EOF
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_REGION=${AWS_REGION:-us-east-1}
S3_BUCKET=${S3_BUCKET:-}
EOF
  chmod 600 "${HOME}/.k8s-test-runner-credentials"

  if [ -n "${S3_BUCKET:-}" ]; then
    echo "  ✓ S3_BUCKET configured: ${S3_BUCKET}"
  else
    echo "  ⚠ S3_BUCKET not set — add it as a Codespaces secret"
  fi
else
  echo "  ⚠ AWS credentials not configured yet"
  echo ""
  echo "    To add them:"
  echo "    1. Go to https://github.com/settings/codespaces"
  echo "    2. Under 'Codespaces secrets', add:"
  echo "       - AWS_ACCESS_KEY_ID"
  echo "       - AWS_SECRET_ACCESS_KEY"
  echo "       - S3_BUCKET"
  echo "       - AWS_REGION (set to: us-east-1)"
  echo "    3. Make sure this repository is in the 'Repository access' list"
  echo "    4. Rebuild the codespace (Command Palette → 'Codespaces: Rebuild Container')"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Setup complete."
echo ""
echo "  Next: run 'make doctor' to verify everything is in place."
echo "════════════════════════════════════════════════════════════"