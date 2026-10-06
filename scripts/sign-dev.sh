#!/bin/zsh
# Reuse one private, per-user code-signing identity across development apps.
set -euo pipefail
unsetopt XTRACE
umask 077

usage() {
    print -u2 -- "Usage: $0 --setup | APP.app [APP.app ...]"
    print -u2 -- "Sign nested helper apps before their containing app. Keep each bundle ID stable."
}

if (( $# == 0 )); then usage; exit 2; fi
if [[ "$1" == --help ]]; then usage; exit 0; fi
if [[ "$1" == --setup && $# != 1 ]]; then usage; exit 2; fi

# This directory deliberately lives outside the repository and build outputs.
# Never silently regenerate an existing identity: that would lose TCC grants.
signing_dir="${MELTY_DEV_SIGNING_DIR:-$HOME/Library/Application Support/Melty/DevelopmentSigning}"
keychain="$signing_dir/development.keychain-db"
certificate="$signing_dir/certificate.pem"
password_file="$signing_dir/keychain-password"
fingerprint_file="$signing_dir/identity.sha1"
temporary_dir=""

cleanup() {
    if [[ -n "$temporary_dir" ]]; then /bin/rm -rf -- "$temporary_dir"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ! -d "$signing_dir" ]]; then
    /bin/mkdir -p -- "${signing_dir:h}"
    # mkdir is also a guard against two simultaneous first-time initializations.
    /bin/mkdir -m 700 -- "$signing_dir"
    temporary_dir="$(/usr/bin/mktemp -d "$signing_dir/.setup.XXXXXX")"
    /usr/bin/openssl rand -hex 32 > "$password_file"
    keychain_password="$(<"$password_file")"
    cat > "$temporary_dir/openssl.cnf" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = signing
prompt = no
[subject]
CN = Melty Local Development
[signing]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONFIG
    /usr/bin/openssl req -new -newkey rsa:3072 -nodes -x509 -sha256 -days 3650 \
        -config "$temporary_dir/openssl.cnf" -keyout "$temporary_dir/private-key.pem" \
        -out "$certificate" 2> "$temporary_dir/openssl.log"
    /usr/bin/openssl pkcs12 -export -inkey "$temporary_dir/private-key.pem" \
        -in "$certificate" -out "$temporary_dir/identity.p12" \
        -passout "file:$password_file"
    /usr/bin/security create-keychain -p "$keychain_password" "$keychain"
    /usr/bin/security set-keychain-settings -lut 3600 "$keychain"
    /usr/bin/security import "$temporary_dir/identity.p12" -k "$keychain" \
        -P "$keychain_password" -x -T /usr/bin/codesign > /dev/null
    /usr/bin/security set-key-partition-list -S apple-tool: -s \
        -k "$keychain_password" "$keychain" > /dev/null
    /usr/bin/openssl x509 -in "$certificate" -noout -fingerprint -sha1 \
        | /usr/bin/sed 's/.*=//; s/://g' > "$fingerprint_file"
    cleanup
    temporary_dir=""
    print -u2 -- "Created Melty Local Development signing identity (valid for 10 years)."
    print -u2 -- "Keep $signing_dir: replacing this identity requires new permission grants."
fi

for required in "$keychain" "$certificate" "$password_file" "$fingerprint_file"; do
    if [[ ! -s "$required" ]]; then
        print -u2 -- "Signing state is incomplete: $required"
        print -u2 -- "Restore the existing signing directory from backup; refusing to replace its identity."
        exit 1
    fi
done
/bin/chmod 700 "$signing_dir"
/bin/chmod 600 "$keychain" "$certificate" "$password_file" "$fingerprint_file"
fingerprint="$(<"$fingerprint_file")"
actual_fingerprint="$(/usr/bin/openssl x509 -in "$certificate" -noout -fingerprint -sha1 \
    | /usr/bin/sed 's/.*=//; s/://g')"
if [[ ${#fingerprint} != 40 || "$fingerprint" == *[^[:xdigit:]]* || "$fingerprint" != "$actual_fingerprint" ]]; then
    print -u2 -- "Signing certificate fingerprint does not match the saved identity."
    exit 1
fi
if ! /usr/bin/openssl x509 -in "$certificate" -checkend 0 -noout > /dev/null; then
    print -u2 -- "The development certificate has expired. Renew deliberately; permissions will need migration."
    exit 1
fi
keychain_password="$(<"$password_file")"
/usr/bin/security unlock-keychain -p "$keychain_password" "$keychain"
unset keychain_password
identities="$(/usr/bin/security find-identity -p codesigning "$keychain")"
if [[ "$identities" != *"$fingerprint"* ]]; then
    print -u2 -- "The saved signing identity is missing from $keychain."
    exit 1
fi
if [[ "$1" == --setup ]]; then
    print -r -- "Melty Local Development: $fingerprint"
    exit 0
fi

for app_dir in "$@"; do
    if [[ ! -d "$app_dir/Contents" ]]; then
        print -u2 -- "Expected an app bundle: $app_dir"
        exit 2
    fi
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_dir/Contents/Info.plist")"
    if [[ -z "$bundle_id" ]]; then
        print -u2 -- "Missing CFBundleIdentifier: $app_dir"
        exit 2
    fi
    for surface_library in "$app_dir"/Contents/Frameworks/**/MeltySurfaceFrame.dylib(N); do
        /usr/bin/codesign --force --sign "$fingerprint" --keychain "$keychain" \
            --timestamp=none --identifier "$bundle_id.surface-frame" "$surface_library"
    done
    # Let codesign generate a certificate-bound requirement. An identifier-only
    # requirement would let unrelated code impersonate an already approved app.
    /usr/bin/codesign --force --sign "$fingerprint" --keychain "$keychain" \
        --timestamp=none --identifier "$bundle_id" \
        --preserve-metadata=entitlements,flags,runtime "$app_dir"
    /usr/bin/codesign --verify --deep --strict "$app_dir"
done
