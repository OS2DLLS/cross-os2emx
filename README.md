# cross-os2emx

`cross-os2emx` provides a Linux-hosted cross-compilation toolchain for the
`i686-pc-os2-emx` target. Linux runs the build tools (including CMake and
Meson); the cross compiler produces OS/2 objects, executables, and DLLs.

The toolchain includes OS/2-enabled binutils and GCC, the EMX utilities and
headers, CMake, Meson, libtool, and helper scripts. The installed GCC reports
version 9.2.0, CMake 3.31.7, and Meson is configured as 1.11.1.

## Build the toolchain on Linux

### Host prerequisites

Install or otherwise provide the following Linux host tools and libraries:

- GNU Make, GCC and G++
- Git, `wget`, `tar`, `gzip`, and `unzip`
- Flex, Bison, M4, Texinfo/`makeinfo`, and gettext utilities such as `autopoint`
- Perl, Python 3, `pkg-config`, `sed`, `gawk`, and standard core utilities
- OpenSSL development headers and libraries, used by the CMake build

The Makefile bootstraps its required Autoconf, Automake, and libtool versions
and downloads/builds Meson. Those steps do not replace the host prerequisites
listed above. On Linux, the Makefile prefers `/usr/bin` and `/bin` for host
compilers and arranges the flex/glibc library paths needed by this build.

### Source checkout layout

From the repository root, the default command is:

```sh
cd /data/cross-os2emx
make PREFIX=/data/os2emx
```

The current Makefile defaults to these paths:

| Purpose | Default |
| --- | --- |
| Build root | `/data/build-nix` |
| Component build/download root | `/data/build-nix/cross-os2emx` |
| Installed toolchain prefix | `/data/build-nix/cross-os2emx/toolchain` |
| Source root | Parent directory of this checkout |

With the default source root, the Makefile expects these component worktrees
in its parent directory:

| Makefile variable | Required directory name |
| --- | --- |
| `BINUTILSDIR` | `binutils-os2` |
| `GCCDIR` | `gcc-os2` |
| `CMAKEDIR` | `cmake-os2` |
| `LIBCDIR` | `libc-os2` |

The current Linux build layout uses patched worktrees outside the main
checkout. The Git submodules inside the checkout may be reference revisions;
initializing them alone does not guarantee that they contain all patches used
by the external worktrees. To use the submodules directly, initialize and
verify their revisions first, then pass the component paths explicitly. For
example, from the repository root:

```sh
make \
  BINUTILSDIR="$PWD/binutils-os2" \
  GCCDIR="$PWD/gcc-os2" \
  CMAKEDIR="$PWD/cmake-os2" \
  LIBCDIR="$PWD/libc"
```

Use that override only when those checkouts contain the required OS/2
cross-build changes. The `libc` submodule's directory name differs from the
default external worktree name `libc-os2`.

The main build variables can be overridden when needed:

```sh
make OS2EMX_BUILD_ROOT=/data/build-nix \
     OS2EMX_SOURCE_ROOT=/path/to/component-worktrees \
     PREFIX=/data/build-nix/my-os2-toolchain
```

By default, `make` installs into the isolated `toolchain/` prefix shown above;
it does not overwrite `/data/os2emx`. Keep build directories outside source
checkouts. Avoid `make -n` as a supposedly safe dry run: GNU Make may execute
recipe lines containing recursive `$(MAKE)` even in print-only mode.

### Check the installed toolchain

After the build, set the prefix and inspect the host tools and target identity:

```sh
export TOOLCHAIN_PREFIX=/data/build-nix/cross-os2emx/bare-make/toolchain
export PATH="$TOOLCHAIN_PREFIX/bin:$PATH"

"$TOOLCHAIN_PREFIX/bin/i686-pc-os2-emx-gcc" --version
"$TOOLCHAIN_PREFIX/bin/i686-pc-os2-emx-gcc" -dumpmachine
"$TOOLCHAIN_PREFIX/bin/i686-pc-os2-emx-g++" -dumpmachine
"$TOOLCHAIN_PREFIX/bin/cmake" --version
```

The target triple should be `i686-pc-os2-emx`. CMake is a Linux host program;
the GCC/G++ drivers are Linux programs that emit OS/2 target files.

## Cross-compile a project from Linux

Use a separate build directory under the approved build root, not inside the
source checkout. The generated cross files configure the target compiler,
sysroot, and OMF-related tools and flags.

