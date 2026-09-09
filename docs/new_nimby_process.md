# New Nimby release process

This is the process for shipping a new Nimby version across the whole treeform
Nim toolchain. Do not run the release commands until this checklist is complete
and the target version is written down.

This document is the sibling of [`new_nim_process.md`](new_nim_process.md).
Use that one when the Nim version moves. Use this one when only Nimby moves.

The difference that makes this process its own document: **every Nim binary
distribution ships a copy of Nimby baked into `bin/`.** Releasing a new Nimby
binary is only half the job. The other half is rebuilding every published Nim
distribution so it carries the new Nimby instead of the old one.

Use placeholders in this document until the real release is ready:

- `<nimby-version>` is the new Nimby release version, for example `0.1.28`.
- `<prev-nimby-version>` is the currently published Nimby release, for example
  `0.1.27`.
- `<nim-version>` is a Nim version that has a binary distribution, for example
  `2.2.10`.

Commands are written so they can be pasted into PowerShell from `C:\p`.

Every step is gated. If any command, workflow, release, or asset check fails,
stop immediately, save the run URL or error output, inspect the failed logs, and
do not move to the next repo or the next Nim version until the failure is
understood.

## How Nimby gets into a Nim binary distribution

Read this before doing anything. The rebuild half of this process only makes
sense once this is clear.

`treeform/nimby-nim-builds` `.github/workflows/release.yml` has a
`Clone and build nimby` step that does this:

```bash
git clone --depth 1 https://github.com/treeform/nimby.git
cd nimby
nim c -d:release -o:nimby src/nimby.nim
cp nimby ../Nim/bin/
```

Three consequences drive this whole document:

1. **The bundled Nimby is not pinned.** It is a shallow clone of Nimby's
   default branch at the moment the workflow runs. Whatever is on `master`
   when the job runs is what ends up in `bin/`. There is no tag, no submodule,
   and no version input.

2. **Rebuilding is how you upgrade the bundled Nimby.** There is no way to
   patch an existing distribution asset. To get `<nimby-version>` into the
   `<nim-version>` distribution, you re-run `Nim Binaries Distribution` for
   `<nim-version>` after Nimby `master` carries the new code.

3. **Nimby is compiled by the Nim it will ship with.** The bundled Nimby for
   the Nim `2.0.16` distribution is compiled by the freshly built Nim `2.0.16`.
   If new Nimby code needs a language or stdlib feature newer than an old
   supported Nim, that distribution's rebuild fails. `nimby.nimble` currently
   declares `requires "nim >= 2.0.0"`, so that is the floor being promised.

Because of 1 and 2, **Nimby `master` must be frozen for the duration of the
rebuild phase.** If someone lands a commit on Nimby `master` while the Nim
distributions are rebuilding, some distributions get the released Nimby and
others get an unreleased Nimby, and there is no way to tell them apart from the
outside.

Other places Nimby's version is referenced, all of which have to move too:

| Place | What it is |
| --- | --- |
| `nimby.nimble` `version` | Package version |
| `src/nimby.nim` `writeVersion` | What `nimby --version` prints |
| `README.md` curl links | Raw download instructions |
| `.github/workflows/test_from_nothing.yml` `NIMBY_VERSION` | Downloads the published binary |
| Nim distribution `bin/nimby` | Baked in by `nimby-nim-builds` |

## Nim distributions that must be rebuilt

Every published release in `treeform/nimby-nim-builds` carries a Nimby binary.
As of 2026-09-08 that is seven releases:

| Nim version | Release date |
| --- | --- |
| `2.2.12` | 2026-09-08 |
| `2.2.10` | 2026-05-24 |
| `2.2.8` | 2026-02-23 |
| `2.2.6` | 2026-01-31 |
| `2.2.4` | 2026-01-31 |
| `2.2.2` | 2026-01-31 |
| `2.0.16` | 2026-01-31 |

Regenerate this list before starting. Do not trust the table above:

```powershell
gh release list --repo treeform/nimby-nim-builds --limit 50
```

Rebuild in newest-first order: `2.2.12`, then `2.2.10`, `2.2.8`, `2.2.6`,
`2.2.4`, `2.2.2`, `2.0.16`. Newest first because `2.2.12` is what
`setup-nim-action` defaults to and what Nimby's own CI consumes, so a problem
there should stop the process before five more builds burn CI time.

