#!/bin/zsh
set -euo pipefail
set +x
[[ "${GITHUB_ACTIONS:-}" == true ]] || { print -u2 'Only run this helper on an ephemeral GitHub Actions runner'; exit 1; }
: "${RUNNER_TEMP:?}"
KEYCHAIN_PATH="$RUNNER_TEMP/explorer-development.keychain-db"
P12_PATH="$RUNNER_TEMP/explorer-development.p12"
CERT_PATH="$RUNNER_TEMP/explorer-development.pem"

if [[ "${1:-}" == '--cleanup' ]]; then
  security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
  for item in "$P12_PATH" "$CERT_PATH"; do
    [[ ! -f "$item" ]] || unlink "$item"
  done
  exit 0
fi

: "${EXPLORER_DEV_P12_BASE64:?Configure the fixed signing certificate in GitHub Secrets}"
: "${EXPLORER_DEV_P12_PASSWORD:?Configure the PKCS12 password in GitHub Secrets}"
: "${EXPLORER_LOCAL_SIGNING_SHA1:?Configure EXPLORER_DEV_CERT_SHA1 in GitHub Variables}"
umask 077
printf '%s' "$EXPLORER_DEV_P12_BASE64" | base64 --decode > "$P12_PATH"
KEYCHAIN_PASSWORD=$(openssl rand -hex 32)
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$P12_PATH" -P "$EXPLORER_DEV_P12_PASSWORD" -t cert -f pkcs12 \
  -k "$KEYCHAIN_PATH" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" > /dev/null
security list-keychains -d user -s "$KEYCHAIN_PATH" "$HOME/Library/Keychains/login.keychain-db"
security find-certificate -c 'Mac Development: Explorer Self-Signed' -p "$KEYCHAIN_PATH" > "$CERT_PATH"
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN_PATH" "$CERT_PATH"
security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -Fiq "$EXPLORER_LOCAL_SIGNING_SHA1"
unlink "$P12_PATH"
unlink "$CERT_PATH"
