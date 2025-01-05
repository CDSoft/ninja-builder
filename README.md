# Ninja builder

This repository just bundles [Ninja](https://github.com/ninja-build/ninja) into a Git project.
It provides a shell script to cross compile Ninja for Linux, MacOS and Windows.

# Usage

```
$ ./ninja-builder.sh
```

This compiles the Ninja binaries for Linux, MacOS and Windows with `zig`.

```
$ ./ninja-builder.sh gcc install
```

This compiles and installs the Ninja binary for the host with `gcc`.

```
$ ./ninja-builder.sh clang install
```

This compiles and installs the Ninja binary for the host with `clang`.
