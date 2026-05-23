#!/bin/bash
# release.sh — build, package, and publish a new Binky release.
#
# Usage:
#   ./release.sh 1.2.3
#   ./release.sh 1.2.3 --bump-only            # steps 1–2 only (no build, git, or gh)
#   ./release.sh 1.2.3 --no-push              # steps 1–4 (bump, build, DMG, cask) — no commit, tag, push, or gh release
#   ./release.sh 1.2.3 --notarize             # also notarize + staple the DMG/zip after build (requires Apple Developer ID)
#   ./release.sh 1.2.3 --no-push --notarize   # combine: build + notarize, no publish
#
# Notarization (off by default — see docs/release.md for setup):
#   When --notarize is passed, the script submits Binky-$VERSION.{dmg,zip} to
#   Apple's notary service (notarytool), waits for the result, and staples the
#   ticket onto the DMG. The keychain profile name is read from the env var
#   $BINKY_NOTARY_PROFILE (default: "BinkyNotaryProfile"). Until a paid Apple
#   Developer ID + signing certificate + stored notary profile are configured,
#   leave this flag off; releases will be ad-hoc-signed and require users to
#   right-click → Open or run xattr -dr com.apple.quarantine on first launch.
#
# What it does:
#   1. Bumps MARKETING_VERSION + CURRENT_PROJECT_VERSION in the Xcode project
#   2. Updates only explicit version copy/download tokens on site pages
#   3. Builds the Release scheme
#   4. Creates the DMG (+ zip for in-app updater), then updates Casks/binky.rb (version + sha256 of the zip) for Homebrew
#   4b. (--notarize) Submits DMG/zip to Apple's notary service and staples the DMG
#   5. Commits, tags, pushes, and publishes the GitHub release
#
# Release notes: if a previous `v*` tag exists, notes use `git log $PREV_GIT_TAG..HEAD` (subjects
# only, chronological), excluding the “Bump to v$VERSION” commit. With **no** prior tag (first
# public release), notes list the full repo history the same way. Edit the release on GitHub
# afterward if you want prose or grouping.
#
# Commit all app/source changes before running: the tag must point at a tree that includes the full
# app, not only version-string files.
#
# Prerequisites: create-dmg (brew install create-dmg), gh (brew install gh)
# For --notarize: an Apple Developer ID + a stored `xcrun notarytool store-credentials` profile

set -e  # exit on any error

# ── Args ──────────────────────────────────────────────────────────────────────

BUMP_ONLY=false
NO_PUSH=false
NOTARIZE=false
VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bump-only) BUMP_ONLY=true; shift ;;
    --no-push)   NO_PUSH=true;   shift ;;
    --notarize)  NOTARIZE=true;  shift ;;
    *)
      if [ -n "$VERSION" ]; then
        echo "Usage: ./release.sh <version> [--bump-only|--no-push] [--notarize]"
        exit 1
      fi
      VERSION="$1"
      shift
      ;;
  esac
done

if [ -z "$VERSION" ]; then
  echo "Usage: ./release.sh <version> [--bump-only|--no-push] [--notarize]"
  echo "  --bump-only  Steps 1–2 only: write version into project + site, no build, git, or gh."
  echo "  --no-push    Steps 1–4: bump, build Release, create DMG + zip, update Cask. No commit, tag, push, or gh release."
  echo "  --notarize   After building, submit DMG + zip to Apple notary service and staple the DMG."
  echo "               Requires \$BINKY_NOTARY_PROFILE (default: \"BinkyNotaryProfile\") configured via"
  echo "               'xcrun notarytool store-credentials'. See docs/release.md."
  exit 1
fi

if [ "$BUMP_ONLY" = true ] && [ "$NO_PUSH" = true ]; then
  echo "✗ --bump-only and --no-push are mutually exclusive."
  exit 1
fi

if [ "$BUMP_ONLY" = true ] && [ "$NOTARIZE" = true ]; then
  echo "✗ --bump-only skips the build, so --notarize has nothing to submit."
  exit 1
fi