If a rebuild of an old distribution fails only because new Nimby code will not
compile under that old Nim, that is a real decision point, not a step to skip
silently. Either fix Nimby to keep compiling under the declared floor, or drop
that Nim version from the supported set and say so in `nimby.nimble` and the
README. Write down which choice was made.

## Preflight

Before changing anything, confirm the current state.

1. Confirm the local repos are on `master` and up to date:

   ```powershell
   git -C C:/p/nimby status --short --branch
   git -C C:/p/nimby-nim-builds status --short --branch
   git -C C:/p/setup-nim-action status --short --branch
   ```

   Each repo should show `## master...origin/master` with no extra changed
   files.

2. Record the current published versions:

   ```powershell
   gh release list --repo treeform/nimby --limit 5
   gh release list --repo treeform/nimby-nim-builds --limit 50
   ```

3. Confirm `<nimby-version>` is not already taken:

   ```powershell
   gh release view <nimby-version> --repo treeform/nimby
   ```

   This should fail with "release not found". If it succeeds, pick a new
   version or understand why the release already exists.

4. Confirm Nimby `master` is the commit you intend to release. The latest tag
   is not necessarily the current `master`:

   ```powershell
   git -C C:/p/nimby rev-parse master
   git -C C:/p/nimby rev-parse <prev-nimby-version>
   git -C C:/p/nimby log --oneline <prev-nimby-version>..master
   ```

   Everything in that log is going into the release and into every rebuilt Nim
   distribution. Read it.

5. Find every hard-coded Nimby version before editing:

   ```powershell
   rg -n "<prev-nimby-version>|NIMBY_VERSION" C:/p/nimby C:/p/nimby-nim-builds C:/p/setup-nim-action
   ```

6. Confirm the workflows exist with the expected names:

   ```powershell
   gh workflow list --repo treeform/nimby --all
   gh workflow list --repo treeform/nimby-nim-builds --all
   gh workflow list --repo treeform/setup-nim-action --all
   ```

7. Announce the `master` freeze. From here until the last rebuild is verified,
   nothing lands on Nimby `master`. See the mechanism section for why.

## Monitor Every GitHub Action

Same pattern as the Nim process. For every workflow run this process starts:

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

When a push starts many workflows, monitor the exact commit instead of visually
scanning recent branch runs. Get the real SHA from git, never from memory:

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

Avoid complicated nested `--jq` strings in PowerShell when filtering by SHA. If
the filter is more than a one-liner, use `--json` and filter in PowerShell.

## Expected Durations and Alert Thresholds

Nimby-side timings came from the Nimby `0.1.27` run on 2026-05-24. The rebuild
phase timings are the Nim binary build timings from that same run, because a
rebuild is the same workflow doing the same work.

| Step | Typical time observed | Alert threshold |
| --- | ---: | ---: |
| Nimby master push workflows | about 2-3 min total | 15 min |
| Nimby `Nimby Release Binaries` tag workflow | about 2 min total | 15 min |
| Nimby post-release workflows | about 2-3 min total | 15 min |
| One Nim distribution rebuild (`Nim Binaries Distribution`) | about 14 min total | 35 min |
| Nim distribution published `Test` | about 1-2 min total | 10 min |
| `setup-nim-action` push matrix | under 1 min | 10 min |

Budget for the rebuild phase specifically. Six distributions at roughly 14
minutes each is about 90 minutes of wall clock if run one at a time. They can
be dispatched in parallel, but see the parallelism note in Phase 2 before
doing that.

Platform-specific notes:

- Nim distribution Windows builds are the slowest. 13-14 minutes is normal.
  Inspect logs past 25-30 minutes.
- Nim distribution Linux X64 and Linux ARM64 builds were around 8 minutes.
  Inspect either past 20 minutes.
- Nimby's own release binaries are much faster than the Nim compiler builds. A
  Nimby release build taking many minutes on any platform is unusual.
- Release upload jobs should finish in seconds once artifacts are built.

## Runbook Gotchas From 2026-09-08 (Nimby 0.2.2 and 0.2.3)

- 0.2.2 was released, baked into all seven distributions, and only then found
  to install into the current directory when `NIMBY_HOME` was unset. The fix
  was 0.2.3 and a second full rebuild pass. See the matching gotchas section
  in [`new_nim_process.md`](new_nim_process.md) for what was learned about
  which tests actually gate this.
