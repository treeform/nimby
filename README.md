
![Nimby Logo](docs/nimbyLogo.png)

# Nimby

`nimble install nimby`

![Github Actions](https://github.com/treeform/nimby/workflows/Github%20Actions/badge.svg)

[API reference](https://treeform.github.io/nimby)

Nimby is the fastest and simplest way to install Nim packages.
It keeps things honest, transparent, and lightning fast.

Instead of magic, Nimby just uses git. It clones repositories directly into your workspace, reads their `.nimble` files, and installs dependencies in parallel. Everything is shallow cloned, HEAD by design, and written straight into your `nim.cfg`.

You can also install globally with `-g` in `~/.nimby/pkgs` folder. Nimby can install the Nim compiler itself as well in the `~/.nimby/nim/bin` folder. With two commands you can download Nim and install all your packages, and be ready to build in seconds around 14 seconds.

---

## Why Nimby exists

When I added Nim to our company CI, our builds suddenly became very slow. Nimble installs took almost two minutes for Fidget2. That felt wrong, so I started digging.

I tried replacing Nimble with a few simple shell scripts that just cloned the repos with git. It built fine, and was way way faster! 2 minutes vs 3 seconds faster.

So Nimby started from a simple idea: download Nim packages from git, do not resolve dependencies, and in parallel.

## Why always install HEAD?

Well, the Nim community is small, and it doesn’t really have the packaging culture that other languages do. And that’s fine. In a way, it’s actually freeing!

But it also means that people rarely test older versions of packages against older versions of other packages. It's just boring thankless work after all.

This makes a lot of the version numbers in requirements you see in `.nimble` files don’t really reflect reality. They might claim that a version is supported, but in practice, no one tests the old stuff. And that’s okay. It’s just how the community works.

So Nimby follows the community approach and always checks out HEAD, because HEAD has the highest chance of working. Even if an API has changed, we now have AI tools that can help fix minor API changes.

For development, installing from HEAD is the best way to move forward. It keeps everything current and in sync with how people actually develop Nim projects. It avoids diamond dependencies (where your package depends on A and B, but A and B depend on conflicting versions of C) and keeps things simple. I love simple things.

But installing from HEAD is not good for CI, releases, or deployment to production. That’s where lock files come in. Since the community relies on HEAD, lock files give you a way to record exactly what worked at a given moment in time.

Generating a lock file is easy. Commit it along with your code, and when you need to reproduce a build, Nimby can install the exact dependencies and commits listed in that file. It's just a simple text file that lists package names, URLs, and commits.

So the model is simple: use HEAD (`nimby install`) for development, and use lock files for deployment (`nimby sync`). It’s the best of both worlds.
It's a simple text file that lists package names, URLs, and commits.


## What is the deal with the workspace folder?

You always should run `nimby` commands from the workspace folder just like you would with `git clone`. It's not wrong to think of nimby like a `git clone` with extra steps.

I think the workspace folder is great. The way I have things set up, there’s a single Nim config file, and all the packages I’m working on live together as simple git checkouts.
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

This makes it much easier to move around and explore the code base. If I’m developing something and want to see what a function does inside one of the dependencies, I can just open it right there. No hunting through hidden directories or special paths.

It also helps modern AI tools. Since everything sits in one folder, they can read and understand the source code of all your dependencies at once, giving you better suggestions and context.

I never liked it when packages get installed into hidden folders deep in your home directory, or when they end up scattered inside things like `deps` or `nim_modules`. It feels messy. I like everything to be clean and simple, and having all your checkouts in one visible folder is the simplest way I can think of.

Not everyone develops like this, though. Sometimes you just need a tool globally and don’t want it sitting in your workspace. That’s why I added the `-g` or `--global` flag. It installs packages in a global Nimby folder `~/.nimby/pkgs` instead of the local workspace. This is especially handy for CI setups or for people who only need to use packages, not develop them.

The global option works for both `nimby install -g` and even more importantly `nimby sync -g` when you’re working with lock files. That’s really all there is to it.

## What? It also installs Nim itself?

Yeah, installing Nim is actually pretty easy. You just copy a couple of folders, put them in the right place, and add `~/.nimby/nim/bin` to your system path. That’s it.

I think it’s a great addition to have in Nimby because it makes setup incredibly simple. You can just curl the Nimby binary for your system `curl -L -o nimby https://github.com/treeform/nimby/releases/download/v0.1.2/nimby-Linux-X64`, and that’s all you need. Then you run `./nimby use 2.2.6` with the Nim version you want, and `./nimby install your/nimby.lock` with your lock file.

This works perfectly for CI workflows, deployments, or any situation where you’re starting with a blank machine. You don’t need to install anything else. Nimby downloads Nim, installs your packages, and you’re ready to go.

---

## Installation

### macOS ARM64
```
curl -L -o nimby https://github.com/treeform/nimby/releases/download/0.1.16/nimby-macOS-ARM64
chmod +x nimby
```

### Linux X64
```
curl -L -o nimby https://github.com/treeform/nimby/releases/download/0.1.16/nimby-Linux-X64
chmod +x nimby
```

### Linux ARM64
```
curl -L -o nimby https://github.com/treeform/nimby/releases/download/0.1.16/nimby-Linux-ARM64
chmod +x nimby
```

### Windows
```
curl -L -o nimby.exe https://github.com/treeform/nimby/releases/download/0.1.16/nimby-Windows-X64.exe
```


---

## Add Nim to your PATH

```sh
export PATH="$HOME/.nimby/nim/bin:$PATH"
```

```sh
$env:PATH = "$HOME\.nimby\nim\bin;$env:PATH"   # PowerShell
```

---

## Quick Start

Install Nim itself:

```sh
nimby use 2.2.4
```

Install a package:

```sh
nimby install fidget2
```

Update a package:

```sh
nimby update fidget2
```

Remove a package:

```sh
nimby remove fidget2
```

Install globally:

```sh
nimby install -g cligen
```

Nimby installs packages in parallel and updates your `nim.cfg` automatically.
If it finds a `.nimble` file with version rules that do not match, it will warn you but still install HEAD, since that is what actually works in practice.

---

## Working with lock files

Lock files make CI and reproducible builds easy.
During development, you let packages float and track HEAD.
When you need a reproducible build, you freeze the exact commits.

Generate a lock file:

```sh
nimby lock
```

Install from a lock file:

```sh
nimby sync
```

This is similar to how Cargo, npm, and other package managers use lock files, but kept as simple text that lists package names, URLs, and commits.

---

## Other commands

List all installed packages:

```sh
nimby list
```

View dependency tree:

```sh
nimby tree fidget2
```

Check workspace health:

```sh
nimby doctor
```

`nimby doctor` will report missing folders, broken git repos, and out-of-sync paths in your `nim.cfg`.
