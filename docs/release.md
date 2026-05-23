# Releasing Binky

The day-to-day release flow is handled by `release.sh` at the repo root.
This document covers the parts that aren't in the script's own usage text:
**how to set up Apple Developer ID signing and notarization** so
`--notarize` works, and **what happens if you skip it**.

---

## TL;DR

| You have… | Run this |
|---|---|
| Just want to test locally, no publish | `./release.sh 1.2.3 --no-push` |
| Just want a build artifact, no notarization | `./release.sh 1.2.3 --no-push` |
| Full publish, ad-hoc signed (current 1.x default) | `./release.sh 1.2.3` |
| Full publish, notarized (target for 2.0) | `./release.sh 1.2.3 --notarize` |
| First time setting up notarization | Read §3 below, then `./release.sh 1.2.3 --no-push --notarize` once to dry-run it. |

---

## 1. What's the difference?

Binky 1.x ships **ad-hoc signed** (`codesign --sign -`). The app runs, but
macOS Gatekeeper warns the user on first launch ("Binky cannot be opened
because Apple cannot check it for malicious software"). The README
documents two workarounds:

1. System Settings → Privacy & Security → "Open Anyway"
2. `xattr -dr com.apple.quarantine /Applications/Binky.app`

Neither is acceptable for paying customers. **Binky 2.0 must ship
notarized.** Notarization is Apple's automated review of a signed app —
it's not the App Store, but the result is that Gatekeeper recognizes the
build and lets users open it without any prompts.

`release.sh --notarize` automates the build step. It does **not** automate
the one-time setup of credentials, which is documented below.

## 2. Prerequisites (one-time)

You need three things before `--notarize` can ever succeed:

1. **Paid Apple Developer Program membership** — $99/year, on the
   [Apple Developer site](https://developer.apple.com/programs/).
2. **A "Developer ID Application" certificate** in your login keychain.
   This is the cert that signs binaries for distribution **outside** the
   App Store. Create it from
   `https://developer.apple.com/account/resources/certificates/list`
   → **+** → "Developer ID Application". Download the `.cer`, double-click
   to install in Keychain Access. (Xcode → Settings → Accounts can do this
   for you.)
3. **An app-specific password** for your Apple ID (used by `notarytool`
   non-interactively). Create at
   `https://appleid.apple.com/account/manage` → Sign-In and Security →
   App-Specific Passwords. Keep the 16-char password somewhere safe; you
   won't see it again.

Verify the cert is in place:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
# Expect: 1 valid identities found, line ending in "Developer ID Application: Your Name (TEAM_ID)"
```

## 3. Configure `notarytool` once

`notarytool` lets you store the credentials in your login keychain so the
release script can submit non-interactively.

```bash
xcrun notarytool store-credentials "BinkyNotaryProfile" \
    --apple-id "you@example.com" \
    --team-id  "ABCDE12345" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

- `BinkyNotaryProfile` is the profile name `release.sh` looks for by
  default. Override via `BINKY_NOTARY_PROFILE=other-name ./release.sh …`
  if you have multiple Apple accounts.
- `--team-id` is the 10-character Team ID from
  `https://developer.apple.com/account` → Membership.
- `--password` is the app-specific password from §2.3, **not** your Apple
  ID password.

Confirm the profile works:

```bash
xcrun notarytool history --keychain-profile "BinkyNotaryProfile"
# Expect a (possibly empty) list of past submissions, no errors.
```

`release.sh --notarize` runs this same command as a pre-flight check and
will refuse to start the build if it fails.

## 4. The Xcode signing settings

The Xcode project must be signed with the Developer ID cert at build
time (notarization will reject anything signed with `-` for ad-hoc).
This isn't automated yet — open `Binky.xcodeproj` once and:

1. Select the **Binky** target → **Signing & Capabilities**.
2. **Team:** pick your Developer ID team.
3. **Signing Certificate:** "Developer ID Application".
4. Verify **Hardened Runtime** is enabled — required for notarization.

Once these settings are saved in `project.pbxproj`, every Release build
picks them up. (If you ever sign in Xcode with `Sign to Run Locally`,
notarization will fail with "binary is not signed with a valid Developer
ID certificate"; flip back to Developer ID for releases.)

## 5. Run a notarized release

Smoke-test first without publishing:

```bash
./release.sh 1.7.0 --no-push --notarize
```

That builds, creates the DMG/zip, **and** submits both to Apple. The
script waits for the result (typically 1–5 minutes). On success it
staples the DMG and prints `✓ Notarization complete.`

If smoke succeeds, run the full publish:

```bash
./release.sh 1.7.0 --notarize
```

This adds: commit version files, tag, push, `gh release create`. The
release on GitHub now contains a notarized DMG and zip.

## 6. What `--notarize` actually does

After step 4 (DMG + zip + cask update), the script:

1. `xcrun notarytool submit Binky-$VERSION.dmg --keychain-profile "$BINKY_NOTARY_PROFILE" --wait`
2. `xcrun stapler staple Binky-$VERSION.dmg`
3. `xcrun stapler validate Binky-$VERSION.dmg`
4. `xcrun notarytool submit Binky-$VERSION.zip --keychain-profile "$BINKY_NOTARY_PROFILE" --wait`

The zip is **not** stapled because zip isn't a bundle format — there's
nowhere to staple to. After Apple's notary service approves the zip,
Gatekeeper looks up the notarization status online when a user first
launches the app from that zip. (Once it's approved, every subsequent
launch is offline.) DMG users get a stapled DMG, which works offline
forever, so we recommend the DMG path in the README.

## 7. Troubleshooting

### "binary is not signed with a valid Developer ID certificate"
The Release build was ad-hoc signed (`-`). Open the Xcode project and
confirm signing settings per §4. Re-run `./release.sh ...`.

### "The signature of the binary is invalid"
Hardened Runtime is off, or one of the bundled binaries (`qpdf`,
`create-dmg` cruft) was modified after signing. Rebuild from a clean
tree (`git clean -fdx build/`) and retry.

### "Submission failed" with no further detail
The notary service queue is sometimes slow. Retry with:
```bash
xcrun notarytool submit Binky-$VERSION.dmg \
  --keychain-profile "BinkyNotaryProfile" --wait --output-format json
```
The JSON output includes a submission UUID; pull the full log with:
```bash
xcrun notarytool log <UUID> --keychain-profile "BinkyNotaryProfile"
```

### Profile missing after a Mac wipe / new machine
The keychain profile is per-Mac. Re-run §3.
