#!/bin/bash
# one-command release: tag, push, and publish a github release whose notes come
# straight from the README changelog. closes the "pushed a tag but forgot the
# github release" gap. run with no args to release whatever version the README
# header declares; pass an explicit version (e.g. ./release.sh v0.3) to override.
#
#   ./release.sh            release the version in the README title
#   ./release.sh v0.3       release that version explicitly
#   ./release.sh --dry-run  show what would happen, change nothing
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO" || exit 1
README="$REPO/README.md"
BRANCH="main"

DRY=0
VERSION=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    v*) VERSION="$a" ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

die() { echo "release aborted: $1" >&2; exit 1; }

# version defaults to the "· vX.Y" suffix in the README h1
if [ -z "$VERSION" ]; then
  VERSION="$(sed -n '1s/.*·[[:space:]]*\(v[0-9][0-9.]*\).*/\1/p' "$README")"
  [ -n "$VERSION" ] || die "could not read version from README header; pass it explicitly"
fi

# pull the changelog block for this version: everything between '### vX.Y' and the
# next '### ' heading. these become the github release notes.
NOTES="$(awk -v v="### $VERSION " '
  index($0, v)==1 {grab=1; next}
  grab && /^### / {exit}
  grab {print}
' "$README" | sed '/./,$!d')"
[ -n "$NOTES" ] || die "no changelog section '### $VERSION' found in README"

# safety: clean tree, on the right branch, tools present
[ -z "$(git status --porcelain)" ] || die "working tree not clean - commit first"
[ "$(git rev-parse --abbrev-ref HEAD)" = "$BRANCH" ] || die "not on $BRANCH"
command -v gh >/dev/null || die "gh cli not installed"

echo "version:  $VERSION"
echo "branch:   $BRANCH"
echo "notes:"
echo "$NOTES" | sed 's/^/  | /'
echo

if [ "$DRY" = "1" ]; then
  echo "(dry run - nothing pushed or published)"
  exit 0
fi

# tag (move if it already exists locally), push branch + tag, publish release
git tag -f "$VERSION"
git push origin "$BRANCH"
git push -f origin "$VERSION"

if gh release view "$VERSION" >/dev/null 2>&1; then
  printf '%s' "$NOTES" | gh release edit "$VERSION" --notes-file -
  echo "updated existing release $VERSION"
else
  printf '%s' "$NOTES" | gh release create "$VERSION" --title "$VERSION" --notes-file -
  echo "published release $VERSION"
fi
