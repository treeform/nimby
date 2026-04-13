import os, strutils, sequtils, sets, tables


proc cmd(command: string) =
  echo "> ", command
  let result = execShellCmd(command)
  if result != 0:
    raise newException(Exception, "Command failed: " & $result)

# cmd("nimby --help")
# cmd("nimby -h")
# cmd("nimby --version")
# cmd("nimby -v")
# cmd("nimby --help")
# cmd("nimby -h")
# cmd("nimby --version")
# cmd("nimby -v")

proc setup() =
  removeDir(expandTilde("~/.nimby/nimbylock"))
  removeDir(expandTilde("~/.nimby/pkgs"))
  removeDir(expandTilde("~/.nimby/tmp"))
  createDir(expandTilde("~/.nimby/tmp"))
  setCurrentDir(expandTilde("~/.nimby/tmp"))

echo "`install` should create the package locally:"
echo "------------------------"
setup()
cmd("nimby install -V mummy")
doAssert dirExists("mummy")
cmd("nimby remove mummy")

removeDir(expandTilde("~/.nimby/pkgs"))
removeDir(expandTilde("~/.nimby/tmp"))
createDir(expandTilde("~/.nimby/tmp"))
setCurrentDir(expandTilde("~/.nimby/tmp"))
echo "------------------------"
echo ""

echo "`install -g` should create the package globally:"
echo "------------------------"
setup()
cmd("nimby install -g -V mummy")
doAssert not dirExists("mummy")
doAssert dirExists(expandTilde("~/.nimby/pkgs/mummy"))
echo "------------------------"
echo ""

echo "`lock` should include dependencies in the package with their corresponding URLs:"
echo "------------------------"
setup()
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
echo "------------------------"
echo ""
