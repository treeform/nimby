import std/[os, osproc, strutils, sequtils, tables, strformat, unittest]
import testpackage

let testWorkspace* = getTempDir() / "nimby_tests"
let nimbyHome* = getTempDir() / "nimby_home"

proc cmdAt*(workingDir, command: string): string {.discardable.} =
  ## Runs a shell command in a test directory, echoes output and returns it.
  echo "  > ", command
  let (output, exitCode) = execCmdEx(command, workingDir = workingDir)
  result = output
  echo output.indent(4)

  if exitCode != 0:
    raise newException(Exception, &"Command failed: {exitCode}")

  return output

proc cmd*(command: string): string {.discardable.} =
  ## Runs a shell command in the test workspace, echoes output and returns it.
  cmdAt(testWorkspace, command)

proc cmdFailAt*(workingDir, command: string): string {.discardable.} =
  ## Runs a shell command that is expected to fail.
  echo "  > ", command
  let (output, exitCode) = execCmdEx(command, workingDir = workingDir)
  result = output
  echo output.indent(4)
  check exitCode != 0

proc cmdFail*(command: string): string {.discardable.} =
  ## Runs a shell command in the test workspace that is expected to fail.
  cmdFailAt(testWorkspace, command)

proc branch(repo: string): string =
  cmd(&"git -C {repo} rev-parse --abbrev-ref HEAD").strip

proc setupEnvironment(installNim: bool = true) =
  setCurrentDir(getTempDir())
  removeDir(nimbyHome / "nimbylock")
  removeDir(nimbyHome / "pkgs")
  putEnv("NIMBY_HOME", nimbyHome)
  if installNim:
    cmd("nimby use 2.2.10")
  removeDir(testWorkspace)
  createDir(testWorkspace)
  setCurrentDir(testWorkspace)

suite "`nimby use` should":
  setup:
    setupTestPackages()
    setupEnvironment(installNim = false)

  test "install nim into NIMBY_HOME":
    cmd("nimby use 2.2.10")
    check fileExists(nimbyHome / "nim" / "bin" / addFileExt("nim", ExeExt))

  test "fail when nim is not installed":
    removeDir(nimbyHome / "nim")
    cmd("nimby create")
    createTestPackage("myapp")
    cmd(&"nimby install file://{testPackagesDir}/myapp")
    writeFile(testWorkspace / "myapp" / "nimby.lock", "")
    let output = cmdFailAt(testWorkspace / "myapp", "nimby c src/myapp.nim")
    check output.contains("Nim is not installed")
    check output.contains("nimby use")

suite "`nimby create` should":
  setup:
    setupTestPackages()
    setupEnvironment()

  test "create a workspace in the current directory":
    cmd("nimby create")
    check fileExists("nim.cfg")
    check readFile("nim.cfg").contains("# Managed by Nimby")

  test "create nested workspaces explicitly":
    cmd("nimby create")
    let nested = testWorkspace / "nested"
    createDir(nested)

    cmdAt(nested, "nimby create")

    check fileExists(testWorkspace / "nim.cfg")
    check fileExists(nested / "nim.cfg")

  test "succeed when run twice without duplicating the marker":
    cmd("nimby create")
    cmd("nimby create")
    let content = readFile(testWorkspace / "nim.cfg")
    check content.count("# Managed by Nimby") == 1

  test "succeed explicitly inside a Git checkout":
    let repo = testWorkspace / "repo"
    createDir(repo)
    createDir(repo / ".git")

    cmdAt(repo, "nimby create")

    check fileExists(repo / "nim.cfg")
    check readFile(repo / "nim.cfg").contains("# Managed by Nimby")

  test "succeed explicitly inside a Nimble package":
    let package = testWorkspace / "package"
    createDir(package)
    writeFile(package / "package.nimble", "version = \"0.1.0\"\n")

    cmdAt(package, "nimby create")

    check fileExists(package / "nim.cfg")
    check readFile(package / "nim.cfg").contains("# Managed by Nimby")

  test "install into a nested workspace instead of parent":
    cmd("nimby create")
    let nested = testWorkspace / "nested"
    createDir(nested)
    cmdAt(nested, "nimby create")

    createTestPackage("dependency")
    cmdAt(nested, &"nimby install file://{testPackagesDir}/dependency")

    check dirExists(nested / "dependency")
    check not dirExists(testWorkspace / "dependency")
    check readFile(nested / "nim.cfg").contains("dependency")

