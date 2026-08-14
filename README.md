![Nimby Logo](docs/nimbyLogo.png)

# Nimby

`nimble install nimby`

![GitHub Actions](https://github.com/treeform/nimby/workflows/Github%20Actions/badge.svg)

[API reference](https://treeform.github.io/nimby)

Nimby is the fastest and simplest way to install Nim packages.
It keeps things honest, transparent, and lightning fast.

## Quick Start

```sh skip
curl -L -o nimby https://github.com/treeform/nimby/releases/download/0.1.27/nimby-Linux-X64
chmod +x nimby
./nimby use 2.2.10
./nimby create
./nimby install libraryA libraryB libraryC
./nimby lock library > library/nimby.lock
./nimby sync library/nimby.lock
```

## Why Nimby exists

When I added Nim to our company CI, our builds suddenly became very slow. Nimble installs took almost two minutes for Fidget2. That felt wrong, so I started digging.

I tried replacing Nimble with a few simple shell scripts that just cloned the repos with git. It built fine, and was way, way faster! So then I wrote Nimby as a tool to clone everything in parallel:

* Nimble: 2 minutes
* Nimby: 3 seconds

At its core, Nimby runs `git clone` and updates `nim.cfg` in the workspace folder.

After that, Nimby grew from a few basic ideas:

* Have a single workspace folder.
* Download Nim packages using git.
* Do not resolve dependencies.
* Always grab `#HEAD`.
* Do everything in parallel.

Instead of magic, Nimby just uses git. It clones repositories directly into your workspace, reads their `.nimble` files, and installs dependencies in parallel. Packages are shallow-cloned and checked out at HEAD by design, and their paths are written straight into your `nim.cfg`.

You can also install globally with `-g` in the `~/.nimby/pkgs` folder. Nimby can install the Nim compiler itself into the `~/.nimby/nim/bin` folder. With two commands, you can download Nim, install all your packages, and be ready to build in about 14 seconds.

## How to use

* Create a workspace with `nimby create` in the folder where you want packages to live.
* Install with `nimby install libraryA libraryB libraryC` for development.
* Keep your project alongside its dependencies in the workspace.
  ```
  workspace/
    nim.cfg
    project/
    libraryA/
    libraryB/
    libraryC/
  ```
* Create a lock file with `nimby lock project > project/nimby.lock`.
  ```
  libraryA 1.0.0 https://github.com/treeform/libraryA xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
  libraryB 1.0.0 https://github.com/treeform/libraryB xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
  libraryC 1.0.0 https://github.com/treeform/libraryC xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
  ```
* For CI and deployments, use the lock file with `nimby sync project/nimby.lock`.
  ```
  workspace/
    nim.cfg
    project/
    libraryA/
    libraryB/
    libraryC/
  ```

## Why always install HEAD?

Well, the Nim community is small, and it doesn't really have the packaging culture that other languages do. And that's fine. In a way, it's actually freeing!

But it also means that people rarely test older versions of packages against older versions of other packages. It's boring, thankless work, after all.

Because of that, many version requirements in `.nimble` files don't really reflect reality. They might claim that a version is supported, but in practice, no one tests the old stuff. And that's okay. It's just how the community works.

So Nimby follows the community approach and always checks out HEAD, because HEAD has the highest chance of working. Even if an API has changed, we now have AI tools that can help fix minor API changes.

For development, installing from HEAD is the best way to move forward. It keeps everything current and in sync with how people actually develop Nim projects. It avoids diamond dependencies (where your package depends on A and B, but A and B depend on conflicting versions of C) and keeps things simple. I love simple things.

But installing from HEAD is not good for CI, releases, or deployment to production. That's where lock files come in. Since the development process relies on HEAD, lock files give you a way to record exactly what worked at a given moment in time for deployment.

Generating a lock file is easy. Commit it along with your code. When you need to reproduce a build, just run `nimby sync repo/nimby.lock`; Nimby will install the exact dependencies and commits listed in that file. It's a simple text file that lists package names, URLs, and commits.

## What is the deal with the workspace folder?

Create a workspace with `nimby create` in the folder where you want packages to live.
After that, you can run commands from inside any package or subdirectory and Nimby will walk upward until it finds that workspace.
If no workspace exists, Nimby will only create one automatically in plain directories.
Inside a Git checkout or a Nimble package, it stops and asks you to run `nimby create` in the directory you really want as the workspace.

I think the workspace folder is great. The way I have things set up, there's a single Nim config file, and all the packages I'm working on live together as simple git checkouts.

Alongside them, I also keep clones of all the dependencies I use. Everything lives in one place:

```
workspace/
  nim.cfg
  fidget2/
  pixie/
  jsony/
  puppy/
  mummy/
  ..
```

This makes it much easier to move around and explore the codebase. If I'm developing something and want to see what a function does inside one of the dependencies, I can just open it right there. No hunting through hidden directories or special paths.

It also helps modern AI tools. Since everything sits in one folder, they can read and understand the source code of all your dependencies at once, giving you better suggestions and context.

I never liked it when packages get installed into hidden folders deep in your home directory, or when they end up scattered inside things like `deps` or `nim_modules`. It feels messy. I like everything to be clean and simple, and having all your checkouts in one visible folder is the simplest way I can think of.

Not everyone develops like this, though. Sometimes you just need a tool globally and don't want it sitting in your workspace. That's why I added the `-g` or `--global` flag. It installs packages in the global Nimby folder, `~/.nimby/pkgs`, instead of the local workspace. This is especially handy for CI setups or for people who only need to use packages, not develop them.

The global option works for both `nimby install -g` and, even more importantly, `nimby sync -g` when you're working with lock files. That's really all there is to it.

## What? It also installs Nim itself?

Yeah, installing Nim is actually pretty easy. You just copy a couple of folders, put them in the right place, and add `~/.nimby/nim/bin` to your system path. That's it.

I think it's a great addition to have in Nimby because it makes setup incredibly simple. You can just curl the Nimby binary for your system, `curl -L -o nimby https://github.com/treeform/nimby/releases/download/0.1.27/nimby-Linux-X64`, and that's all you need. Then you run `./nimby use 2.2.10` with the Nim version you want, and `./nimby sync your/nimby.lock` with your lock file.

This works perfectly for CI workflows, deployments, or any situation where you're starting with a blank machine. You don't need to install anything else. Nimby downloads Nim, installs your packages, and you're ready to go.

---

## Installation

### macOS ARM64
```sh skip
curl -L -o nimby https://github.com/treeform/nimby/releases/download/0.1.27/nimby-macOS-ARM64
chmod +x nimby
```

### Linux X64
```sh skip
curl -L -o nimby https://github.com/treeform/nimby/releases/download/0.1.27/nimby-Linux-X64
chmod +x nimby
```

### Linux ARM64
```sh skip
curl -L -o nimby https://github.com/treeform/nimby/releases/download/0.1.27/nimby-Linux-ARM64
chmod +x nimby
```

### Windows
```sh skip
curl -L -o nimby.exe https://github.com/treeform/nimby/releases/download/0.1.27/nimby-Windows-X64.exe
```

### Nimble

```sh skip
nimble install nimby
```

---

## Installing Nim

Nimby can install Nim itself into `~/.nimby/nim`:

```sh skip
nimby use 2.2.10
```

`nimby use <version>` downloads that Nim version and makes it the active Nim
compiler under `~/.nimby/nim`.

After that, add Nim's bin directory to `PATH`.

For bash or zsh:

```sh skip
export PATH="$HOME/.nimby/nim/bin:$PATH"
```

For PowerShell:

```sh skip
$env:PATH = "$HOME\.nimby\nim\bin;$env:PATH"   # PowerShell
```

## Installing Packages

Installing from a git URL is useful for forks, private repositories, and
packages that are not in the index:

```sh
nimby install https://github.com/treeform/bitty.git
```

```output
Installing package: https://github.com/treeform/bitty.git
Cloning into 'bitty'...
Installed package: bitty
```

Fragments select a branch, tag, commit hash, or other git ref:

```sh
nimby install https://github.com/treeform/nimbytestpackage.git#branch 2>&1 |
  sed -n "/^Installing package:/p; /^Cloning into 'nimbytestpackage'...$/p; /^Installed package: nimbytestpackage$/p"
```

```output
Installing package: https://github.com/treeform/nimbytestpackage.git#branch
Cloning into 'nimbytestpackage'...
Installed package: nimbytestpackage
```

For day-to-day development, installing by package name checks Nim's package
index and clones the package into the current workspace:

```sh
nimby install silky 2>&1 |
  sed -n '/^Installing package: silky$/p; /^Installed package: silky$/p'
```

```output
Installing package: silky
Installed package: silky
```

You can install several packages in one command, with spaces or commas:

```sh skip
nimby install taggy, orbits, stenography
```

Global installs use `~/.nimby/pkgs` instead of the current workspace:

```sh skip
nimby install -g cligen
```

Nimby installs packages in parallel and updates your `nim.cfg` automatically.
If it finds a `.nimble` file with version rules that do not match, it will warn you but still install HEAD, since that is what actually works in practice.

---

## The CLI

`nimby --version` prints the version and exits.

```sh
nimby --version
```

`nimby help` shows the command surface. This is a useful smoke test because it
does not need a workspace.

```sh
nimby help
```

```output
Usage: nimby <subcommand> [options]
  ~ Minimal package manager for Nim. ~
    -g, --global Install packages in the ~/.nimby/pkgs directory
    -v, --version print the version of Nimby
    -h, --help show this help message
    -V, --verbose print verbose output
Package subcommands:
  create     create a Nimby workspace in the current directory
  install    install Nim packages into the current workspace
  update     update all Nim packages in the current directory
  remove     remove all Nim packages in the current directory
  list       list all Nim packages in the current directory
  tree       show all packages as a dependency tree
  doctor     diagnose all packages and fix linking issues
  lock       generate a lock file for a package
  sync       synchronize packages from a lock file
  use        install a Nim compiler version
  help       show this help message
Compiler subcommands:
  All verify packages are locked, then forward arguments to nim.
  c          compile project to C code
  cpp        compile project to C++ code
  js         compile project to Javascript
  e          run a Nimscript file
  doc        generate the documentation for inputfile
  check      checks the project for syntax and semantics
```

## Working with lock files

Lock files make CI and reproducible builds easy.
During development, you let packages float and track HEAD.
When you need a reproducible build, you freeze the exact commits.

Generate a lock file:

```sh
nimby lock nimbytestpackage | grep -v '^Nimby ' > nimby.lock
grep '^chroma ' nimby.lock | cut -d' ' -f1-3
```

```output
chroma 1.0.0 https://github.com/treeform/chroma
```

Install from a lock file:

```sh
mkdir synced
cp nimby.lock synced/
cd synced
nimby create >/dev/null
nimby sync nimby.lock 2>&1 | sed -n '/^Installed package: chroma$/p'
```

```output
Installed package: chroma
```

The synchronized package is now part of the workspace.

```sh
cd synced
nimby tree chroma
```

```output
chroma 1.0.0
```

## Updating And Removing

`update` runs git pull for a package checkout:

```sh
nimby update silky 2>&1 | sed -n '/^Updated package: silky$/p'
```

```output
Updated package: silky
```

`update --all` updates both workspace and global packages. It prompts first, so
use `-y` only when the command is already intentional:

```sh
nimby update --all -y >/dev/null && echo "Updated all packages"
```

```output
Updated all packages
```

Removing a package also removes its path from `nim.cfg`.

```sh
nimby remove silky
```

```output
Removed package: silky
```

Global synchronization is the same idea, but writes to the global package
directory:

```sh
nimby sync -g nimby.lock 2>&1 | sed -n '/^Installed package: chroma$/p'
```

```output
Installed package: chroma
```

This is similar to how Cargo, npm, and other package managers use lock files, but it is kept as a simple text file that lists package names, URLs, and commits.

---

`nimby doctor` will report missing folders, broken git repos, and out-of-sync paths in your `nim.cfg`.
