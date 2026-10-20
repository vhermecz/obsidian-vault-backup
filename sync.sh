#!/usr/bin/env bash
# Downloads an Obsidian Sync vault into a fresh directory, mirrors it over the
# repository checkout (keeping .git/ and .github/), and commits any changes.
set -euo pipefail

: "${OBSIDIAN_AUTH_TOKEN:?auth-token input is required}"
: "${VAULT:?vault input is required}"
REPO_DIR="${REPO_DIR:-$PWD}"
DEVICE_NAME="${DEVICE_NAME:-github-actions}"
MAX_SHRINK_PERCENT="${MAX_SHRINK_PERCENT:-50}"
VERBOSE="${VERBOSE:-false}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

ALL_FILE_TYPES="image,audio,video,pdf,unsupported"
ALL_CONFIGS="app,appearance,appearance-data,hotkey,core-plugin,core-plugin-data,community-plugin,community-plugin-data"

vault_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/obsidian-vault.XXXXXX")"
log_file="$(mktemp "${RUNNER_TEMP:-/tmp}/ob-sync.XXXXXX.log")"

# Runs an ob command, hiding its output unless it fails or VERBOSE is set.
run_ob() {
  if [[ "$VERBOSE" == "true" ]]; then
    ob "$@"
  elif ! ob "$@" >"$log_file" 2>&1; then
    echo "::error::'ob $1' failed. Last lines of output:"
    tail -n 30 "$log_file"
    exit 1
  fi
}

echo "Setting up vault in $vault_dir"
setup_args=(sync-setup --vault "$VAULT" --path "$vault_dir" --device-name "$DEVICE_NAME" --json)
if [[ -n "${VAULT_PASSWORD:-}" ]]; then
  setup_args+=(--password "$VAULT_PASSWORD")
fi
run_ob "${setup_args[@]}"
run_ob sync-config --path "$vault_dir" --mode mirror-remote \
  --file-types "$ALL_FILE_TYPES" --configs "$ALL_CONFIGS" --json

echo "Downloading vault"
run_ob sync --path "$vault_dir"
rm -rf "$vault_dir/.obsidian/.sync.lock"

# Guard against a sync that silently came back empty or truncated.
new_count="$(find "$vault_dir" -type f | wc -l)"
old_count="$(git -C "$REPO_DIR" ls-files -- . ':(exclude).github' | wc -l)"
echo "Files in vault: $new_count, files in repo: $old_count"
if (( new_count == 0 )); then
  echo "::error::Downloaded vault is empty; refusing to wipe the repository."
  exit 1
fi
if (( old_count > 0 && (old_count - new_count) * 100 > old_count * MAX_SHRINK_PERCENT )); then
  echo "::error::Vault has $new_count files but the repo has $old_count (more than ${MAX_SHRINK_PERCENT}% fewer). Refusing to sync; raise max-shrink-percent if this is intended."
  exit 1
fi

# Replace everything except .git/ and .github/ with the vault's contents.
find "$REPO_DIR" -mindepth 1 -maxdepth 1 ! -name .git ! -name .github -exec rm -rf {} +
cp -a "$vault_dir/." "$REPO_DIR/"
rm -rf "$vault_dir"

cd "$REPO_DIR"
# --force so .gitignore files inside the vault cannot hide notes from the backup.
git add --all --force -- . ':(exclude).github'
if git diff --cached --quiet; then
  echo "No changes."
  echo "changed=false" >>"$GITHUB_OUTPUT"
  exit 0
fi

git diff --cached --shortstat
git -c user.name="${GIT_USER_NAME:-github-actions[bot]}" \
    -c user.email="${GIT_USER_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}" \
    commit --quiet -m "${COMMIT_MESSAGE:-sync: $(date -u +%F)}"
git push --quiet origin HEAD
echo "changed=true" >>"$GITHUB_OUTPUT"
echo "commit=$(git rev-parse HEAD)" >>"$GITHUB_OUTPUT"
