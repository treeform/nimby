import 
  std/[os],
  ../src/nimby

echo "Test 1: parses version and srcDir without deps"
let path1 = getTempDir() / "test1.nimble"
writeFile(path1, """
version = "0.1.2"
srcDir = "src"
""")
let n1 = parseNimbleFile(path1)
doAssert n1.version == "0.1.2", "version should parse"
doAssert n1.srcDir == "src", "srcDir should parse"
doAssert n1.deps.len == 0, "no deps expected"
removeFile(path1)

echo "Test 2: parses nim version requirement as a dep"
let path2 = getTempDir() / "test2.nimble"
writeFile(path2, """
version = "1.2.3"
srcDir = "lib"
requires "nim >= 1.6.2"
""")
let n2 = parseNimbleFile(path2)
doAssert n2.version == "1.2.3"
doAssert n2.srcDir == "lib"
doAssert n2.deps.len == 1
doAssert n2.deps[0] == ("nim", ">=", "1.6.2")
removeFile(path2)

echo "Test 3: parses no formula for dependency"
let path3 = getTempDir() / "test3.nimble"
writeFile(path3, """
version = "0.0.1"
srcDir = "src"
requires "pixie"
""")
let n3 = parseNimbleFile(path3)
doAssert n3.deps.len == 1
doAssert n3.deps[0] == ("pixie", "", "")
removeFile(path3)

echo "Test 4: parses multiple requires lines and preserves order"
let path4 = getTempDir() / "test4.nimble"
writeFile(path4, """
version = "2.0.0"
srcDir = "src"
requires "pixie >= 0.3.1"
requires "chroma == 0.2.0"
""")
let n4 = parseNimbleFile(path4)
doAssert n4.deps.len == 2
doAssert n4.deps[0] == ("pixie", ">=", "0.3.1")
doAssert n4.deps[1] == ("chroma", "==", "0.2.0")
removeFile(path4)

echo "Test 5: tolerates extra whitespace in requires line"
let path5 = getTempDir() / "test5.nimble"
writeFile(path5, """
version =  "3.0.0a"
srcDir  = "src"
requires    "vmath   >=   1.0.0"
""")
let n5 = parseNimbleFile(path5)
doAssert n5.version == "3.0.0a", "version should parse"
doAssert n5.srcDir == "src", "srcDir should parse"
doAssert n5.deps.len == 1
doAssert n5.deps[0] == ("vmath", ">=", "1.0.0")
removeFile(path5)

echo "All parseNimbleFile tests passed."