- Before creating the release, read the `Installed Nim ... to:` line in the
  `Test install Nim` run for the release commit. It builds Nimby from
  `master`, so it shows where the *new* code installs things.
- All seven rebuilds were dispatched at once and finished in about 15
  minutes. Parallel is fine; keep the run IDs in a file.
- Phase 3's `setup-nim-action` re-test does not need `v6` to move unless
  `action.yml` changed. An empty commit on `master` is enough.

## Phase 1: Release the new Nimby

Repo: `C:/p/nimby`

GitHub: `treeform/nimby`

This phase is the same shape as Repo 3 in the Nim process, minus the Nim
version edits.

1. First commit, before the release exists. Edit:

   - `nimby.nimble` — bump `version` to `<nimby-version>`.
   - `src/nimby.nim` — update `writeVersion` to print `Nimby <nimby-version>`.

   Leave these on the old version for now:

   - `README.md` curl links — still `<prev-nimby-version>`.
   - `.github/workflows/test_from_nothing.yml` `NIMBY_VERSION` — still
     `<prev-nimby-version>`.

   Both of those download a published binary that does not exist yet. They move
   in Phase 3.

   Gate: `nimby.nimble` `version` and `writeVersion` must match. They are the
   two things that disagree most often, and a mismatch is only visible after
   the binaries are already published.

   ```powershell
   rg -n "^version" C:/p/nimby/nimby.nimble
   rg -n "Nimby <nimby-version>" C:/p/nimby/src/nimby.nim
   ```

2. Push and run the Nimby test suite.

   Required workflows:

   - `test.yml` (`Test`)
   - `test_install_nim.yml` (`Test install Nim`)
   - `test_install_nim_source.yml` (`Test install Nim form Source`, name typo is in the repo)
   - `test_from_nothing.yml` (`Test setup Nim from nothing.`)
   - `test_readme.yaml` (`Test README`)
   - `test_install_from_file.yml` (`Test Install From a .nimble File`)
   - `test_sync_lock_file.yml` (`Test Sync Lock File`)

   Gate: each required workflow must finish successfully.

   Note that at this point `test_from_nothing.yml` is still exercising
   `<prev-nimby-version>` against the *old* Nim distributions. That is
   expected and it is still a useful regression check — it proves the previous
   world still works before you change it.

3. Prove the new Nimby compiles under every Nim version you are about to
   rebuild. This is the gate that is unique to the Nimby process, and skipping
   it is how the rebuild phase fails halfway through with three distributions
   already updated and three not.

   The cheap version of this check is `nimby-nim-builds`'s
   `Test Release Build`, which clones Nimby `master` and builds it against a
   freshly built Nim, without publishing anything. Run it for the oldest Nim
   you support:

   ```powershell
   gh workflow run test_release.yml --repo treeform/nimby-nim-builds -f nim_version=2.0.16
   ```

   Gate: must finish successfully on Linux X64, Linux ARM64, macOS ARM64, and
   Windows X64. The `Print versions` step in that workflow prints both
   `nim --version` and `nimby --version` — read them. `nimby --version` must
   already print `<nimby-version>`, because it built from `master`.

   If this fails on the oldest Nim only, go back to the decision point in the
   "Nim distributions that must be rebuilt" section before continuing.

4. Create the Nimby release for `<nimby-version>`.

   The release workflow is `.github/workflows/release.yml` and the action name
   is `Nimby Release Binaries`. It has `workflow_dispatch`, but the upload job
   is gated on `startsWith(github.ref, 'refs/tags/') || github.event_name ==
   'release'`. A manual dispatch builds the binaries and uploads nothing. Use a
   pushed tag or a published GitHub release for the real release.

   **Historical note, fixed before 0.2.2:** the workflow used to trigger on both
   `release: types: [published]` and `push: tags: ["*"]`, so a single
   `gh release create` starts two runs that build the same artifacts and upload
   the same asset names concurrently. On the 0.2.0 release both finished
   successfully and the assets came out correct, but nothing makes that
   guaranteed: two jobs racing to replace the same asset is luck, not design.

   Gate: **every** triggered run must finish successfully, not just the first
   one you notice. List them explicitly rather than assuming there is one:

   ```powershell
   gh run list --repo treeform/nimby --workflow release.yml --limit 5
   ```

   If this repo is ever tidied up, dropping the `push: tags` trigger and
   keeping only `release: published` removes the race.

   Note that this workflow uses `treeform/setup-nim-action@v6`, which downloads
   a Nim distribution that still contains the *old* Nimby. That is fine and
   expected — that Nim is only being used as a compiler here.