suite "`nimby install` should":
  setup:
    setupTestPackages()
    setupEnvironment()

  test "require a package argument":
    let output = cmdFail("nimby install")
    check output.contains("No package specified for install.")
    check not fileExists("nim.cfg")

  test "refuse to install the current directory":
    let output = cmdFail("nimby install .")
    check output.contains("Refusing to install the current directory.")
    check not fileExists("nim.cfg")

  test "create the package locally":
    cmd("nimby install -V mummy")
    check dirExists("mummy")
    cmd("nimby remove mummy")

  test "install multiple packages from one command line":
    createTestPackage("package")
    createTestPackage("dependency")
    cmd(&"nimby install file://{testPackagesDir}/package, file://{testPackagesDir}/dependency")
    check dirExists("package")
    check dirExists("dependency")

  test "create the package globally when used with `-g`":
    cmd("nimby install -g -V mummy")
    check not dirExists("mummy")
    check dirExists(nimbyHome / "pkgs" / "mummy")

  test "install globally when NIMBY_HOME has spaces":
    let spacedHome = getTempDir() / "nimby home with spaces"
    removeDir(spacedHome)
    putEnv("NIMBY_HOME", spacedHome)
    cmd("nimby use 2.2.10")
    cmd("nimby install -g -V mummy")
    check dirExists(spacedHome / "pkgs" / "mummy")
    removeDir(spacedHome)
    putEnv("NIMBY_HOME", nimbyHome)

  test "record the global package in the workspace nim.cfg":
    cmd("nimby install -g mummy")
    let nimCfg = readFile(testWorkspace / "nim.cfg")
    check nimCfg.contains("--path:")
    check nimCfg.contains("mummy")

  test "refuse to install globally without a workspace inside a Git checkout":
    let repo = testWorkspace / "repo"
    createDir(repo)
    createDir(repo / ".git")

    let output = cmdFailAt(repo, "nimby install -g mummy")

    check output.contains("No Nimby workspace found")
    check output.contains("Refusing to create one inside package or Git checkout")
    check not fileExists(repo / "nim.cfg")

  test "work on file:// urls":
    createTestPackage("package")
    cmd(&"nimby install file://{testPackagesDir}/package")
    check dirExists("package")
    check readFile("nim.cfg").contains("# Managed by Nimby")

  test "use a parent workspace from nested directories":
    cmd("nimby create")
    createTestPackage("dependency")
    let nested = testWorkspace / "nested"
    createDir(nested)

    cmdAt(nested, &"nimby install file://{testPackagesDir}/dependency")

    check dirExists(testWorkspace / "dependency")
    check not fileExists(nested / "nim.cfg")

  test "refuse to auto-create inside Git checkouts":
    createTestPackage("dependency")
    let repo = testWorkspace / "repo"
    createDir(repo)
    createDir(repo / ".git")

    let output = cmdFailAt(repo, &"nimby install file://{testPackagesDir}/dependency")

    check output.contains("No Nimby workspace found")
    check output.contains("Refusing to create one inside package or Git checkout")
    check not fileExists(repo / "nim.cfg")

  test "refuse to auto-create inside a subdirectory of a Git checkout":
    createTestPackage("dependency")
    let repo = testWorkspace / "repo"
    createDir(repo)
    createDir(repo / ".git")
    let subdir = repo / "src"
    createDir(subdir)

    let output = cmdFailAt(subdir, &"nimby install file://{testPackagesDir}/dependency")

    check output.contains("No Nimby workspace found")
    check output.contains("Refusing to create one inside package or Git checkout")
    check not fileExists(subdir / "nim.cfg")
    check not fileExists(repo / "nim.cfg")

  test "refuse to auto-create inside Nimble packages":
    createTestPackage("dependency")
    let package = testWorkspace / "package"
    createDir(package)
    writeFile(package / "package.nimble", "version = \"0.1.0\"\n")

    let output = cmdFailAt(package, &"nimby install file://{testPackagesDir}/dependency")

    check output.contains("No Nimby workspace found")
    check output.contains("Refusing to create one inside package or Git checkout")
    check not fileExists(package / "nim.cfg")

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
    setupEnvironment()

  test "include dependencies in the package with their corresponding URLs":
    cmd("nimby install https://github.com/RowDaBoat/nimbytestpackage.git")
    writeFile("nimbytestpackage.lock", cmd("nimby lock nimbytestpackage"))
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


