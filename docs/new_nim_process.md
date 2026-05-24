# Nim binary and Nimby release process

This is the process for moving the treeform Nim toolchain to a new Nim
version. Do not run the release commands until this checklist is complete and
the target versions are written down.

Use placeholders in this document until the real release is ready:

- `<nim-version>` is the Nim version without a leading `v`, for example
  `2.2.10`.
- `<nim-tag>` is the upstream Nim tag with a leading `v`, for example
  `v2.2.10`.
- `<nimby-version>` is the new Nimby release version, for example `0.1.27`.

Commands are written so they can be pasted into PowerShell from `C:\p`.

Every step is gated. If any command, workflow, release, or asset check fails,
stop immediately, save the run URL or error output, inspect the failed logs, and
do not move to the next repo until the failure is understood.

## Preflight

Before changing anything, confirm the current state.

1. Confirm the official Nim tag exists:

   ```powershell
   gh api repos/nim-lang/Nim/tags --jq '.[].name' | rg '^<nim-tag>$'
   ```

2. Confirm whether `treeform/nimby-nim-builds` already has the binary release:

   ```powershell
   gh release view <nim-version> --repo treeform/nimby-nim-builds
   ```

   If the release exists, verify its assets instead of rebuilding it.
   If the release does not exist, continue with the binary build process.

3. Confirm the local repos are on `master` and up to date:

   ```powershell
   git -C C:/p/nimby-nim-builds status --short --branch
   git -C C:/p/setup-nim-action status --short --branch
   git -C C:/p/nimby status --short --branch
   ```

   Each repo should show `## master...origin/master` with no extra changed
   files.

4. Record the current published versions:

   ```powershell
   gh release list --repo treeform/nimby-nim-builds --limit 5
   gh release list --repo treeform/nimby --limit 5
   ```

5. Check every hard-coded old version before editing:

   ```powershell
   rg -n "2\\.2\\.|0\\.1\\.|nim-version|NIM_VERSION|NIMBY_VERSION" C:/p/nimby-nim-builds C:/p/setup-nim-action C:/p/nimby
   ```

6. Confirm the workflows exist with the expected names:

   ```powershell
   gh workflow list --repo treeform/nimby-nim-builds --all
   gh workflow list --repo treeform/setup-nim-action --all
   gh workflow list --repo treeform/nimby --all
   ```

## Monitor Every GitHub Action

Use this pattern for every workflow run that this process starts:

```powershell
gh run list --repo <owner>/<repo> --workflow <workflow-file> --limit 5
gh run watch <run-id> --repo <owner>/<repo> --exit-status
```

If the watch command exits non-zero, stop and inspect the failure:

```powershell
gh run view <run-id> --repo <owner>/<repo> --log-failed
```

Do not continue from a failed or cancelled run. Do not assume a release worked
because the workflow started.

When a push starts many workflows, prefer monitoring the exact commit instead
of visually scanning recent branch runs. First get the real SHA from git:

```powershell
$sha = git -C C:/p/nimby rev-parse HEAD
gh run list --repo treeform/nimby --commit $sha --event push --limit 30
```

For a simple polling loop:

```powershell
$repo = "treeform/nimby"
$sha = git -C C:/p/nimby rev-parse HEAD
$ok = @("success", "skipped")
do {
  $runs = @(gh run list --repo $repo --commit $sha --event push --limit 30 --json databaseId,name,status,conclusion,url | ConvertFrom-Json)
  $runs | Sort-Object name | Format-Table name,status,conclusion,databaseId
  $active = @($runs | Where-Object { $_.status -ne "completed" })
  if ($active.Count -gt 0) { Start-Sleep -Seconds 20 }
} while ($runs.Count -eq 0 -or $active.Count -gt 0)

$failed = @($runs | Where-Object { $ok -notcontains $_.conclusion })
if ($failed.Count -gt 0) {
  $failed | Format-Table name,status,conclusion,databaseId,url
  throw "One or more GitHub runs failed."
}
```

