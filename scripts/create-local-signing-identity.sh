#!/bin/zsh
set -euo pipefail

IDENTITY='Mac Development: Explorer Self-Signed'
if security find-identity -v -p codesigning | grep -Fq "\"$IDENTITY\""; then
  print "Signing identity already exists: $IDENTITY"
  exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/explorer-signing.XXXXXX")
cleanup() {
  rm -f "$WORK/key.pem" "$WORK/certificate.pem" "$WORK/identity.p12"
  rmdir "$WORK" 2>/dev/null || true
}
trap cleanup EXIT
PASSWORD=$(openssl rand -hex 24)
LOGIN_KEYCHAIN=$(security default-keychain -d user | tr -d '" ')

openssl req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
  -subj "/CN=$IDENTITY/O=Explorer Local Development" \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,digitalSignature,keyCertSign' \
  -addext 'extendedKeyUsage=codeSigning' \
  -keyout "$WORK/key.pem" -out "$WORK/certificate.pem" 2>/dev/null
openssl pkcs12 -export -legacy -name "$IDENTITY" \
  -inkey "$WORK/key.pem" -in "$WORK/certificate.pem" \
  -passout "pass:$PASSWORD" -out "$WORK/identity.p12"

security import "$WORK/identity.p12" -k "$LOGIN_KEYCHAIN" -P "$PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security
security add-trusted-cert -r trustRoot -p codeSign -k "$LOGIN_KEYCHAIN" "$WORK/certificate.pem"
security find-identity -v -p codesigning | grep -Fq "\"$IDENTITY\""
print "Created signing identity: $IDENTITY"