For the `/data` workspace, `shell.nix` provides a workspace-wide CMake default
using the source-controlled toolchain file
`/data/cross-os2emx/cmake/os2emx-default.cmake`. It reads the compiler,
sysroot, and OMF archiver from the generic `OS2EMX_*` environment. The file is
kept with this source checkout; `/data/build-nix` is only for generated build
trees and logs. A fresh CMake configure in the default target shell consumes
`CMAKE_TOOLCHAIN_FILE` automatically and uses Ninja. Use
`OS2EMX_BUILD_MODE=host` when configuring or building Linux host tools so the
cross compiler defaults are removed. Existing CMake caches retain their
original toolchain and generator; use a fresh build directory when switching
between host and target configurations.

### CMake

The installed CMake toolchain file is:

```text
$TOOLCHAIN_PREFIX/share/cmake/cross/i686-pc-os2-emx.cmake
```

Example:

```sh
PROJECT_SOURCE=/path/to/project
BUILD_DIR=/data/build-nix/my-project-os2

"$TOOLCHAIN_PREFIX/bin/cmake" \
  -S "$PROJECT_SOURCE" \
  -B "$BUILD_DIR" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_PREFIX/share/cmake/cross/i686-pc-os2-emx.cmake" \
  -DCMAKE_BUILD_TYPE=Release
"$TOOLCHAIN_PREFIX/bin/cmake" --build "$BUILD_DIR" -j2
```

The toolchain file sets `CMAKE_SYSTEM_NAME` to OS/2, selects the
`i686-pc-os2-emx` C and C++ compilers, sets the target sysroot and configures
OMF/linker flags. Keep CMake and other code generators on the Linux host; do
not try to run target executables during configuration unless the project has
an OS/2 emulator configured.

### Meson

The installed cross files are:

```text
$TOOLCHAIN_PREFIX/share/meson/cross/i686-pc-os2-emx-aout.txt
$TOOLCHAIN_PREFIX/share/meson/cross/i686-pc-os2-emx-omf.txt
```

Choose the file that matches the object format required by the project. For
OMF:

```sh
PROJECT_SOURCE=/path/to/project
BUILD_DIR=/data/build-nix/my-project-os2
meson setup "$BUILD_DIR" "$PROJECT_SOURCE" \
  --cross-file "$TOOLCHAIN_PREFIX/share/meson/cross/i686-pc-os2-emx-omf.txt"
meson compile -C "$BUILD_DIR" -j2
```

Use the `i686-pc-os2-emx-aout.txt` cross file instead when the project
requires a.out output.

### Autotools

Source the helper in the current shell, then configure in an out-of-tree
build directory:

```sh
PROJECT_SOURCE=/path/to/project
BUILD_DIR=/data/build-nix/my-project-os2
. "$TOOLCHAIN_PREFIX/i686-pc-os2-emx/bin/setemxenv"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
AR=i686-pc-os2-emx-emxomfar "$PROJECT_SOURCE/configure" \
  --host=i686-pc-os2-emx
make -j2
```

For OMF objects and archives, use `i686-pc-os2-emx-emxomfar`; a normal host
GNU `ar` does not create the required OMF archive format. The CMake and Meson
OMF cross files select the appropriate archiver for you.

## GCC sources and generated files

GCC's `intl` and `libiberty` directories are part of the GCC source checkout;
they are not separate Git submodules. `gettext`/`autopoint` are Linux host
build tools, not a reason to add a separate gettext source submodule. The
Makefile downloads and builds its libtool source in the build root. Keep
configure output, downloaded archives, generated `libtool` scripts, object
files, and generated `intl`/`libiberty` build files out of Git.

## Additional target libraries

The installed helper scripts can install supported Netlabs RPM or ZIP
packages into the target prefix. For example:

```sh
"$TOOLCHAIN_PREFIX/bin/installrpmzip" PACKAGE_NAME
"$TOOLCHAIN_PREFIX/bin/installrpm" PACKAGE_NAME
"$TOOLCHAIN_PREFIX/bin/installzip" https://example.invalid/library.zip
```

Use the real package name or URL. These helpers also accept local files; see
their usage output for optional destination and repository flags. Check that
any added library is target-compatible and provides OMF archives when needed;
host libraries cannot be used for OS/2 links.