# Pre-flight notarization config so we fail fast (before the long build) if the
# user passed --notarize without setting up credentials. Actual notarytool
# invocation happens after the DMG is built.
NOTARY_PROFILE="${BINKY_NOTARY_PROFILE:-BinkyNotaryProfile}"
if [ "$NOTARIZE" = true ]; then
  if ! xcrun --find notarytool >/dev/null 2>&1; then
    echo "✗ --notarize requested but xcrun notarytool not found. Install Xcode command-line tools."
    exit 1
  fi
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "✗ --notarize requested but keychain profile \"$NOTARY_PROFILE\" is missing or invalid."
    echo "  Set up once with:"
    echo "    xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
    echo "      --apple-id <YOUR_APPLE_ID> --team-id <TEAM_ID> --password <APP_SPECIFIC_PASSWORD>"
    echo "  Or override the profile name via \$BINKY_NOTARY_PROFILE."
    echo "  Full setup guide: docs/release.md."
    exit 1
  fi
fi

if [ "$BUMP_ONLY" = false ] && git rev-parse "refs/tags/v$VERSION" >/dev/null 2>&1; then
  echo "✗ Git tag v$VERSION already exists locally. Remove it or choose another version."
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "✗ Working tree is not clean. Commit or stash all changes first so the v$VERSION tag includes the full app."
  git status -sb
  exit 1
fi

