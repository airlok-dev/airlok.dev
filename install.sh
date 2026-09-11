#!/bin/sh
# Installs the latest release of airlok (https://github.com/airlok-dev/airlok).
#
#     curl -fsSL https://airlok.dev/install.sh | sh
#     curl -fsSL https://airlok.dev/install.sh | AIRLOK_NO_MODIFY_PATH=1 sh
#
# Asks the GitHub API for the latest release, downloads that release's
# airlok-installer.sh, checks it against the sha256 digest GitHub publishes
# for the asset, and runs it with the arguments given here. That installer
# then checks each archive against the sha256 checksums built into it, and
# reads AIRLOK_INSTALL_DIR, AIRLOK_NO_MODIFY_PATH, and the other variables
# listed by its --help.
#
# The check is the dist installer's: the file's sha256 as lowercase hex,
# compared with the published value. One difference: this script uses
# sha256sum, shasum, or openssl and stops if none is available, where the
# dist installer skips its check when sha256sum is missing.
#
# Set AIRLOK_GITHUB_TOKEN to authenticate the API request. Without it GitHub
# allows 60 requests an hour from one address.

set -u

REPO=airlok-dev/airlok

say() {
    printf 'airlok-install: %s\n' "$1" >&2
}

fail() {
    say "$1"
    exit 1
}

# download URL FILE [HEADER]
download() {
    if command -v curl >/dev/null 2>&1; then
        if [ -n "${3:-}" ]; then
            curl --proto '=https' --tlsv1.2 -fsSL -H "$3" -o "$2" "$1"
        else
            curl --proto '=https' --tlsv1.2 -fsSL -o "$2" "$1"
        fi
    elif command -v wget >/dev/null 2>&1; then
        if [ -n "${3:-}" ]; then
            wget -q --header="$3" -O "$2" "$1"
        else
            wget -q -O "$2" "$1"
        fi
    else
        fail "curl or wget is required"
    fi
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -b "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 -b "$1" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" | awk '{print $NF}'
    else
        return 1
    fi
}

# asset_digest RELEASE_JSON NAME: the digest GitHub lists for asset NAME,
# such as sha256:3f7b..., or "null".
asset_digest() {
    grep -Eo '"name": *"[^"]*"|"digest": *("[^"]*"|null)' "$1" | awk -v want="\"$2\"" '
        /^"name"/ { sub(/^"name": */, ""); found = ($0 == want); next }
        found { sub(/^"digest": */, ""); gsub(/"/, ""); print; exit }
    '
}

main() {
    tmp=$(mktemp -d 2>/dev/null || mktemp -d -t airlok-install) \
        || fail "cannot create a temporary directory"
    trap 'rm -rf "$tmp"' EXIT
    trap 'exit 1' HUP INT TERM

    auth=""
    if [ -n "${AIRLOK_GITHUB_TOKEN:-}" ]; then
        auth="Authorization: Bearer $AIRLOK_GITHUB_TOKEN"
    fi
    download "https://api.github.com/repos/$REPO/releases/latest" "$tmp/release.json" "$auth" \
        || fail "cannot read the latest release from the GitHub API. If it is rate limited, set AIRLOK_GITHUB_TOKEN, or run the installer from https://github.com/$REPO/releases/latest"

    tag=$(grep -Eo '"tag_name": *"[^"]*"' "$tmp/release.json" | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')
    [ -n "$tag" ] || fail "the GitHub API response has no tag_name"
    digest=$(asset_digest "$tmp/release.json" airlok-installer.sh)
    case "$digest" in
        sha256:*) want=${digest#sha256:} ;;
        *) fail "release $tag lists no sha256 digest for airlok-installer.sh" ;;
    esac

    installer="$tmp/airlok-installer.sh"
    download "https://github.com/$REPO/releases/download/$tag/airlok-installer.sh" "$installer" \
        || fail "cannot download airlok-installer.sh for $tag"
    got=$(sha256_of "$installer") \
        || fail "cannot verify the download: no sha256sum, shasum, or openssl found"
    [ "$got" = "$want" ] || fail "checksum mismatch for airlok-installer.sh from $tag
    want: $want
    got:  $got"

    say "verified airlok-installer.sh from $tag, running it"
    # Hand over on stdin, which is how the installer is meant to run
    # (curl | sh). The open descriptor keeps the file readable after the
    # temporary directory is removed.
    exec 3<"$installer"
    rm -rf "$tmp"
    trap - EXIT
    exec sh -s -- "$@" <&3 3<&-
}

main "$@"
