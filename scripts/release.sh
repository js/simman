#!/bin/bash
# Tags HEAD, builds SimMan.app for release, and publishes it as a GitHub release
# with notes Claude writes from the commits since the previous tag.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "$(git status --porcelain)" ]]; then
	echo "The working tree has uncommitted changes. Commit or stash them first." >&2
	exit 1
fi
git fetch --quiet --tags origin
if ! git merge-base --is-ancestor HEAD origin/main; then
	echo "HEAD isn't on origin/main. Push it first." >&2
	exit 1
fi

previous=$(git tag --list 'v*' --sort=-v:refname | head -1)
echo "Previous tag: ${previous:-none}"
read -rp "New tag: " tag
if [[ ! $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "Use the form v1.2.3." >&2
	exit 1
fi
if git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null; then
	echo "$tag already exists." >&2
	exit 1
fi

make dist VERSION="${tag#v}"
zip="build/SimMan-$tag.zip"
rm -f "$zip"
# ditto archives the bundle the way Finder's Compress does.
ditto -c -k --keepParent build/release/SimMan.app "$zip"

if [[ -n $previous ]]; then
	range="$previous..HEAD"
	scope="the changes since $previous"
else
	range=HEAD
	scope="the first release, so summarise what the app does rather than listing every commit"
fi
prompt="Below are the commit messages for SimMan $tag. SimMan is a macOS menu bar app that shows which git \
worktree each booted iOS simulator loads its Expo app from, and switches a simulator to another worktree. \
Write GitHub release notes for people who use the app, covering $scope. Write a short bulleted list of \
changes a user would notice, one plain sentence per bullet with no bold label. Leave out docs, build and \
refactoring changes, and don't describe how the app feels. Output only the Markdown, with no heading and no \
preamble."

notes=$(mktemp "${TMPDIR:-/tmp}/simman-notes.XXXXXX")
echo "Writing release notes with Claude…"
git log --reverse --format='%s%n%n%b' "$range" | sed '/^Co-Authored-By:/d' |
	claude -p --model claude-sonnet-5-5 --tools "" --no-session-persistence "$prompt" >"$notes"
cat >>"$notes" <<NOTES

## Install

Unzip \`SimMan-$tag.zip\` and move \`SimMan.app\` to \`/Applications\`. SimMan isn't notarized, so macOS blocks the first launch. To allow it, run:

\`\`\`sh
xattr -dr com.apple.quarantine /Applications/SimMan.app
\`\`\`
NOTES

while true; do
	echo
	cat "$notes"
	echo
	read -rp "[p]ublish $tag, [e]dit the notes, or [a]bort? " choice
	case $choice in
	p) break ;;
	e) ${EDITOR:-vi} "$notes" ;;
	*)
		echo "Aborted. Nothing was tagged or uploaded."
		exit 1
		;;
	esac
done

git tag -a "$tag" -m "$tag"
git push origin "$tag"
gh release create "$tag" "$zip" --title "$tag" --notes-file "$notes" --verify-tag