FILE_MARKETING=$(grep "MARKETING_VERSION" Binky.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //;s/;//')
FILE_BUILD=$(grep "CURRENT_PROJECT_VERSION" Binky.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //;s/;//')
OLD_MARKETING="$FILE_MARKETING"

echo "▶ Releasing Binky v$VERSION (project marketing version is $FILE_MARKETING)"
echo ""

replace_token_if_present() {
  local file="$1"
  local old="$2"
  local new="$3"
  [ -f "$file" ] || return 0

  python3 - "$file" "$old" "$new" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
old = sys.argv[2]
new = sys.argv[3]

text = path.read_text(encoding="utf-8")
if old not in text:
    raise SystemExit(0)

path.write_text(text.replace(old, new), encoding="utf-8")
PY
}

# ── 1. Bump version (skip if project + site already at $VERSION) ─────────────

if [ "$FILE_MARKETING" != "$VERSION" ]; then
  echo "→ Bumping version in project.pbxproj…"
  sed -i '' "s/MARKETING_VERSION = $FILE_MARKETING/MARKETING_VERSION = $VERSION/g" \
    Binky.xcodeproj/project.pbxproj
  sed -i '' "s/CURRENT_PROJECT_VERSION = $FILE_BUILD/CURRENT_PROJECT_VERSION = $VERSION/g" \
    Binky.xcodeproj/project.pbxproj
else
  echo "→ Project already at $VERSION (skipping pbxproj bump)"
fi

# ── 2. Update site ────────────────────────────────────────────────────────────

if [ "$OLD_MARKETING" != "$VERSION" ]; then
  echo "→ Updating site version copy tokens…"
  replace_token_if_present site/index.html "\"softwareVersion\": \"$OLD_MARKETING\"" "\"softwareVersion\": \"$VERSION\""
  replace_token_if_present site/index.html "v$OLD_MARKETING/Binky-$OLD_MARKETING.dmg" "v$VERSION/Binky-$VERSION.dmg"
  replace_token_if_present site/index.html "v$OLD_MARKETING · Requires" "v$VERSION · Requires"
  # Hero line uses "Apple Silicon" instead of "Requires" (compare pages).
  replace_token_if_present site/index.html "v$OLD_MARKETING · Apple Silicon" "v$VERSION · Apple Silicon"

  replace_token_if_present site/llms.txt "Download v$OLD_MARKETING:" "Download v$VERSION:"
  replace_token_if_present site/llms.txt "v$OLD_MARKETING/Binky-$OLD_MARKETING.dmg" "v$VERSION/Binky-$VERSION.dmg"

  if [ -f site/homepage.md ]; then
    replace_token_if_present site/homepage.md "v$OLD_MARKETING/Binky-$OLD_MARKETING.dmg" "v$VERSION/Binky-$VERSION.dmg"
  fi

  if compgen -G "site/compare/*/index.html" > /dev/null || [ -f site/compare/index.html ]; then
    for f in site/compare/*/index.html site/compare/index.html; do
      [ -f "$f" ] || continue
      replace_token_if_present "$f" "v$OLD_MARKETING · Requires" "v$VERSION · Requires"
      replace_token_if_present "$f" "v$OLD_MARKETING/Binky-$OLD_MARKETING.dmg" "v$VERSION/Binky-$VERSION.dmg"
    done
  fi
else
  echo "→ Site strings already match v$VERSION (skipping site sed)"
fi

if [ "$BUMP_ONLY" = true ]; then
  echo ""
  echo "✓ Bump only — updated project + site strings to v$VERSION."
  echo "  Commit those files, then: ./release.sh $VERSION  (full build, tag, gh release)"
  exit 0
fi

PREV_GIT_TAG=$(git tag -l 'v*' --sort=-version:refname | head -1 || true)
if [ -z "$PREV_GIT_TAG" ]; then
  echo "→ No previous v* tags (treating this as first public release for release notes)."
fi

# ── 3. Build ──────────────────────────────────────────────────────────────────

echo "→ Building Release…"
xcodebuild -scheme Binky -configuration Release -derivedDataPath build \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

# ── 4. Create DMG ─────────────────────────────────────────────────────────────

echo "→ Creating Binky-$VERSION.dmg…"
rm -f "Binky-$VERSION.dmg"
create-dmg \
  --volname "Binky" \
  --volicon "build/Build/Products/Release/Binky.app/Contents/Resources/AppIcon.icns" \
  --background "dmg-background.tiff" \
  --window-pos 200 120 \
  --window-size 420 520 \
  --icon-size 100 \
  --icon "Binky.app" 210 160 \
  --hide-extension "Binky.app" \
  --app-drop-link 210 370 \
  "Binky-$VERSION.dmg" \
  "build/Build/Products/Release/Binky.app"

echo "→ Creating Binky-$VERSION.zip (for in-app updater)…"
rm -f "Binky-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent \
  "build/Build/Products/Release/Binky.app" \
  "Binky-$VERSION.zip"

CASK_SHASUM=$(shasum -a 256 "Binky-$VERSION.zip" | awk '{print $1}')
echo "→ Updating Casks/binky.rb (version $VERSION, sha256)…"
sed -i '' "s/version \".*\"/version \"$VERSION\"/" Casks/binky.rb
sed -i '' "s/sha256 \".*\"/sha256 \"$CASK_SHASUM\"/" Casks/binky.rb
python3 - <<'PY'
import pathlib
import re
import sys

path = pathlib.Path("Casks/binky.rb")
text = path.read_text(encoding="utf-8")
pattern = re.compile(
    r'url "https://github\.com/heyderekj/binky/releases/download/v#\{version\}/Binky-#\{version\}\.zip"(?:,\n\s*verified: "github\.com/heyderekj/binky/")?'
)
replacement = (
    'url "https://github.com/heyderekj/binky/releases/download/v#{version}/Binky-#{version}.zip",\n'
    '      verified: "github.com/heyderekj/binky/"'
)

new_text, count = pattern.subn(replacement, text, count=1)
if count == 0:
    print("✗ Could not find cask URL stanza to enforce verified metadata.", file=sys.stderr)
    sys.exit(1)

path.write_text(new_text, encoding="utf-8")
PY

# ── 4b. Notarize (optional) ───────────────────────────────────────────────────
#
# We submit both artifacts so the in-app zip updater path is also covered. zip
# can't be stapled (it's not a bundle), but a successful notarytool submission
# means Gatekeeper will look up the ticket online when a user first runs the
# app. The DMG IS stapled, so DMG users keep working offline forever.

if [ "$NOTARIZE" = true ]; then
  echo "→ Notarizing Binky-$VERSION.dmg…"
  xcrun notarytool submit "Binky-$VERSION.dmg" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  echo "→ Stapling notarization ticket onto DMG…"
  xcrun stapler staple "Binky-$VERSION.dmg"
  xcrun stapler validate "Binky-$VERSION.dmg"

  echo "→ Notarizing Binky-$VERSION.zip (no staple — zip ticket lives only on Apple's side)…"
  xcrun notarytool submit "Binky-$VERSION.zip" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  echo "✓ Notarization complete. DMG is stapled and works offline; zip relies on Apple's online check."
else
  echo "→ Skipping notarization (no --notarize flag)."
  echo "  Users who download Binky-$VERSION.dmg will see Gatekeeper prompts on first launch."
  echo "  See docs/release.md for one-time signing/notarization setup."
fi

# ── 5. Optional bump commit, push, tag, release ─────────────────────────────

# --no-push: stop here. The DMG / zip / updated Cask are on disk for inspection or for kicking off
# a release manually. No git or gh side-effects so a typo in <version> can be undone with `git
# checkout` and re-run.
if [ "$NO_PUSH" = true ]; then
  echo ""
  echo "✓ --no-push: built Binky v$VERSION locally (DMG + zip + cask updated)."
  echo "  Skipped: commit, tag, push, gh release."
  echo "  Inspect:"
  echo "    open Binky-$VERSION.dmg"
  echo "    git status"
  echo "  When you're satisfied, re-run without --no-push to publish, or:"
  echo "    git add -A && git commit -m \"Bump to v$VERSION\""
  echo "    git tag v$VERSION && git push origin main v$VERSION"
  echo "    gh release create v$VERSION Binky-$VERSION.dmg Binky-$VERSION.zip --title \"Binky $VERSION\""
  exit 0
fi

echo "→ Committing version files (if changed by this run)…"
git add Casks/binky.rb Binky.xcodeproj/project.pbxproj site/index.html site/llms.txt README.md
[ -f site/homepage.md ] && git add site/homepage.md
if compgen -G "site/compare/*/index.html" > /dev/null; then
  git add site/compare/*/index.html
fi
[ -f site/compare/index.html ] && git add site/compare/index.html
if git diff --cached --quiet; then
  echo "  (nothing to commit — version already in repo)"
else
  git commit -m "Bump to v$VERSION"
fi
git push origin main

echo "→ Tagging and publishing release…"
git tag "v$VERSION"
git push origin "v$VERSION"

if [ -n "$PREV_GIT_TAG" ]; then
  echo "→ Composing release notes from git ($PREV_GIT_TAG..HEAD, excluding version bump)…"
else
  echo "→ Composing release notes from git (full history, excluding version bump)…"
fi
NOTES_FILE=$(mktemp)
{
  echo "## Binky $VERSION"
  echo ""
  if [ -n "$PREV_GIT_TAG" ]; then
    echo "Changes since **$PREV_GIT_TAG** (commit subjects from this repo):"
  else
    echo "First public release — commit subjects from this repo (chronological):"
  fi
  echo ""
  if [ -n "$PREV_GIT_TAG" ] && git rev-parse "$PREV_GIT_TAG" >/dev/null 2>&1; then
    LIST=$(git log --no-merges "$PREV_GIT_TAG"..HEAD --pretty=format:'%s' --reverse | grep -vFx "Bump to v$VERSION" || true)
    if [ -n "$LIST" ]; then
      echo "$LIST" | while IFS= read -r subject; do
        [ -n "$subject" ] && echo "- $subject"
      done
    else
      echo "- *(No commits listed besides the version bump — describe this release manually on GitHub if needed.)*"
    fi
  elif [ -n "$PREV_GIT_TAG" ]; then
    echo "- **Warning:** git tag \`$PREV_GIT_TAG\` not found locally. Run \`git fetch --tags\` or edit release notes on GitHub."
  else
    LIST=$(git log --no-merges --pretty=format:'%s' --reverse | grep -vFx "Bump to v$VERSION" || true)
    if [ -n "$LIST" ]; then
      echo "$LIST" | while IFS= read -r subject; do
        [ -n "$subject" ] && echo "- $subject"
      done
    else
      echo "- *(No commit subjects found — describe this release manually on GitHub if needed.)*"
    fi
  fi
  echo ""
  echo "## Install"
  echo ""
  echo "**Homebrew (optional):**"
  echo ""
  echo "\`\`\`bash"
  echo "brew tap heyderekj/binky https://github.com/heyderekj/binky"
  echo "brew install --cask binky"
  echo "\`\`\`"
  echo ""
  echo "**Or** download **Binky-$VERSION.dmg** from the assets below and drag **Binky** into Applications. Already using Binky? Choose **Install Update** from the in-app banner when it appears."
  echo ""
  echo "## Finder “Open With” shows two Binkys"
  echo ""
  echo "macOS lists each **Binky.app** on disk with its own version. After an upgrade, an older copy is often still around."
  echo ""
  echo "- **Homebrew:** \`brew cleanup binky\` (or \`brew cleanup\`) removes old cask versions under Caskroom."
  echo '- **List every copy:** `mdfind '\''kMDItemCFBundleIdentifier == "com.binky.app"'\''` in Terminal; delete extras you do not need (e.g. in Downloads).'
} > "$NOTES_FILE"

gh release create "v$VERSION" \
  "Binky-$VERSION.dmg" \
  "Binky-$VERSION.zip" \
  --title "Binky $VERSION" \
  --notes-file "$NOTES_FILE" \
  --verify-tag

rm -f "$NOTES_FILE"

echo ""
echo "✓ Binky v$VERSION released."
echo "  https://github.com/heyderekj/binky/releases/tag/v$VERSION"