5. Verify the release assets:

   ```powershell
   gh release view <nimby-version> --repo treeform/nimby --json tagName,name,publishedAt,assets
   ```

   Expected assets:

   - `nimby-Linux-X64`
   - `nimby-Linux-ARM64`
   - `nimby-macOS-ARM64`
   - `nimby-Windows-X64.exe`

   Each asset must be uploaded, have a non-zero size, and have the expected
   platform name.

6. Smoke test the published binary by hand before letting it into six Nim
   distributions:

   ```powershell
   curl -L -o C:/temp/nimby.exe https://github.com/treeform/nimby/releases/download/<nimby-version>/nimby-Windows-X64.exe
   C:/temp/nimby.exe --version
   ```

   Gate: it must print `Nimby <nimby-version>`.

## Phase 2: Rebuild every Nim binary distribution

Repo: `C:/p/nimby-nim-builds`

GitHub: `treeform/nimby-nim-builds`

**Phase 2 runs before Phase 3. Do not reorder them.** It is tempting to bump
the README links and `NIMBY_VERSION` right after the release is published,
since the assets now exist. Doing that moves `master` off the release tag, and
the gate immediately below this paragraph then fails — correctly, because the
rebuilds clone `master` unpinned and would bake an unreleased commit into the
distributions. Hold those edits, uncommitted, until Phase 2 is finished. This
was misordered once while running the 0.2.0 release and only the SHA gate
caught it.

This is the phase that has no equivalent in the Nim process. Nothing in this
repo needs editing. The work is dispatching `Nim Binaries Distribution` once
per published Nim version and verifying each result.

Before starting, re-confirm the freeze is holding, because the workflow will
clone whatever is on `master` right now.

**Ask GitHub, not your local clone.** The rebuild clones
`https://github.com/treeform/nimby.git`, so GitHub is the authority for both
sides of this comparison. Local refs can be stale, and the release tag may not
exist locally at all: `gh release create` creates the tag server-side, so
`git rev-parse <nimby-version>` fails with "unknown revision" on a clone that
has not fetched tags since. During the 0.2.1 release that check errored and
printed a bare `MISMATCH`, which read as "the freeze broke" when the freeze was
in fact fine. A gate whose failure mode is indistinguishable from the thing it
guards against is worse than no gate.

```powershell
$master = gh api repos/treeform/nimby/git/ref/heads/master --jq '.object.sha'
if ($LASTEXITCODE -ne 0) { throw "could not read master" }

# commits/<tag> resolves to a commit whether the tag is lightweight or
# annotated, and exits non-zero if the tag does not exist.
$tag = gh api repos/treeform/nimby/commits/<nimby-version> --jq '.sha'
if ($LASTEXITCODE -ne 0) { throw "could not resolve tag <nimby-version>" }

foreach ($pair in @(@("master", $master), @("tag", $tag))) {
  if ($pair[1] -notmatch '^[0-9a-f]{40}$') { throw "$($pair[0]) did not resolve to a SHA: $($pair[1])" }
}

"master : $master"
"tag    : $tag"
if ($master -ne $tag) { throw "FREEZE BROKEN: master has moved off the release tag." }
"freeze holding"
```

The `-notmatch` check matters: on failure `gh api --jq` still prints the error
JSON to stdout, so a bare capture would happily compare an error body as if it
were a SHA.

Gate: both SHAs must resolve and be identical. If `master` has moved past the
release tag, stop. Either revert the extra commits, or cut a new Nimby release
that includes them and restart Phase 2 from the new tag.

Expect these two to diverge legitimately once Phase 3 lands. The gate applies
only while Phase 2 is running.

For each `<nim-version>` in the rebuild list, newest first:

1. Record what the current distribution ships, so you can prove the rebuild
   changed something:

   ```powershell
   gh release view <nim-version> --repo treeform/nimby-nim-builds --json assets --jq '.assets[] | {name, size, updatedAt}'
   ```

2. Dispatch the rebuild:

   ```powershell
   gh workflow run release.yml --repo treeform/nimby-nim-builds -f nim_version=<nim-version>
   ```

   The `nim_version` input must not have a leading `v`. The workflow validates
   this and fails fast if you get it wrong. It clones upstream Nim with the
   `v` prefix added for you.

   Gate: the workflow must finish successfully on Linux X64, Linux ARM64,
   macOS ARM64, and Windows X64, and the `release` job must finish
   successfully.

