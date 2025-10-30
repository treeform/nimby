import os


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

removeDir(expandTilde("~/.nimby/packages"))
removeDir(expandTilde("~/.nimby/tmp"))
createDir(expandTilde("~/.nimby/tmp"))
setCurrentDir(expandTilde("~/.nimby/tmp"))

cmd("nimby install -V mummy")
doAssert dirExists("mummy")
cmd("nimby remove mummy")

removeDir(expandTilde("~/.nimby/packages"))
removeDir(expandTilde("~/.nimby/tmp"))
createDir(expandTilde("~/.nimby/tmp"))
setCurrentDir(expandTilde("~/.nimby/tmp"))

cmd("nimby install -g -V mummy")
doAssert not dirExists("mummy")
doAssert dirExists(expandTilde("~/.nimby/packages/mummy"))
