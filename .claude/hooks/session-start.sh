#!/bin/bash
# SessionStart hook for Claude Code on the web: make a fresh Linux container able to run the part of
# the definition of done that does not need a Mac (docs/coding-and-testing-guidelines.md).
#
# Three problems, in order of how quietly they break:
#
# 1. The web checkout arrives shallow and without tags. The build number is the commit count
#    (ADR 0004), and scripts/tag_release.py's sequence check reads every tag; a shallow clone gets
#    both wrong without saying so. So this fetches the full history and tags first.
#
# 2. There is no Swift toolchain. AppCore is built to test on Linux (ADR 0007), but only if `swift`
#    is on PATH. This does not download one: the environment's setup script should (Swift's Linux
#    installer at https://www.swift.org/install/linux/, which needs download.swift.org in the
#    environment's network allowlist). Without it, the hook says so loudly, and the steward skill
#    says which workflow to dispatch instead.
#
# 3. There is no Xcode and never will be on Linux: the app's own build and tests always come from
#    tests.yml (.claude/skills/steward/SKILL.md).
#
# Synchronous on purpose (no {"async": true}): a session that starts before the tag fetch finishes
# would compute the wrong build number.
set -euo pipefail

# Web sessions only. A local checkout is the developer's own, possibly one of several worktrees,
# and this must not reach into it.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"

echo "==> Restoring full history and tags (the build number and tag_release.py need them)"
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  # --unshallow fails on a complete repo, hence the branch; the plain --tags retry covers a server
  # that refuses the deepening but still hands over tags.
  git fetch --unshallow --tags origin || git fetch --tags origin
else
  git fetch --tags origin || true
fi
echo "    build number here would be: $(git rev-list --count HEAD)"

echo "==> Swift toolchain"
if command -v swift >/dev/null 2>&1; then
  swift --version 2>&1 | head -1 | sed 's/^/    /'
  echo "==> Resolving AppCore"
  swift package --package-path AppCore resolve
else
  echo "    WARNING: no Swift toolchain on PATH. \`swift test\`, the coverage floor and \`swift format\`"
  echo "    cannot run here; dispatch tests.yml against the branch and read its core and lint jobs."
  echo "    To fix it for every session, install Swift in the environment's setup script."
fi

echo "==> Ready. The app itself builds only on macOS: see .claude/skills/steward/SKILL.md."
