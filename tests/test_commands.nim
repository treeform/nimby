import os, strutils, sequtils, tables, strformat
import testsharness

# cmd("nimby --help")
# cmd("nimby -h")
# cmd("nimby --version")
# cmd("nimby -v")
# cmd("nimby --help")
# cmd("nimby -h")
# cmd("nimby --version")
# cmd("nimby -v")

proc clean() =
  removeDir(expandTilde("~/.nimby/nimbylock"))
  removeDir(expandTilde("~/.nimby/pkgs"))
  removeDir(testWorkspace)
  createDir(testWorkspace)
  setCurrentDir(testWorkspace)

suite "`nimby install` should":
  setup: clean()

  test "create the package locally":
    cmd("nimby install -V mummy")
    doAssert dirExists("mummy")
    cmd("nimby remove mummy")

  test "create the package globally when used with `-g`":
    cmd("nimby install -g -V mummy")
    doAssert not dirExists("mummy")
    doAssert dirExists(expandTilde("~/.nimby/pkgs/mummy"))

suite "`nimby lock` should":
  setup: clean()

  test "include dependencies in the package with their corresponding URLs":
    cmd("nimby install git@github.com:RowDaBoat/nimbytestpackage.git")
    cmd("nimby lock nimbytestpackage > nimbytestpackage.lock")
    doAssert fileExists("nimbytestpackage.lock")
    let lockOut = readFile("nimbytestpackage.lock")
    let lockLines = lockOut.split('\n').filterIt(it.len > 0).toSeq[1..^1].mapIt(it.split(' '))

    let expected = @[
      ("bitty", "https://github.com/treeform/bitty"),
      ("boxy", "https://github.com/treeform/boxy"),
      ("bumpy", "https://github.com/treeform/bumpy"),
      ("chroma", "https://github.com/treeform/chroma"),
    ].toTable
    let actual = lockLines.mapIt((it[0], it[2])).toTable

    for name, url in expected:
      doAssert actual.getOrDefault(name) == url

    doAssert not actual.contains("nimbytestpackage")

suite "`nimby update` should":
  setup: clean()
  proc getCommit(repo: string): string =
    cmd(&"git -C {repo} rev-parse HEAD").strip

  proc rewindPackage(repo: string, commit: string, branch: string = "main"): string =
    let present = getCommit(repo)
    cmd(&"git -C {repo} fetch --deepen 1")
    cmd(&"git -C {repo} checkout {commit}")
    cmd(&"git -C {repo} branch -f {branch}")
    cmd(&"git -C {repo} branch -u origin/{branch} {branch}")
    cmd(&"git -C {repo} checkout {branch}")
    let past = getCommit(repo)
    doAssert present != past
    present

  proc expect[T](expected: T, actual: T): string =
    &"\nexpected: {expected}\nactual:   {actual}"

  test "update local packages":
    cmd("nimby install git@github.com:RowDaBoat/nimbytestpackage.git")
    let present = rewindPackage("nimbytestpackage", "HEAD^")

    cmd("nimby update nimbytestpackage")

    let actual = getCommit("nimbytestpackage")
    doAssert present == actual, expect(present, actual)

  test "update global packages with -g":
    cmd("nimby install -g git@github.com:RowDaBoat/nimbytestpackage.git")
    let repoPath = "~/.nimby/pkgs/nimbytestpackage"
    let present = rewindPackage(repoPath, "HEAD^")

    cmd("nimby update nimbytestpackage")

    let actual = getCommit(repoPath)
    doAssert present == actual, expect(present, actual)

  test "update local and global packages with --all":
    cmd("nimby install -g git@github.com:treeform/bitty.git")
    cmd("nimby install git@github.com:RowDaBoat/nimbytestpackage.git")
    let bittyPath = "~/.nimby/pkgs/bitty"
    let ntpPath = "nimbytestpackage"
    let bittyPresent = rewindPackage(bittyPath, "HEAD^", "master")
    let ntpPresent = rewindPackage(ntpPath, "HEAD^")

    cmd("nimby update --all -y")

    let bittyActual = getCommit(bittyPath)
    let ntpActual = getCommit(ntpPath)

    doAssert bittyPresent == bittyActual, expect(bittyPresent, bittyActual)
    doAssert ntpPresent == ntpActual, expect(ntpPresent, ntpActual)
