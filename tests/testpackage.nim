import std/[os, osproc, sequtils, strutils, strformat]

let testPackagesDir* = getTempDir() / "nimby_tests" / "packages"

proc createTestPackage*(
  name: string,
  branch: string = "main",
  requires: openArray[string] = []
) =
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

  let commands = [
    "git init",
    &"git checkout -b {branch}",
    "git add -A",
    &"git commit -m \"Initial commit for {name}\"",
  ]

  for command in commands:
    let (output, exitCode) = execCmdEx(command, workingDir = packageDir)
    if exitCode != 0:
      raise newException(Exception, &"Failed to initialize test package '{name}':\n{command}\n{output}")

proc addSubmodule*(repository: string, url: string) =
  let commands = [
    &"git -c protocol.file.allow=always submodule add {url}",
    "git commit -m \"Add submodule\"",
  ]

  for command in commands:
    let (output, exitCode) = execCmdEx(command, workingDir = repository)
    if exitCode != 0:
      raise newException(Exception, &"Failed to add submodule to '{repository}':\n{command}\n{output}")