suite "`nimby c` should":
  setup:
    setupTestPackages()
    setupEnvironment()

  test "fail when no lock file is present":
    cmd("nimby create")
    createTestPackage("myapp")
    cmd(&"nimby install file://{testPackagesDir}/myapp")
    let output = cmdFailAt(testWorkspace / "myapp", "nimby c src/myapp.nim")
    check output.contains("nimby.lock")

  test "fail when a dependency directory is missing":
    cmd("nimby create")
    createTestPackage("dep")
    createTestPackage("myapp", requires = [&"file://{testPackagesDir}/dep"])
    cmd(&"nimby install file://{testPackagesDir}/myapp")
    writeFile(testWorkspace / "myapp" / "nimby.lock", cmd("nimby lock myapp"))

    removeDir(testWorkspace / "dep")

    let output = cmdFailAt(testWorkspace / "myapp", "nimby c src/myapp.nim")
    check output.contains("dep")
    check output.contains("not found")

  test "fail when a dependency is not at the locked commit":
    cmd("nimby create")
    createTestPackage("dep")
    createTestPackage("myapp", requires = [&"file://{testPackagesDir}/dep"])
    cmd(&"nimby install file://{testPackagesDir}/myapp")
    writeFile(testWorkspace / "myapp" / "nimby.lock", cmd("nimby lock myapp"))

    let (_, _) = execCmdEx(
      GitCommit & " --allow-empty -m \"advance\"",
      workingDir = testWorkspace / "dep"
    )

    let output = cmdFailAt(testWorkspace / "myapp", "nimby c src/myapp.nim")
    check output.contains("dep")

  test "fail when a dependency has uncommitted changes":
    cmd("nimby create")
    createTestPackage("dep")
    createTestPackage("myapp", requires = [&"file://{testPackagesDir}/dep"])
    cmd(&"nimby install file://{testPackagesDir}/myapp")
    writeFile(testWorkspace / "myapp" / "nimby.lock", cmd("nimby lock myapp"))

    writeFile(testWorkspace / "dep" / "dirty.txt", "uncommitted")

    let output = cmdFailAt(testWorkspace / "myapp", "nimby c src/myapp.nim")
    check output.contains("dep")

  test "fail when the compilation has an error":
    cmd("nimby create")
    createTestPackage("myapp")
    writeFile(testPackagesDir / "myapp" / "src" / "myapp.nim", "this is not valid nim\n")
    # Not chained with `&&`: execCmdEx bypasses the shell on Windows.
    let packageDir = testPackagesDir / "myapp"
    discard execCmdEx("git add -A", workingDir = packageDir)
    discard execCmdEx(GitCommit & " -m \"broken source\"", workingDir = packageDir)

    cmd(&"nimby install file://{testPackagesDir}/myapp")
    writeFile(testWorkspace / "myapp" / "nimby.lock", "")

    let output = cmdFailAt(testWorkspace / "myapp", "nimby c src/myapp.nim")
    check output.contains("error")

  test "compile successfully with an empty lock file":
    cmd("nimby create")
    createTestPackage("myapp")
    cmd(&"nimby install file://{testPackagesDir}/myapp")
    writeFile(testWorkspace / "myapp" / "nimby.lock", "")

    cmdAt(testWorkspace / "myapp", "nimby c src/myapp.nim")

  test "compile with verified dependencies":
    cmd("nimby create")
    createTestPackage("dep")
    createTestPackage("myapp", requires = [&"file://{testPackagesDir}/dep"])
    cmd(&"nimby install file://{testPackagesDir}/myapp")
    writeFile(testWorkspace / "myapp" / "nimby.lock", cmd("nimby lock myapp"))

    cmdAt(testWorkspace / "myapp", "nimby c src/myapp.nim")

  test "forward extra arguments to nim c":
    cmd("nimby create")
    createTestPackage("myapp")
    cmd(&"nimby install file://{testPackagesDir}/myapp")
    writeFile(testWorkspace / "myapp" / "nimby.lock", "")

    cmdAt(testWorkspace / "myapp", "nimby c -d:release src/myapp.nim")

  test "compile when NIMBY_HOME has spaces":
    let spacedHome = getTempDir() / "nimby home with spaces"
    removeDir(spacedHome)
    putEnv("NIMBY_HOME", spacedHome)
    cmd("nimby use 2.2.10")
    cmd("nimby create")
    createTestPackage("myapp")
    cmd(&"nimby install file://{testPackagesDir}/myapp")
    writeFile(testWorkspace / "myapp" / "nimby.lock", "")

    cmdAt(testWorkspace / "myapp", "nimby c src/myapp.nim")
    removeDir(spacedHome)
    putEnv("NIMBY_HOME", nimbyHome)

  test "dispatch cpp, js, doc, and check to nim":
    cmd("nimby create")
    createTestPackage("myapp")
    cmd(&"nimby install file://{testPackagesDir}/myapp")
    writeFile(testWorkspace / "myapp" / "nimby.lock", "")

    cmdAt(testWorkspace / "myapp", "nimby check src/myapp.nim")
    cmdAt(testWorkspace / "myapp", "nimby doc src/myapp.nim")
    cmdAt(testWorkspace / "myapp", "nimby js src/myapp.nim")
    cmdAt(testWorkspace / "myapp", "nimby cpp src/myapp.nim")