3. Verify the assets were actually replaced. This is the check that catches a
   rebuild that silently did nothing:

   ```powershell
   gh release view <nim-version> --repo treeform/nimby-nim-builds --json tagName,publishedAt,assets --jq '{tag: .tagName, published: .publishedAt, assets: [.assets[] | {name, size, updatedAt}]}'
   ```

   Expected assets:

   - `nim-<nim-version>-Linux-X64.tar.gz`
   - `nim-<nim-version>-Linux-ARM64.tar.gz`
   - `nim-<nim-version>-macOS-ARM64.tar.gz`
   - `nim-<nim-version>-Windows-X64.zip`

   Gate: every asset's `updatedAt` must be from this rebuild, not from the
   original release. `publishedAt` will *not* change on a rebuild — the
   release already existed — so `publishedAt` is not evidence of anything.
   `updatedAt` on the assets is.

   Gate: the asset sizes should be in the same ballpark as the recorded
   values from step 1. A distribution that suddenly halves in size means a
   `cp -r` step silently failed.

4. Prove the rebuilt distribution actually carries the new Nimby:

   ```powershell
   gh workflow run test.yml --repo treeform/nimby-nim-builds -f nim_version=<nim-version>
   ```

   Gate: the workflow must finish successfully on all four platforms.

   Gate: read the `Print Nimby version` step output on each platform. It must
   print `Nimby <nimby-version>`. **This is the single most important check in
   the entire document.** A green `Test` run only proves the archive downloads
   and Nim compiles; it does not by itself prove the Nimby swap happened. Open
   the log and read the version:

   ```powershell
   gh run view <run-id> --repo treeform/nimby-nim-builds --log | rg "Nimby "
   ```

5. Only then move to the next `<nim-version>`.

Watch for:

- **Parallelism.** These are independent dispatches of the same workflow and
  GitHub will happily run several at once. Running them serially is slower but
  keeps the failure story simple: if something breaks you know exactly which
  version broke it and how many distributions were already updated. If you do
  dispatch in parallel, keep a written list of which versions are done,
  because `gh run list` for one workflow across six versions is hard to read.
- **Partial completion is a real state.** Halfway through this phase, some
  published Nim distributions ship `<nimby-version>` and some ship
  `<prev-nimby-version>`. There is nothing in the release metadata that says
  which. Keep the list. Finish the phase.
- **Same URL, new content.** Rebuilding replaces the assets behind download
  URLs that already exist and that people and CI already use. There are no
  published checksums today, so nothing breaks, but anyone who cached an
  archive by URL now has a stale copy. If checksums are ever added to this
  repo, this step has to publish new ones.
- The Windows job copies `dlls/*` from this repo into `Nim/bin/`. That is
  repo content, not build output, so it comes along on a rebuild unchanged.
- `test.yml` has two defaults that disagree today: the `workflow_dispatch`
  input default is `2.2.6` and the `NIM_VERSION` fallback is `2.2.4`. Always
  pass `-f nim_version=` explicitly rather than relying on either.
- Older action versions in this repo emit Node.js 20 deprecation warnings.
  They do not mean the rebuild failed. Record them and fix them in a separate
  maintenance pass.

## Phase 3: Point everything at the new Nimby

Back in `C:/p/nimby`. These edits were deliberately held back in Phase 1
because they reference release assets that did not exist yet.

1. Second commit on Nimby `master`:

   - `README.md` — update every
     `https://github.com/treeform/nimby/releases/download/<prev-nimby-version>/...`
     link to `<nimby-version>`. There are several, including one inside prose
     partway down the file, not just the Quick Start block. Verify with:

     ```powershell
     rg -n "releases/download/" C:/p/nimby/README.md
     ```

     Leave the `nimby use <nim-version>` examples alone. The Nim version is not
     changing in this process.

   - `.github/workflows/test_from_nothing.yml` — set `NIMBY_VERSION` to
     `<nimby-version>`. Leave `NIM_VERSION` alone.

2. Push and watch the full workflow set for that exact commit.

   Gate: `Test README` and `Test setup Nim from nothing.` must both pass. These
   two are the real gates here — they are the ones that download
   `<nimby-version>` from the release.

   `test_from_nothing.yml` is now an end-to-end proof of both halves of this
   process at once: it downloads the new Nimby binary, uses it to install the
   Nim distribution, and then runs `nimby install fidget2` from the copy in
   `$HOME/.nimby/nim/bin`.

