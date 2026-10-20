# Obsidian Vault Backup

A GitHub Action that mirrors an [Obsidian Sync](https://obsidian.md/sync) vault into the root of a repository, using the official [`obsidian-headless`](https://www.npmjs.com/package/obsidian-headless) client, and commits whatever changed.

- **One-way mirror.** The vault is downloaded with `mirror-remote` mode into a fresh directory on every run, so nothing is ever uploaded back to Obsidian Sync.
- **Everything is included:** all attachment types and all config categories, including community plugins and their settings.
- **The repository becomes the vault.** Files deleted from the vault are deleted from the repo. `.git/` and `.github/` are left alone; everything else is replaced.
- **Safety check.** The run fails without touching the repo if the download comes back empty, or would remove more than `max-shrink-percent` of the existing files.
- **Quiet logs.** File names are not printed unless `verbose: true`, so a backup repo's Actions logs don't list your notes.

## Usage

Create a **private** repository for the backup and add `.github/workflows/sync.yml`:

```yaml
name: Sync Obsidian vault

on:
  schedule:
    - cron: "0 3 * * *"
  workflow_dispatch:

permissions:
  contents: write

concurrency:
  group: obsidian-sync

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: vhermecz/obsidian-vault-backup@v1
        with:
          vault: ${{ vars.OBSIDIAN_VAULT }}
          auth-token: ${{ secrets.OBSIDIAN_AUTH_TOKEN }}
          vault-password: ${{ secrets.OBSIDIAN_VAULT_PASSWORD }}
```

Then, in the repository's **Settings → Secrets and variables → Actions**:

| Kind | Name | Value |
|---|---|---|
| Variable | `OBSIDIAN_VAULT` | Vault name or ID, as shown by `ob sync-list-remote` |
| Secret | `OBSIDIAN_AUTH_TOKEN` | Your Obsidian auth token (see below) |
| Secret | `OBSIDIAN_VAULT_PASSWORD` | The vault's end-to-end encryption password (omit for standard encryption) |

### Getting the auth token

On your own machine (Node.js 22+):

```bash
npx obsidian-headless login          # interactive; handles 2FA
cat ~/.config/obsidian-headless/auth_token
```

On macOS and Windows the file is at `~/.obsidian-headless/auth_token`. The token stays valid until you run `ob logout`, so the same token can be used for several backup repositories.

## Inputs

| Input | Default | Description |
|---|---|---|
| `vault` | *required* | Remote vault name or ID. |
| `auth-token` | *required* | Obsidian auth token. |
| `vault-password` | `""` | End-to-end encryption password. |
| `device-name` | `github-actions` | Device name reported to Obsidian Sync. |
| `max-shrink-percent` | `50` | Abort if more than this percentage of the repo's files would be removed. `100` disables the check. |
| `commit-message` | `sync: YYYY-MM-DD` | Commit message. |
| `git-user-name` | `github-actions[bot]` | Commit author name. |
| `git-user-email` | GitHub Actions bot address | Commit author email. |
| `verbose` | `false` | Print the full sync log (lists file names). |
| `obsidian-headless-version` | `0.0.14` | npm version of `obsidian-headless`. |
| `token` | `github.token` | Token used to check out and push. |

## Outputs

| Output | Description |
|---|---|
| `changed` | `"true"` if a commit was pushed. |
| `commit` | SHA of the pushed commit. |

## Notes

- The action checks out the repository itself; don't add a separate `actions/checkout` step.
- GitHub rejects files larger than 100 MB. A vault containing such a file will fail to push.
- Git doesn't track empty folders, so empty vault folders don't appear in the backup.
- GitHub disables scheduled workflows after 60 days without repository activity. If the vault goes untouched that long, re-enable the workflow from the Actions tab.
