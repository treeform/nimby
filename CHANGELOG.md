# Changelog

## 0.2.2

### Added

#### `NIMBY_HOME` picks where Nimby lives

Nimby's home directory (where `nimby use` installs Nim and where global
packages go) used to be hard-coded to `~/.nimby`. It can now be set with the
`NIMBY_HOME` environment variable. The value is tilde-expanded and turned into
an absolute path, and paths with spaces work. The build commands honor it too.

Contributed by RowDaBoat.

#### `nimby doctor` checks a lot more

`nimby doctor` now reports missing dependencies, `nim.cfg` linking and
format problems, packages that are listed but not on disk, and orphan
directories that are on disk but not linked. Every finding comes with a
suggested fix.

Contributed by RowDaBoat.

#### `nimby r`

The `r` command that was documented but missing is back.

### Changed

#### Nim 2.2.12 is the default

The README examples, the CI workflows, and the test suite now target Nim
2.2.12. Binary distributions are published at
https://github.com/treeform/nimby-nim-builds/releases/tag/2.2.12.

### Fixed

- The compiler subcommands (`nimby c`, `nimby r`, and friends) now fail with a
  clear error when Nimby has no Nim set up instead of failing later inside
  the compiler. This check works on Windows too.
- The test suite sets up its own Nim with `nimby use` inside an isolated
  `NIMBY_HOME`, so running the tests no longer touches your real `~/.nimby`
  or the local workspace.

## 0.2.1

### Fixed

#### `nimby install -g` produced packages nim could not find

0.2.0 stopped `-g` writing any `nim.cfg`, which left globally installed
packages on disk but invisible to the compiler. The install reported success
and the build then failed with `cannot open file: <dep>`.

`-g` decides where package files are stored, and nothing else. The `--path:`
entries still have to be written somewhere, and the only candidates are the
workspace or the package's own folder. Writing into the package folder is what
0.2.0 set out to stop, so a workspace is required for `-g` exactly as it is
for a normal install.

Inside a Git checkout or Nimble package with no workspace, `nimby install -g`
now refuses with the same message a normal install gives, instead of silently
producing an unusable install.

This reverses the 0.2.0 note below about `-g` leaving your local `nim.cfg`
alone. `-g` does write to the workspace `nim.cfg`; what it will not do is
create one inside a package.

## 0.2.0

First release since 0.1.27 (2026-05-24). Workspaces changed enough to justify
the minor bump.

### Breaking

#### Workspaces are explicit

Nimby used to create a `nim.cfg` workspace wherever you happened to be
standing. It no longer does that inside a Git checkout or a Nimble package. It
stops and makes you choose:

```
No Nimby workspace found.
Refusing to create one inside package or Git checkout: /home/me/myproject
Run `nimby create` in the directory you want as the workspace.
```

Run `nimby create` in the directory you want as the workspace root. Nimby walks
up from wherever you are to find it, so you can still work from any
subdirectory.

The marker line in `nim.cfg` is now `# Managed by Nimby`. Workspaces marked
`# Created by Nimby` are still recognized, so there is nothing to migrate.

**Migrating CI.** If your workflow checks out a repository and then runs
`nimby install` in the checkout root, it will now fail. That pattern was
quietly wrong before: Nimby installs packages as siblings of the workspace
root, so it was writing package directories into your repository. Create the
workspace outside the checkout instead:

```yaml
- uses: actions/checkout@v5
- uses: treeform/setup-nim-action@v6

- name: Install dependencies
  shell: bash
  run: |
    cd ..
    nimby create
    nimby install mypackage
```

The workspace has to be the *parent* of your checkout, so that your repository
sits inside it alongside its dependencies and nim finds the `nim.cfg` by
walking up. A workspace somewhere else, such as under `RUNNER_TEMP`, will
install the packages but your own build will not see them.

Locally the same rule applies: run `nimby create` in the directory you want as
the workspace root, with your project as one of its children.

#### `-g` no longer touches your local `nim.cfg`

Global installs could previously create or modify a `nim.cfg` in the current
directory, including inside a Git checkout. They now leave the local workspace
alone.

Superseded in 0.2.1: this went too far and made globally installed packages
invisible to nim. `-g` writes to the workspace `nim.cfg` again; it just refuses
to create one inside a package.

### Added

#### `nimby create`

Creates a workspace in the current directory. Idempotent, and prepends the
marker to an existing `nim.cfg` rather than overwriting it.

#### Compiler subcommands: `c`, `cpp`, `js`, `e`, `doc`, `check`

Each verifies `nimby.lock` before handing off to nim. Every locked dependency
must be present, free of uncommitted changes, and sitting on the locked commit:

```
Dependency `vmath` not found in workspace.
Dependency `pixie` has uncommitted changes.
Dependency `chroma` is not at the locked commit.
```

Extra arguments forward straight through, so `nimby c -d:release src/app.nim`
does what you expect. A verified reproducible build is now one command instead
of a lock check plus a compile.

#### Install several packages at once

`nimby install a b c` and `nimby install a,b,c` both work.

### Fixed

#### Intermittent `Can't add package's tree to config`

A package required by URL in one `.nimble` and by bare name in another was
queued twice under two different keys, so two workers cloned into the same
directory. When the second arrived mid-clone it found the directory present but
the `.nimble` file not yet checked out, and Nimby exited 1. Jobs are now
identified by package name, so this cannot happen. In practice it also means
packages like `bitty` and `bumpy` are no longer installed twice on every run.

#### Interrupted installs no longer poison a workspace

Clones are staged in a temporary directory and moved into place only once
complete. Killing an install mid-clone used to leave a half-populated directory
that made every later install in that workspace fail until it was deleted by
hand.

#### URLs containing `~`, `=`, `<`, `>` or `^`

`requires "file://C:\Users\RUNNER~1\...\pkgs/dep"` parsed as the name
`file://C:\Users\RUNNER` with version operator `~`. Version operator characters
inside a URL spec are now part of the URL. Bare names like `bitty ~= 0.1.4`
parse as before.

### Internal

- The functional suite runs on Linux X64, Linux ARM64, macOS ARM64 and Windows
  X64. It was Linux-only, and four Windows-specific test harness bugs were
  hiding behind that.
- `name` and `spec` are used consistently throughout: a spec is a requirement as
  written (url, url#branch, lock line, `.nimble` path, bare name), a name is the
  normalized package name and the directory it installs into.
- Added `docs/new_nimby_process.md`, the release runbook this release follows.
