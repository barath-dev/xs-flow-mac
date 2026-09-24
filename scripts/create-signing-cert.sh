#!/bin/zsh
# Creates a self-signed code-signing certificate "MouseDriver Local Signing" in
# your login keychain, so rebuilt copies of MouseDriver keep their permissions.
# Only needed if you don't have an "Apple Development" certificate.
set -euo pipefail
NAME="MouseDriver Local Signing"
if security find-identity -p codesigning | grep -q "$NAME"; then
  echo "\"$NAME\" already exists."; exit 0
fi
TMP=$(mktemp -d)
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" >/dev/null 2>&1
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/cert.p12" -passout pass:mousedriver >/dev/null 2>&1 \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/cert.p12" -passout pass:mousedriver
security import "$TMP/cert.p12" -k ~/Library/Keychains/login.keychain-db -P mousedriver -T /usr/bin/codesign
rm -rf "$TMP"
echo "Created \"$NAME\". Re-run scripts/bundle.sh."