suite "`nimby update` should":
  setup:
    setupTestPackages()
    setupEnvironment()
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
      repoPath = nimbyHome / "pkgs" / "nimbytestpackage"
      present = rewindPackage(repoPath, "HEAD^")

    cmd("nimby update nimbytestpackage")

    let actual = getCommit(repoPath)
    check present == actual

  test "update local and global packages with --all":
    cmd("nimby install -g https://github.com/treeform/bitty.git")
    cmd("nimby install https://github.com/RowDaBoat/nimbytestpackage.git")
    let
      bittyPath = nimbyHome / "pkgs" / "bitty"
      ntpPath = "nimbytestpackage"
      bittyPresent = rewindPackage(bittyPath, "HEAD^", "master")
      ntpPresent = rewindPackage(ntpPath, "HEAD^")

    cmd("nimby update --all -y")

    let
      bittyActual = getCommit(bittyPath)
      ntpActual = getCommit(ntpPath)

    check bittyPresent == bittyActual
    check ntpPresent == ntpActual

suite "`nimby doctor` should":
  setup:
    setupTestPackages()
    setupEnvironment()

  test "fail when no workspace exists":
    let output = cmdFail("nimby doctor")
    check output.contains("No Nimby workspace found")

  test "fail when nim.cfg is not managed by Nimby":
    writeFile(testWorkspace / "nim.cfg", "--path:\"something/src\"\n")
    let output = cmdFail("nimby doctor")
    check output.contains("No Nimby workspace found")

  test "report unexpected lines in nim.cfg":
    cmd("nimby create")
    let nimCfg = readFile(testWorkspace / "nim.cfg")
    writeFile(testWorkspace / "nim.cfg", nimCfg & "some garbage line\n")
    let output = cmd("nimby doctor")
    check output.contains("Unexpected line in nim.cfg")

  test "report package linked in nim.cfg but missing from disk":
    cmd("nimby create")
    let nimCfg = readFile(testWorkspace / "nim.cfg")
    writeFile(testWorkspace / "nim.cfg", nimCfg & "--path:\"ghost/src\"\n")
    let output = cmd("nimby doctor")
    check output.contains("ghost")
    check output.contains("missing from disk")

  test "report missing dependency for a package":
    createTestPackage("dep")
    createTestPackage("myapp", requires = [&"file://{testPackagesDir}/dep"])
    cmd(&"nimby install file://{testPackagesDir}/myapp")
    removeDir(testWorkspace / "dep")
    let output = cmd("nimby doctor")
    check output.contains("dep")
    check output.contains("not found for package")

  test "report package with no .nimble file":
    cmd("nimby create")
    createDir(testWorkspace / "notnim")
    let nimCfg = readFile(testWorkspace / "nim.cfg")
    writeFile(testWorkspace / "nim.cfg", nimCfg & "--path:\"notnim/src\"\n")
    let output = cmd("nimby doctor")
    check output.contains("notnim")
    check output.contains("no .nimble file")

  test "report package not linked in nim.cfg":
    createTestPackage("myapp")
    cmd(&"nimby install file://{testPackagesDir}/myapp")
    writeFile(testWorkspace / "nim.cfg", "# Managed by Nimby\n")
    let output = cmd("nimby doctor")
    check output.contains("myapp")
    check output.contains("not linked in nim.cfg")

  test "report orphan directories not in nim.cfg":
    cmd("nimby create")
    createDir(testWorkspace / "stray")
    let output = cmd("nimby doctor")
    check output.contains("stray/")
    check output.contains("not linked in nim.cfg")

  test "report missing dependency for a named package":
    createTestPackage("dep")
    createTestPackage("myapp", requires = [&"file://{testPackagesDir}/dep"])
    cmd(&"nimby install file://{testPackagesDir}/myapp")
    removeDir(testWorkspace / "dep")
    let output = cmd("nimby doctor myapp")
    check output.contains("dep")
    check output.contains("not found for package")

  test "report named package not linked in nim.cfg":
    createTestPackage("myapp")
    cmd(&"nimby install file://{testPackagesDir}/myapp")
    writeFile(testWorkspace / "nim.cfg", "# Managed by Nimby\n")
    let output = cmd("nimby doctor myapp")
    check output.contains("myapp")
    check output.contains("not linked in nim.cfg")

  test "fail when named package directory does not exist":
    cmd("nimby create")
    let output = cmdFail("nimby doctor ghost")
    check output.contains("ghost")
    check output.contains("not found")

  test "work from a subdirectory of the workspace":
    cmd("nimby create")
    createDir(testWorkspace / "stray")
    let nested = testWorkspace / "subdir"
    createDir(nested)
    let output = cmdAt(nested, "nimby doctor")
    check output.contains("stray/")
    check output.contains("not linked in nim.cfg")

suite "NIMBY_HOME environment variable":
  setup:
    setupTestPackages()
    setupEnvironment()

  test "global install with -g uses NIMBY_HOME when set":
    let customHome = getTempDir() / "nimby_custom_home"
    removeDir(customHome)
    putEnv("NIMBY_HOME", customHome)
    cmd("nimby create")
    cmd("nimby install -g -V mummy")
    putEnv("NIMBY_HOME", nimbyHome)
    check dirExists(customHome / "pkgs" / "mummy")