3. Re-run the downstream consumer, `treeform/setup-nim-action`.

   No edits are needed in that repo for a Nimby-only release — its
   `nim-version` default does not change. But its `test.yml` matrix installs
   Nim `2.2.10` and `2.2.6` from the rebuilt distributions and runs
   `nimby -v` and `nimby install jsony`. That makes it a free
   end-to-end check that the rebuilds are good from a third repo's point of
   view.

   That workflow triggers on `push` and `pull_request` only, with no
   `workflow_dispatch`, so it cannot be started with `gh workflow run`. Start
   it by pushing an empty commit or a trivial README touch to `master`:

   ```powershell
   git -C C:/p/setup-nim-action commit --allow-empty -m "Re-test against rebuilt Nim distributions with Nimby <nimby-version>"
   git -C C:/p/setup-nim-action push origin master
   ```

   Gate: must pass on Linux X64, Linux ARM64, macOS ARM64, and Windows X64 for
   both matrix Nim versions, and `nimby -v` must print `<nimby-version>`.

   The `v6` tag does not need to move for a Nimby-only release, because nothing
   in `action.yml` changed. If you pushed a commit that does change
   `action.yml`, move the tag and verify it as described in the Nim process:

   ```powershell
   git -C C:/p/setup-nim-action ls-remote --tags origin v6
   ```

4. Lift the Nimby `master` freeze. Say so wherever you announced it.

## If a rebuild fails partway through

This is the failure mode worth planning for, because it leaves the published
set inconsistent.

1. Do not start more rebuilds. Write down which Nim versions completed step 4
   of Phase 2 and which did not.

2. Diagnose from the failed job:

   ```powershell
   gh run view <run-id> --repo treeform/nimby-nim-builds --log-failed
   ```

3. Decide which kind of failure it is:

   - **Infrastructure flake** (runner died, network timeout, artifact upload
     hiccup): re-dispatch the same `nim_version`. Nothing else to do. Confirm
     the freeze still holds first.

   - **New Nimby will not compile under that Nim**: this is the decision point
     from the top of the document. Either fix Nimby and cut
     `<nimby-version>`+1 — which means redoing Phase 1 and re-running *every*
     rebuild, including the ones that already succeeded, because they now
     carry a Nimby you are abandoning — or drop that Nim version from support
     and record it.

   - **Upstream Nim tag or toolchain problem** unrelated to Nimby: that
     distribution cannot be rebuilt right now. It keeps shipping
     `<prev-nimby-version>`. Record it explicitly in the final verification as
     a known gap rather than letting it look complete.

4. There is no rollback for a distribution that already rebuilt. Re-running
   `release.yml` always builds from Nimby `master`, so "go back to the old
   Nimby" means putting the old Nimby code back on `master` and rebuilding
   again. Prefer rolling forward.

## Final Verification

The whole process is complete only when all of these are true:

- `treeform/nimby` has release `<nimby-version>`.
- The Nimby release has all four expected platform assets, each non-zero.
- `nimby.nimble` `version` and `src/nimby.nim` `writeVersion` both say
  `<nimby-version>`.
- The downloaded `<nimby-version>` binary prints `Nimby <nimby-version>`.
- Every Nim version listed by
  `gh release list --repo treeform/nimby-nim-builds` has been rebuilt, with
  every asset's `updatedAt` from this rebuild pass — or is explicitly recorded
  as a known gap with a reason.
- For every rebuilt Nim version, the `Test` workflow passed **and** its
  `Print Nimby version` step printed `Nimby <nimby-version>`.
- Nimby README download links point to `<nimby-version>`.
- `test_from_nothing.yml` `NIMBY_VERSION` is `<nimby-version>` and that
  workflow is green.
- `Test README` is green.
- `treeform/setup-nim-action` CI is green against the rebuilt distributions
  and printed `<nimby-version>` from `nimby -v`.
- The Nimby `master` freeze has been lifted and `origin/master` still matches
  the `<nimby-version>` tag, or has only moved by commits landed after the
  freeze was lifted.

Record the run URLs for the Nimby release workflow and for each of the six
rebuild workflows. Next time, the fastest way to answer "which Nimby is in the
`2.2.4` distribution" is that list.
