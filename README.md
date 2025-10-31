![Nimby Logo](docs/nimbyLogo.png)

# Nimby

`nimble install nimby`

![Github Actions](https://github.com/treeform/nimby/workflows/Github%20Actions/badge.svg)

[API reference](https://treeform.github.io/nimby)

Nimby is the fastest and the most simple way to install Nim packages.

It's a crazy simple system that just git clones repos into the current workspace.

Is Nimble slow?

It came to my attention when we added Nim to our company that our CI speed got way, way slower, and I started wondering why. And so I ran a little investigation. So it looks like it takes about 1:51 seconds to install the Nimble packages for Fidget2.

All right, I thought to myself, well, that's a little slow. Let's see if I can replicate what Nimble does with just git commands. So that's what I did. I just git cloned every package and stuck them into nim.cfg, and everything built. And it was way faster! It was only 20 seconds. So what is Nimble doing for that 1:31 seconds extra? Very strange. SAT solving can't take that much. Even like walking the package tree can't take that long.

Then I thought, well, git is actually kind of slow, because you have to do the handshake and do the git:// protocol. What if you just curl & unzip the packages directly? And then I did that, and that was even faster. 16 seconds!

It's like, wow, okay, now we're going. Well, what about if we do it in parallel? In parallel, it's like 3 seconds. Okay, so if you just download zips in parallel, it's 3 seconds. But if you use Nimble, it's 1:51 seconds. Is this true? Am I doing something wrong?

Code here: https://github.com/treeform/fidget2/pull/91/files

```
* Nimble ..................... 1:51s https://github.com/treeform/fidget2/actions/runs/18803878890/job/53655066175
* Git clone .................... 20s https://github.com/treeform/fidget2/actions/runs/18803878889/job/53655066135
* Curl Zips .................... 16s https://github.com/treeform/fidget2/actions/runs/18803878895/job/53655066174
* Curl Zips in Parallel ......... 3s https://github.com/treeform/fidget2/actions/runs/18803878916/job/53655066170
```

## Quick Start

### macOS ARM64
```
curl -L -o nimby https://github.com/treeform/nimby/releases/download/v0.1.2/nimby-macOS-ARM64
chmod +x nimby
```

### Linux X64
```
curl -L -o nimby https://github.com/treeform/nimby/releases/download/v0.1.2/nimby-Linux-X64
chmod +x nimby
```

### Windows
```
curl -L -o nimby.exe https://github.com/treeform/nimby/releases/download/v0.1.2/nimby-Windows-X64.exe
```

# Install Nim
```
nimby use 2.2.4
```

# Install a package
```
nimby install fidget2
```

# Install a lock file in CI
```
nimby sync fidget2.lock
```

# Update a package
```
nimby update fidget2
```

# Remove a package
```
nimby remove fidget2
```

# List installed packages
```
nimby list
```

# List dependencies in a tree view
```
nimby tree fidget2
```

# Generate a lock file
```
nimby lock fidget2
```

# Check the status of a package
```
nimby doctor fidget2
```
