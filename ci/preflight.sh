#!/usr/bin/env bash
# Fails fast, with a plain message, if any variable or secret is missing or malformed, and exports
# MARKETING_VERSION (from project.yml) for later steps. Checks values only; never prints them.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$here/common.sh"

missing=()
[ -n "${TEAM_ID:-}" ] || missing+=("variable TEAM_ID")
for name in DEALDESK_BUNDLE_ID:BUNDLE_ID DEALDESK_BASE_URL:DD_BASE_URL DEALDESK_APP_TOKEN:DD_APP_TOKEN \
            ASC_KEY_ID:ASC_KEY_ID ASC_ISSUER_ID:ASC_ISSUER_ID ASC_KEY_P8:ASC_KEY_P8; do
  secret="${name%%:*}"
  env_name="${name##*:}"
  [ -n "${!env_name:-}" ] || missing+=("secret $secret")
done
if [ "${#missing[@]}" -gt 0 ]; then
  printf '::error::Missing %s (Settings > Secrets and variables > Actions)\n' "${missing[@]}" >&2
  die "Set the items above, then run the workflow again."
fi

case "$BUNDLE_ID" in
  *REPLACE*) die "DEALDESK_BUNDLE_ID still contains the REPLACE placeholder." ;;
esac
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ && "$BUNDLE_ID" == *.* ]] \
  || die "DEALDESK_BUNDLE_ID is not a valid reverse-DNS bundle ID (letters, digits, dots, hyphens; at least one dot)."
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] \
  || die "TEAM_ID must be the 10-character Team ID from developer.apple.com > Membership details."
[[ "$DD_BASE_URL" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~/-]*)?$ ]] \
  || die "DEALDESK_BASE_URL must be a plain https:// address, such as https://deals.example.org (no spaces or quotes)."
[[ "$DD_APP_TOKEN" =~ ^[A-Za-z0-9._~+/=-]{16,}$ ]] \
  || die "DEALDESK_APP_TOKEN must be at least 16 characters of letters, digits and . _ ~ + / = - (no spaces or quotes)."

version="$(sed -n 's/^ *MARKETING_VERSION: *"\([0-9][0-9.]*\)".*/\1/p' "$here/../project.yml" | head -n 1)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Could not read MARKETING_VERSION from project.yml."
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "MARKETING_VERSION=$version" >> "$GITHUB_ENV"
fi

echo "Preflight OK: every setting present and well-formed (values not printed). Version $version."