Avoid complicated nested `--jq` strings in PowerShell when filtering by SHA.
It is easy to accidentally break quoting and get confusing `jq` errors. If the
filter is more than a one-liner, either use `--json` and filter in PowerShell or
use `gh run list --commit $sha`.

## Expected Durations and Alert Thresholds

These timings came from a successful Nim `2.2.10` and Nimby `0.1.27` run on
2026-05-24. They are not strict SLAs, but they are good smell tests. If a step
runs much longer than the alert threshold without visible progress, inspect the
run logs before assuming it is normal.

| Step | Typical time observed | Alert threshold |
| --- | ---: | ---: |
| `nimby-nim-builds` dry `Test Release Build` | about 13-14 min total | 30 min |
| Nim binary `Nim Binaries Distribution` | about 14 min total | 35 min |
| Nim binary published `Test` | about 1-2 min total | 10 min |
| `setup-nim-action` master push matrix | under 1 min | 10 min |
| `setup-nim-action` `v6` tag push matrix | under 1 min | 10 min |
| Nimby master push workflows | about 2-3 min total | 15 min |
| Nimby `Nimby Release Binaries` tag workflow | about 2 min total | 15 min |
| Nimby post-release bootstrap workflows | about 2-3 min total | 15 min |

Platform-specific notes:

- Nim binary Windows builds are usually the slowest. A 13-14 minute Windows
  build was normal. If Windows is still compiling after 25-30 minutes, inspect
  logs.
- Nim binary Linux x64 and Linux ARM64 builds were around 8 minutes. If either
  passes 20 minutes, inspect logs.
- Nimby release binaries are much faster than Nim compiler binaries. If a Nimby
  release build takes many minutes on any platform, that is unusual.
- Release upload jobs should usually finish in seconds once all artifacts are
  built. If the upload job is stuck for several minutes, inspect it.

## Runbook Gotchas From 2026-05-24

- `setup-nim-action` does not have `workflow_dispatch`. Pushing `master` starts
  CI, and moving `v6` starts another tag-push CI run. Watch both before using
  the action from Nimby.
- When locating runs for a pushed commit, use the exact SHA from
  `git rev-parse HEAD`. Do not type or guess the SHA from memory.
- Moving `setup-nim-action@v6` is a forced tag update. Verify the remote tag
  after pushing:

  ```powershell
  git -C C:/p/setup-nim-action ls-remote --tags origin v6
  ```

- `test_from_nothing.yml` has to be updated in two phases. Before the new Nimby
  release exists, keep `NIMBY_VERSION` on the previous published release while
  changing `NIM_VERSION` to the new Nim version. After the new Nimby release
  assets exist, make a follow-up commit changing `NIMBY_VERSION` to the new
  Nimby release and watch `Test setup Nim from nothing.` again.
- Local `nim r tests/test_commands.nim` can fail on Windows because
  `%TEMP%\nimby_tests` is still locked when the next test tries to delete it.
  This showed up as `The process cannot access the file because it is being used
  by another process`. Treat the Linux GitHub `Test` workflow as the release
  gate for that suite unless the Windows cleanup code is fixed.
- GitHub may show a notice that `windows-latest` is being redirected to
  `windows-2025-vs2026` by 2026-06-15. That notice is not a failure, but it is
  worth tracking because Windows build behavior can change.
- Node.js 20 deprecation warnings in Actions are not release blockers, but they
  are real maintenance debt. If touching workflows, update stale actions such as
  `actions/checkout@v3`, old artifact actions, or old release actions.

## Repo 1: Nim Binary Builds

Repo: `C:/p/nimby-nim-builds`

GitHub: `treeform/nimby-nim-builds`

Workflows that must exist:

- `.github/workflows/test_release.yml`
  - Action name: `Test Release Build`
  - Purpose: builds all binary artifacts without publishing a GitHub release.
- `.github/workflows/release.yml`
  - Action name: `Nim Binaries Distribution`
  - Purpose: builds all binary artifacts and creates or updates the release.
- `.github/workflows/test.yml`
  - Action name: `Test`
  - Purpose: downloads an already published binary release and smoke-tests Nim
    and Nimby.

Order:

