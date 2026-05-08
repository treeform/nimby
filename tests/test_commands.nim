import std/[os, osproc, strutils, sequtils, tables, strformat, unittest]
import testpackage

let testWorkspace* = getTempDir() / "nimby_tests"

proc cmd*(command: string): string {.discardable.} =
  ## Runs a shell command in the test workspace, echoes output and returns it.
  echo "  > ", command
  let (output, exitCode) = execCmdEx(command, workingDir = testWorkspace)
  result = output
  echo output.indent(4)

  if exitCode != 0:
    raise newException(Exception, &"Command failed: {exitCode}")

  return output

proc branch(repo: string): string =
  cmd(&"git -C {repo} rev-parse --abbrev-ref HEAD").strip

proc clean() =
  ## Resets the test workspace and global nimby directories.
  removeDir(expandTilde("~/.nimby/nimbylock"))
  removeDir(expandTilde("~/.nimby/pkgs"))
  removeDir(testWorkspace)
  createDir(testWorkspace)
  setCurrentDir(testWorkspace)

suite "`nimby install` should":
  setup:
    setupTestPackages()
    clean()

  test "create the package locally":
    cmd("nimby install -V mummy")
    check dirExists("mummy")
    cmd("nimby remove mummy")

  test "create the package globally when used with `-g`":
    cmd("nimby install -g -V mummy")
    check not dirExists("mummy")
    check dirExists(expandTilde("~/.nimby/pkgs/mummy"))

  test "work on file:// urls":
    createTestPackage("package")
    cmd(&"nimby install file://{testPackagesDir}/package")
    check dirExists("package")

  test "work on https:// urls":
    cmd("nimby install https://github.com/treeform/nimbytestpackage.git")
    check dirExists("nimbytestpackage")

  test "work on ssh:// urls":
    cmd("nimby install ssh://git@github.com/treeform/nimbytestpackage.git")
    check dirExists("nimbytestpackage")

  test "work on git+ssh:// urls":
    cmd("nimby install git+ssh://git@github.com/treeform/nimbytestpackage.git")
    check dirExists("nimbytestpackage")

  test "work on git@ urls":
    cmd("nimby install git@github.com:treeform/nimbytestpackage.git")
    check dirExists("nimbytestpackage")

  test "work on branches":
    createTestPackage("package", "branch")
    cmd(&"nimby install file://{testPackagesDir}/package#branch")
    check dirExists("package")
    check branch("package") == "branch"

  test "ignore #head fragments":
    createTestPackage("package")
    cmd(&"nimby install file://{testPackagesDir}/package#head")
    check dirExists("package")

  test "resolve required packages not present in nimble":
    createTestPackage("required")
    createTestPackage("requirer", requires = [
      &"file://{testPackagesDir}/required"
    ])
    cmd(&"nimby install file://{testPackagesDir}/requirer")
    check dirExists("requirer")
    check dirExists("required")

  test "resolve required packages with a branch fragment":
    createTestPackage("required", "feature")
    createTestPackage("requirer", requires = [
      &"file://{testPackagesDir}/required#feature"
    ])
    cmd(&"nimby install file://{testPackagesDir}/requirer")
    check dirExists("requirer")
    check dirExists("required")
    check branch("required") == "feature"

  test "resolve required packages with a head fragment ignoring it":
    createTestPackage("required")
    createTestPackage("requirer", requires = [
      &"file://{testPackagesDir}/required#head"
    ])
    cmd(&"nimby install file://{testPackagesDir}/requirer")
    check dirExists("requirer")
    check dirExists("required")
    check branch("required") == "main"

  test "clone packages with their submodules":
    createTestPackage("package")
    addSubmodule(testPackagesDir / "package", "git@github.com:treeform/nimbytestpackage.git")
    cmd(&"nimby install file://{testPackagesDir}/package")
    check dirExists("package")
    check dirExists("package" / "nimbytestpackage")

suite "`nimby lock` should":
  setup:
    setupTestPackages()
    clean()

  test "include dependencies in the package with their corresponding URLs":
    cmd("nimby install https://github.com/RowDaBoat/nimbytestpackage.git")
    cmd("nimby lock nimbytestpackage > nimbytestpackage.lock")
    check fileExists("nimbytestpackage.lock")
    let
      lockOut = readFile("nimbytestpackage.lock")
      lockLines = lockOut.split('\n').filterIt(it.len > 0).toSeq[1..^1].mapIt(it.split(' '))
      expected = @[
        ("bitty", "https://github.com/treeform/bitty"),
        ("boxy", "https://github.com/treeform/boxy"),
        ("bumpy", "https://github.com/treeform/bumpy"),
        ("chroma", "https://github.com/treeform/chroma"),
      ].toTable
      actual = lockLines.mapIt((it[0], it[2])).toTable

    for name, url in expected:
      check actual.getOrDefault(name) == url

    check not actual.contains("nimbytestpackage")

suite "`nimby update` should":
  setup:
    setupTestPackages()
    clean()
  proc getCommit(repo: string): string =
    ## Returns the current HEAD commit hash for the given repo.
    cmd(&"git -C {repo} rev-parse HEAD").strip

  proc rewindPackage(repo: string, commit: string, branch: string = "main"): string =
    ## Rewinds a package repo to a prior commit and returns the original HEAD.
    let present = getCommit(repo)
    cmd(&"git -C {repo} fetch --deepen 1")
    cmd(&"git -C {repo} checkout {commit}")
    cmd(&"git -C {repo} branch -f {branch}")
    cmd(&"git -C {repo} branch -u origin/{branch} {branch}")
    cmd(&"git -C {repo} checkout {branch}")
    let past = getCommit(repo)
    check present != past
    return present

  test "update local packages":
    cmd("nimby install https://github.com/RowDaBoat/nimbytestpackage.git")
    let present = rewindPackage("nimbytestpackage", "HEAD^")

    cmd("nimby update nimbytestpackage")

    let actual = getCommit("nimbytestpackage")
    check present == actual

  test "update global packages with -g":
    cmd("nimby install -g https://github.com/RowDaBoat/nimbytestpackage.git")
    let
      repoPath = "~/.nimby/pkgs/nimbytestpackage"
      present = rewindPackage(repoPath, "HEAD^")

    cmd("nimby update nimbytestpackage")

    let actual = getCommit(repoPath)
    check present == actual

  test "update local and global packages with --all":
    cmd("nimby install -g https://github.com/treeform/bitty.git")
    cmd("nimby install https://github.com/RowDaBoat/nimbytestpackage.git")
    let
      bittyPath = "~/.nimby/pkgs/bitty"
      ntpPath = "nimbytestpackage"
      bittyPresent = rewindPackage(bittyPath, "HEAD^", "master")
      ntpPresent = rewindPackage(ntpPath, "HEAD^")

    cmd("nimby update --all -y")

    let
      bittyActual = getCommit(bittyPath)
      ntpActual = getCommit(ntpPath)

    check bittyPresent == bittyActual
    check ntpPresent == ntpActual
