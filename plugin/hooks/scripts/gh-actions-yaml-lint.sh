#!/usr/bin/env bash
# gh-actions-yaml-lint - PostToolUse Edit|Write hook on .github/workflows/*.{yml,yaml}.
#
# Validates GitHub Actions workflow YAML by parsing it with PyYAML. Blocks
# the tool call on parse error so Claude sees the failure immediately and
# can re-edit, rather than committing/pushing a broken workflow that
# startup-fails on GitHub with a 0-second / 0-jobs / "workflow file issue"
# result that's annoying to debug remotely.
#
# Common failure mode this catches: multi-line bash strings inside `run: |`
# blocks where the continuation line starts at column 1, terminating the
# YAML block scalar prematurely.
#
# Bypass: rare. If you're intentionally writing invalid YAML for a test,
# rename the file out of .github/workflows/ first.
set -o pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

[ -z "$file_path" ] && exit 0

# Only GitHub Actions workflow files.
case "$file_path" in
  */.github/workflows/*.yml|*/.github/workflows/*.yaml) ;;
  *) exit 0 ;;
esac

[ -f "$file_path" ] || exit 0

# Validate via PyYAML. Use the system python3 first; fall back to uvx if
# pyyaml isn't available in the system python.
err=""
if python3 -c "import yaml" 2>/dev/null; then
  err=$(python3 -c "
import sys, yaml
try:
    with open(sys.argv[1]) as f:
        yaml.safe_load(f)
except yaml.YAMLError as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
" "$file_path" 2>&1)
elif command -v uvx >/dev/null 2>&1; then
  err=$(uvx --quiet --from pyyaml python -c "
import sys, yaml
try:
    with open(sys.argv[1]) as f:
        yaml.safe_load(f)
except yaml.YAMLError as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
" "$file_path" 2>&1)
else
  # No YAML parser available. Skip silently rather than blocking.
  exit 0
fi

# If python exited non-zero, $err contains the parse error.
if [ -n "$err" ]; then
  cat <<EOF >&2
🚫 BLOCKED: invalid YAML in GitHub Actions workflow:

  $file_path

PyYAML parse error:
$err

Common cause: multi-line bash string inside \`run: |\` block where the
continuation line starts at column 1. This terminates the YAML block
scalar early. Use printf with \\n instead, or indent the continuation
to match the block.

Fix the YAML before committing. Pushing a broken workflow results in
a 0-second / no-jobs / "workflow file issue" run on GitHub that's
opaque to debug remotely.
EOF
  exit 2
fi

exit 0