1. Run `Test Release Build` for `<nim-version>`.

   ```powershell
   gh workflow run test_release.yml --repo treeform/nimby-nim-builds -f nim_version=<nim-version>
   ```

   Gate: the workflow must finish successfully on:

   - Linux X64
   - Linux ARM64
   - macOS ARM64
   - Windows X64

2. Run `Nim Binaries Distribution` for `<nim-version>`.

   ```powershell
   gh workflow run release.yml --repo treeform/nimby-nim-builds -f nim_version=<nim-version>
   ```

   Gate: the release workflow must finish successfully.

3. Verify the release exists and has all expected assets:

   ```powershell
   gh release view <nim-version> --repo treeform/nimby-nim-builds --json tagName,name,publishedAt,assets
   ```

   Expected assets:

   - `nim-<nim-version>-Linux-X64.tar.gz`
   - `nim-<nim-version>-Linux-ARM64.tar.gz`
   - `nim-<nim-version>-macOS-ARM64.tar.gz`
   - `nim-<nim-version>-Windows-X64.zip`

   Each asset must be uploaded, have a non-zero size, and have the expected
   platform name.

4. Run `Test` for `<nim-version>`.

   ```powershell
   gh workflow run test.yml --repo treeform/nimby-nim-builds -f nim_version=<nim-version>
   ```

   Gate: the workflow must finish successfully. This proves the published
   binaries can be downloaded, extracted, added to `PATH`, and used to compile a
   small Nim program.

Watch for:

- `test.yml` has two defaults today: the workflow input default and the
  `NIM_VERSION` fallback. Keep them in sync when updating defaults.
- `release.yml` expects `<nim-version>` without `v`, but clones upstream Nim
  with `v<nim-version>`.
- Older action versions in this repo may emit Node.js 20 deprecation warnings.
  They do not mean the release failed. Still, record them and update the
  workflow actions in a separate maintenance pass if they remain.

## Repo 2: Setup Nim Action

Repo: `C:/p/setup-nim-action`

GitHub: `treeform/setup-nim-action`

Files that matter:

- `action.yml`
- `.github/workflows/test.yml`

Required edits when moving the default Nim version:

1. Update `action.yml`:

   - `inputs.nim-version.description` example.
   - `inputs.nim-version.default`.

2. Update `.github/workflows/test.yml`:

   - Add `<nim-version>` to the test matrix.
   - Keep at least one older supported Nim version in the matrix if we still
     want backwards coverage.

3. Run the setup action tests by pushing a branch or opening a PR.

   The current setup action workflow triggers on `push` and `pull_request`.
   It does not have `workflow_dispatch`, so do not try to start it with
   `gh workflow run` unless the workflow has been updated to include manual
   dispatch.

   Gate: the workflow must finish successfully on:

   - Linux X64
   - Linux ARM64
   - macOS ARM64
   - Windows X64

4. Handle the action tag intentionally.

   Downstream workflows currently use `treeform/setup-nim-action@v6`. Updating
   `master` alone does not update callers pinned to `@v6`.

   Before moving to Nimby, decide one of these:

   - Move the `v6` tag to the tested commit if `v6` is the continuing major
     version.
   - Create `v7` and update downstream workflows from `@v6` to `@v7`.

   Gate: verify the tag points to the intended commit before continuing.

   ```powershell
   git -C C:/p/setup-nim-action rev-parse master
   git -C C:/p/setup-nim-action rev-parse v6
   git -C C:/p/setup-nim-action ls-remote --tags origin v6
   ```

   Watch for: pushing the moved `v6` tag starts another workflow run with
   `headBranch` set to `v6`. That tag-push run must also pass before moving on
   to Nimby.

## Repo 3: Nimby

Repo: `C:/p/nimby`

GitHub: `treeform/nimby`

Files that usually need version edits:

- `nimby.nimble`
  - Bump `version` to `<nimby-version>`.
- `src/nimby.nim`
  - Update `writeVersion`.
- `README.md`
  - Update raw download links to the new Nimby release after the release exists.
  - Update `nimby use <nim-version>` examples.
