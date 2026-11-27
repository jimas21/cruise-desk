#!/usr/bin/env bash
# Generates the Xcode project and archives it unsigned; signing happens once, at export, with Apple's
# cloud-managed distribution certificate (signing the archive made a new development certificate on every fresh
# runner, and the account's certificate limit filled up).
#
# An unsigned archive carries no entitlements, and export signs with the entitlements the archived app carries.
# So the app is ad-hoc signed here with Config/DealDesk.entitlements (aps-environment = production): without
# that, the exported app would have no push entitlement and APNs registration would fail on the phone.
#
# The server address and app token go into Info.plist (DDBaseURL / DDAppToken) through the build settings
# DD_BASE_URL / DD_APP_TOKEN. GitHub masks both in the log because they come from secrets.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$here/common.sh"
cd "$here/.."

for name in BUNDLE_ID TEAM_ID ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID DD_BASE_URL DD_APP_TOKEN MARKETING_VERSION BUILD_NUMBER; do
  [ -n "${!name:-}" ] || die "$name is not set (ci/preflight.sh and ci/asc_setup.py set the version numbers)"
done
test -f App/Assets.xcassets/AppIcon.appiconset/AppIcon.png || die "App icon is missing; ci/make_icon.py must run first."
test -f App/Assets.xcassets/LaunchMark.imageset/LaunchMark.png || die "Launch mark is missing; ci/make_icon.py must run first."
[[ "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Bad MARKETING_VERSION $MARKETING_VERSION"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || die "Bad BUILD_NUMBER $BUILD_NUMBER"

asc_auth_flags
mkdir -p build

hints() {
  echo "::error::Archive failed. Last error lines from build/archive.log:" >&2
  grep -E 'error:|ARCHIVE FAILED|Cloud signing|No Accounts|No profiles|provisioning' build/archive.log | tail -n 25 >&2 || true
  cat >&2 <<'MSG'

Likely causes, in order:
  1. A Swift compile error (the lines above say "error:"). The Compile check workflow in cruise-desk shows it too.
  2. The API key's Access is not Admin ("Cloud signing permission error").
  3. The bundle ID is not registered, or DEALDESK_BUNDLE_ID differs from the registered one.
  4. TEAM_ID is wrong (must match the team that owns the bundle ID and the key).
  5. A network blip that looks like an auth error ("No Accounts with App Store Connect Access"): re-run.
MSG
}
trap hints ERR

echo "Version $MARKETING_VERSION ($BUILD_NUMBER)"
xcodegen generate

xcodebuild \
  -project DealDesk.xcodeproj \
  -scheme DealDesk \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/DealDesk.xcarchive \
  "${ASC_AUTH[@]}" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  DD_BASE_URL="$DD_BASE_URL" \
  DD_APP_TOKEN="$DD_APP_TOKEN" \
  archive > build/archive.log 2>&1

trap - ERR
app="build/DealDesk.xcarchive/Products/Applications/DealDesk.app"
test -d "$app" || die "xcodebuild reported success but $app is missing."

# Carry the push entitlement into the archive (see the note at the top).
codesign --force --sign - --entitlements Config/DealDesk.entitlements --timestamp=none "$app"
entitlements="$(codesign -d --entitlements - "$app" 2>&1 || true)"
grep -q 'aps-environment' <<<"$entitlements" || die "The archived app does not carry the aps-environment entitlement."

# The built-in values must have reached Info.plist (checked without printing them).
plist="$app/Info.plist"
[ "$(/usr/libexec/PlistBuddy -c 'Print :DDBaseURL' "$plist")" = "$DD_BASE_URL" ] || die "DDBaseURL did not reach Info.plist."
[ "$(/usr/libexec/PlistBuddy -c 'Print :DDAppToken' "$plist")" = "$DD_APP_TOKEN" ] || die "DDAppToken did not reach Info.plist."

echo "Archive OK (push entitlement and built-in server settings present)."
