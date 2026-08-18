import std/[os, osproc, sequtils, strutils, strformat]

const GitCommit* =
  "git -c user.name=Tests -c user.email=git@tests.com commit"

let testPackagesDir* = getTempDir() / "nimby_tests" / "packages"

proc setupTestPackages*() =
  ## Rewrites SSH URLs for Git child processes on CI.
  if not existsEnv("CI"):
    return

  putEnv("GIT_CONFIG_COUNT", "3")
  for i, url in [
    "ssh://git@github.com/",
    "git+ssh://git@github.com/",
    "git@github.com:"
  ]:
    putEnv(
      &"GIT_CONFIG_KEY_{i}",
      "url.https://github.com/.insteadOf"
    )
    putEnv(&"GIT_CONFIG_VALUE_{i}", url)

proc createTestPackage*(
  name: string,
  branch: string = "main",
  commits: int = 1,
  requires: openArray[string] = []
) =
  ## Creates a git-initialized Nimble package in the temp directory with the
  ## given name, number of commits, branch, and dependencies.
  let packageDir = testPackagesDir / name
  createDir(packageDir)

  let requireLines = if requires.len > 0:
    requires.mapIt(&"requires \"{it}\"").join("\n") & "\n"
  else:
    ""

  let nimbleContent = &"""
# Package
version       = "0.1.0"
author        = "Test"
description   = "Test package {name}"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"
{requireLines}"""

  writeFile(packageDir / (name & ".nimble"), nimbleContent)

  let srcDir = packageDir / "src"
  createDir(srcDir)
  writeFile(srcDir / (name & ".nim"), &"## {name}\n")

  var commands = @[
    "git init",
    &"git checkout -b {branch}",
    "git add -A",
    &"{GitCommit} -m \"Initial commit for {name}\"",
  ]

  for i in [1 ..< commits]:
    commands.add &"{GitCommit} --allow-empty -m 'Commit {i}'"

  for command in commands:
    let (output, exitCode) = execCmdEx(command, workingDir = packageDir)
    if exitCode != 0:
      raise newException(Exception, &"Failed to initialize test package '{name}':\n{command}\n{output}")

proc addSubmodule*(repository: string, url: string) =
  ## Adds a git submodule at the given URL to the repository and commits it.
  let commands = [
    &"git -c protocol.file.allow=always submodule add {url}",
    &"{GitCommit} -m \"Add submodule\"",
  ]

  for command in commands:
    let (output, exitCode) = execCmdEx(command, workingDir = repository)
    if exitCode != 0:
      raise newException(Exception, &"Failed to add submodule to '{repository}':\n{command}\n{output}")

proc getCommit*(repo: string): string =
  ## Returns the current HEAD commit hash for the given repo.
  let (output, exitCode) = execCmdEx(&"git -C {repo} rev-parse HEAD")
  if exitCode != 0:
    raise newException(Exception, &"Failed to get commit for '{repo}':\n{output}")
  result = output.strip

proc rewindPackage*(repo: string, commit: string, branch: string = "main"): string =
  ## Rewinds a package repo to a prior commit and returns the original HEAD.
  let present = getCommit(repo)

  let commands = [
    &"git -C {repo} fetch --deepen 1",
    &"git -C {repo} checkout {commit}",
    &"git -C {repo} branch -f {branch}",
    &"git -C {repo} branch -u origin/{branch} {branch}",
    &"git -C {repo} checkout {branch}",
  ]

  for command in commands:
    let (output, exitCode) = execCmdEx(command)
    if exitCode != 0:
      raise newException(Exception, &"Failed to rewind package '{repo}':\n{command}\n{output}")

  let past = getCommit(repo)
  assert present != past, &"rewindPackage: HEAD did not change for '{repo}'"
  return present