- `.github/workflows/test_install_nim.yml`
  - Update `src/nimby use -V <nim-version>`.
- `.github/workflows/test_from_nothing.yml`
  - Update `NIM_VERSION`.
  - Update `NIMBY_VERSION` only after the new Nimby release exists.
- `.github/workflows/*.yml`
  - If touching workflows anyway, update old GitHub action refs so the release
    does not carry avoidable Node deprecation warnings.

Important ordering:

1. Make sure `treeform/setup-nim-action@v6` or the chosen new action tag points
   to the tested setup action commit. Nimby's release workflow uses the setup
   action, so this must be fixed before building Nimby.

2. Update Nimby code and tests for `<nim-version>` and `<nimby-version>`.

   For the first commit before the Nimby release exists:

   - Update `nimby.nimble` to `<nimby-version>`.
   - Update `src/nimby.nim` `writeVersion` to `<nimby-version>`.
   - Update README Nim examples to `<nim-version>`.
   - Update README release links only if the release will be created from this
     commit and the README examples are skipped by tests.
   - Update `test_install_nim.yml` to `<nim-version>`.
   - Update `test_from_nothing.yml` `NIM_VERSION` to `<nim-version>`.
   - Keep `test_from_nothing.yml` `NIMBY_VERSION` on the previous release until
     the new Nimby assets exist.

3. Run Nimby tests on the branch or PR:

   Required workflows:

   - `test.yml` (`Test`)
   - `test_install_nim.yml` (`Test install Nim`)
   - `test_from_nothing.yml` (`Test setup Nim from nothing.`)
   - `test_readme.yaml` (`Test README`)
   - `test_install_from_file.yml` (`Test Install From a .nimble File`)
   - `test_sync_lock_file.yml` (`Test Sync Lock File`)

   Gate: each required workflow must finish successfully.

4. Create the Nimby release for `<nimby-version>`.

   The release workflow is `.github/workflows/release.yml` and the action name
   is `Nimby Release Binaries`. Although the workflow has `workflow_dispatch`,
   the release upload job only runs for a published GitHub release or a pushed
   tag. Use a tag or GitHub release for the real release. A manual dispatch is
   only useful as a build smoke test.

   Gate: the release workflow must finish successfully.

5. Verify the release assets:

   ```powershell
   gh release view <nimby-version> --repo treeform/nimby --json tagName,name,publishedAt,assets
   ```

   Expected assets:

   - `nimby-Linux-X64`
   - `nimby-Linux-ARM64`
   - `nimby-macOS-ARM64`
   - `nimby-Windows-X64.exe`

6. After the release assets exist, update README raw download links and
   `.github/workflows/test_from_nothing.yml` to use `<nimby-version>`.

7. Run `Test README` and `Test setup Nim from nothing.` again by pushing the
   final branch or PR update.

   Gate: both must pass after the README and raw setup version changes.

   In practice, this final push may start the whole normal workflow set again.
   That is fine. Watch all runs for the exact commit and require success or
   expected skipped status.

Watch for:

- `README.md` may contain both the Nim version and the Nimby release version.
  Update the right value in each place.
- `test_from_nothing.yml` downloads the published Nimby binary, so it cannot use
  `<nimby-version>` until that release exists.
- `nimby.nimble` and `writeVersion` must match before tagging a Nimby release.
- The current master may contain commits newer than the latest published Nimby
  release. Do not assume the latest tag is the same as current `master`.

## Final Verification

The whole process is complete only when all of these are true:

- `treeform/nimby-nim-builds` has release `<nim-version>`.
- The Nim binary release has all four expected platform assets.
- The binary release `Test` workflow passes for `<nim-version>`.
- `treeform/setup-nim-action` default version is `<nim-version>`.
- The setup action tag used by downstream workflows points to the tested commit.
- `treeform/nimby` has release `<nimby-version>`.
- The Nimby release has all four expected platform assets.
- Nimby README download links point to `<nimby-version>`.
- Nimby examples and raw setup tests use `<nim-version>`.
- All required workflows are green after the final README and workflow edits.
