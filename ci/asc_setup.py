"""Gets the Apple side ready before a Deal Desk build, using the App Store Connect API key. Safe to run every time.

1. Registers the bundle ID (Certificates, Identifiers & Profiles) if it is not there yet.
2. Turns on the Push Notifications capability for that bundle ID, so the signed app may receive native alerts.
3. Checks that the App Store Connect app record exists. Apple's API cannot create one, so if it is missing this
   stops with the exact steps to make it (about a minute in App Store Connect), before the build starts.
4. Picks the next free build number for this version and exports BUILD_NUMBER for later steps.
5. Makes sure the app has an internal TestFlight group that gets every build, with the team's users in it.
   Problems here are warnings and never stop the build.

Logs may be public: this prints no emails, names or identifiers beyond what GitHub masks.

Environment: ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID, BUNDLE_ID, MARKETING_VERSION, GITHUB_ENV.
Needs PyJWT and cryptography.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
GROUP_NAME = "Me"
APP_NAME = "Deal Desk"


def token() -> str:
    with open(os.environ["ASC_KEY_PATH"], encoding="utf-8") as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method: str, path: str, body: dict | None = None, query: dict | None = None) -> dict:
    url = API + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "dealdesk-ci")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        try:
            errors = json.loads(detail).get("errors", [])
            detail = "; ".join(f"{x.get('title')}: {x.get('detail')}" for x in errors) or detail
        except ValueError:
            pass
        raise RuntimeError(f"{method} {path} -> HTTP {e.code}: {detail}") from None


def ensure_bundle_id(identifier: str) -> str:
    """Returns the bundle ID's resource id, registering it first if needed."""
    found = call("GET", "/bundleIds", query={"filter[identifier]": identifier, "limit": "200"})
    for b in found.get("data", []):
        if b["attributes"]["identifier"] == identifier:
            print("Bundle ID: registered.")
            return b["id"]
    created = call("POST", "/bundleIds", {
        "data": {"type": "bundleIds",
                 "attributes": {"identifier": identifier, "name": APP_NAME, "platform": "IOS"}}})
    print("Bundle ID: was missing, registered it now.")
    return created["data"]["id"]


def ensure_push(bundle_resource_id: str) -> None:
    # This relationship endpoint rejects `limit` (HTTP 400), and a bundle ID has only a handful of capabilities.
    caps = call("GET", f"/bundleIds/{bundle_resource_id}/bundleIdCapabilities")
    if any(c["attributes"].get("capabilityType") == "PUSH_NOTIFICATIONS" for c in caps.get("data", [])):
        print("Push Notifications: already on for the bundle ID.")
        return
    call("POST", "/bundleIdCapabilities", {
        "data": {"type": "bundleIdCapabilities",
                 "attributes": {"capabilityType": "PUSH_NOTIFICATIONS"},
                 "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}}}}})
    print("Push Notifications: turned on for the bundle ID.")


def find_app(identifier: str) -> str | None:
    apps = call("GET", "/apps", query={"filter[bundleId]": identifier, "limit": "200"})
    for app in apps.get("data", []):
        if app["attributes"].get("bundleId") == identifier:
            return app["id"]
    return None


def choose_build_number(app_id: str, version: str) -> str:
    """One more than the highest build already uploaded for this version (never below the run number), so a
    re-run never collides with a number App Store Connect already has."""
    builds = call("GET", "/builds", query={"filter[app]": app_id, "filter[preReleaseVersion.version]": version,
                                           "limit": "200", "fields[builds]": "version"}).get("data", [])
    taken = [int(b["attributes"]["version"]) for b in builds if str(b["attributes"].get("version", "")).isdigit()]
    run = int(os.environ.get("GITHUB_RUN_NUMBER", "1") or "1")
    return str(max([run] + [n + 1 for n in taken]))


def ensure_internal_group(app_id: str) -> None:
    groups = call("GET", f"/apps/{app_id}/betaGroups", query={"limit": "200"}).get("data", [])
    internal = [g for g in groups if g["attributes"].get("isInternalGroup")]
    if internal:
        print(f"TestFlight: internal group present ({len(internal)}).")
        return
    group = call("POST", "/betaGroups", {
        "data": {"type": "betaGroups",
                 "attributes": {"name": GROUP_NAME, "isInternalGroup": True, "hasAccessToAllBuilds": True},
                 "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
    print("TestFlight: created an internal group that gets every build.")

    users = call("GET", "/users", query={"limit": "200"}).get("data", [])
    added = 0
    for user in users:
        a = user["attributes"]
        email = a.get("username") or a.get("email")
        if not email:
            continue
        try:
            call("POST", "/betaTesters", {
                "data": {"type": "betaTesters",
                         "attributes": {"email": email, "firstName": a.get("firstName") or "",
                                        "lastName": a.get("lastName") or ""},
                         "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}}}})
            added += 1
        except RuntimeError as e:
            print(f"::warning::Could not add one team member to the TestFlight group ({str(e)[:200]}).")
    print(f"TestFlight: added {added} of {len(users)} team member(s) to the group.")


def main() -> int:
    identifier = os.environ["BUNDLE_ID"]
    version = os.environ["MARKETING_VERSION"]

    bundle_resource_id = ensure_bundle_id(identifier)
    try:
        ensure_push(bundle_resource_id)
    except RuntimeError as e:
        print(f"::error::Could not turn on Push Notifications for the bundle ID ({str(e)[:300]}). "
              "Turn it on by hand: developer.apple.com > Identifiers > the Deal Desk ID > Push Notifications.")
        return 4

    app_id = find_app(identifier)
    if not app_id:
        print("::error::There is no App Store Connect app for this bundle ID yet. Apple's API cannot create one.")
        print("Make it once (about a minute), then run this workflow again:")
        print("  1. appstoreconnect.apple.com > Apps > + > New App")
        print("  2. Platform iOS. Name: anything not taken on the App Store, e.g. 'Deal Desk (Private)'.")
        print("     (The name under the icon on the phone is always 'Deal Desk'.)")
        print("  3. Bundle ID: pick the Deal Desk one this step just registered. SKU: dealdesk. Full Access.")
        return 3
    print("App record: present.")

    number = choose_build_number(app_id, version)
    print(f"TestFlight version: {version} ({number}).")
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as env:
        env.write(f"BUILD_NUMBER={number}\n")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as s:
            s.write(f"**Deal Desk TestFlight version {version} ({number})**\n\n")

    try:
        ensure_internal_group(app_id)
    except RuntimeError as e:
        print(f"::warning::TestFlight group setup did not finish ({str(e)[:300]}). Add yourself under the app's "
              "TestFlight > Internal Testing in App Store Connect.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
