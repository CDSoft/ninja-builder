#!/bin/bash

# This file is part of ninja-builder.
#
# ninja-builder is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ninja-builder is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ninja-builder.  If not, see <https://www.gnu.org/licenses/>.
#
# For further information about ninja-builder you can visit
# https://codeberg.org/cdsoft/ninja-builder

# Minimal script to cross-compile Ninja with zig

set -eu

RELEASE=2025-06-18

ZIG_VERSION=0.14.1
ZIG_PATH=~/.local/opt/zig
ZIG=$ZIG_PATH/$ZIG_VERSION/zig

NINJA_VERSION=1.13.0
NINJA_URL=https://github.com/ninja-build/ninja/archive/refs/tags/v$NINJA_VERSION.tar.gz
NINJA_REPO=ninja-$NINJA_VERSION

: "${PREFIX:=$HOME/.local}"

BUILD_ROOT=.build

CLEAN=false
INSTALL=false
COMPILER=gcc
COMPILER_VERSION=X
for arg in "$@"
do
    case "$arg" in
        clean)      CLEAN=true ;;
        install)    INSTALL=true ;;
        gcc)        COMPILER=gcc ;;
        clang)      COMPILER=clang ;;
        zig)        COMPILER=zig ;;
        *)          echo "invalid parameter: $arg"
                    exit 1
                    ;;
    esac
done
case $COMPILER in
    gcc)    COMPILER_VERSION=$(gcc --version | awk '{print $3; exit}') ;;
    clang)  COMPILER_VERSION=$(clang --version | awk '{print $3; exit}') ;;
    zig)    COMPILER_VERSION=$ZIG_VERSION ;;
esac

BUILD=$BUILD_ROOT/ninja-$NINJA_VERSION-$COMPILER-$COMPILER_VERSION

SOURCES=(
    "$NINJA_REPO"/src/build.cc
    "$NINJA_REPO"/src/build_log.cc
    "$NINJA_REPO"/src/clean.cc
    "$NINJA_REPO"/src/clparser.cc
    "$NINJA_REPO"/src/debug_flags.cc
    "$NINJA_REPO"/src/depfile_parser.cc
    "$NINJA_REPO"/src/deps_log.cc
    "$NINJA_REPO"/src/disk_interface.cc
    "$NINJA_REPO"/src/dyndep.cc
    "$NINJA_REPO"/src/dyndep_parser.cc
    "$NINJA_REPO"/src/edit_distance.cc
    "$NINJA_REPO"/src/elide_middle.cc
    "$NINJA_REPO"/src/eval_env.cc
    "$NINJA_REPO"/src/graph.cc
    "$NINJA_REPO"/src/graphviz.cc
    "$NINJA_REPO"/src/jobserver.cc
    "$NINJA_REPO"/src/json.cc
    "$NINJA_REPO"/src/lexer.cc
    "$NINJA_REPO"/src/line_printer.cc
    "$NINJA_REPO"/src/manifest_parser.cc
    "$NINJA_REPO"/src/metrics.cc
    "$NINJA_REPO"/src/missing_deps.cc
    "$NINJA_REPO"/src/ninja.cc
    "$NINJA_REPO"/src/parser.cc
    "$NINJA_REPO"/src/real_command_runner.cc
    "$NINJA_REPO"/src/state.cc
    "$NINJA_REPO"/src/status_printer.cc
    "$NINJA_REPO"/src/string_piece_util.cc
    "$NINJA_REPO"/src/util.cc
    "$NINJA_REPO"/src/version.cc
)
WIN32_SOURCES=(
    "$NINJA_REPO"/src/includes_normalize-win32.cc
    "$NINJA_REPO"/src/jobserver-win32.cc
    "$NINJA_REPO"/src/minidump-win32.cc
    "$NINJA_REPO"/src/msvc_helper-win32.cc
    "$NINJA_REPO"/src/msvc_helper_main-win32.cc
    "$NINJA_REPO"/src/subprocess-win32.cc
)
POSIX_SOURCES=(
    "$NINJA_REPO"/src/jobserver-posix.cc
    "$NINJA_REPO"/src/subprocess-posix.cc
)

CFLAGS=(
    -Wno-deprecated
    -Wno-missing-field-initializers
    -Wno-unused-parameter
    -Wno-inconsistent-missing-override
    -fno-rtti
    -fno-exceptions
    -std=c++17
    -fvisibility=hidden
    -pipe
    -O2
    -fdiagnostics-color
    -s
    -DNDEBUG
)
case $COMPILER in
    gcc)    CFLAGS+=( -Wno-alloc-size-larger-than ) ;;
esac

WIN32_CFLAGS=(
    #-D_WIN32_WINNT=0x0601
    -D__USE_MINGW_ANSI_STDIO=1
    -DUSE_PPOLL
    -flto=auto
)

POSIX_CFLAGS=(
    -fvisibility=hidden
    -pipe
    -Wno-dll-attribute-on-redeclaration
)

LINUX_CFLAGS=(
    -DUSE_PPOLL
    -flto=auto
)

MACOS_CFLAGS=(
)

found()
{
    hash "$@" 2>/dev/null
}

download()
{
    local URL="$1"
    local OUTPUT="$2"
    echo "Downloading $URL"
    if ! found curl
    then
        echo "ERROR: curl not found"
        exit 1
    fi
    curl -L "$URL" -o "$OUTPUT" --progress-bar --fail
}

detect_os()
{
    ARCH="$(uname -m)"
    case "$ARCH" in
        (arm64) ARCH=aarch64 ;;
    esac

    case "$(uname -s)" in
        (Linux)  OS=linux ;;
        (Darwin) OS=macos ;;
        (MINGW*) OS=windows;;
        (*)      OS=unknown ;;
    esac
}

install_zig()
{
    [ -x "$ZIG" ] && return

    local ZIG_ARCHIVE="zig-$ARCH-$OS-$ZIG_VERSION.tar.xz"
    local ZIG_URL="https://ziglang.org/download/$ZIG_VERSION/$ZIG_ARCHIVE"

    mkdir -p "$(dirname "$ZIG")"
    download "$ZIG_URL" "$(dirname "$ZIG")/$ZIG_ARCHIVE"

    tar xJf "$(dirname "$ZIG")/$ZIG_ARCHIVE" -C "$(dirname "$ZIG")" --strip-components 1
    rm "$(dirname "$ZIG")/$ZIG_ARCHIVE"
}

clone_ninja()
{
    [ -d "$NINJA_REPO" ] && return
    [ -f "$BUILD/ninja-$NINJA_VERSION.tar.gz" ] || download $NINJA_URL "$BUILD/ninja-$NINJA_VERSION.tar.gz"
    tar xzf "$BUILD/ninja-$NINJA_VERSION.tar.gz" "$NINJA_REPO/src/*" "$NINJA_REPO/COPYING" "$NINJA_REPO/README.md"
}

compile()
{
    local COMPILER="$1"
    local TARGET="$2"
    local OUTPUT
    OUTPUT="ninja-build-$RELEASE-$TARGET"
    local TARGET_CFLAGS=( "${CFLAGS[@]}" )
    local TARGET_SOURCES=( "${SOURCES[@]}" )
    case "$TARGET" in
        (*windows*) TARGET_CFLAGS+=( "${WIN32_CFLAGS[@]}" )
                    TARGET_SOURCES+=( "${WIN32_SOURCES[@]}" )
                    EXT=".exe"
                    ;;
        (*linux*)   TARGET_CFLAGS+=( "${POSIX_CFLAGS[@]}" "${LINUX_CFLAGS[@]}" )
                    TARGET_SOURCES+=( "${POSIX_SOURCES[@]}" )
                    EXT=""
                    ;;
        (*macos*)   TARGET_CFLAGS+=( "${POSIX_CFLAGS[@]}" "${MACOS_CFLAGS[@]}" )
                    TARGET_SOURCES+=( "${POSIX_SOURCES[@]}" )
                    EXT=""
                    ;;
    esac
    if ! [ -f "$BUILD/$OUTPUT.tar.gz" ] || [ ninja-builder.sh -nt "$BUILD/$OUTPUT.tar.gz" ]
    then
        echo "Compile Ninja for $TARGET with $COMPILER"
        mkdir -p "$BUILD/$OUTPUT"
        $COMPILER "${TARGET_CFLAGS[@]}" "${TARGET_SOURCES[@]}" -o "$BUILD/$OUTPUT/ninja$EXT"
        tar czf "$BUILD/$OUTPUT.tar.gz" "$BUILD/$OUTPUT/ninja$EXT" --transform="s,$BUILD/$OUTPUT/,,"
        cat <<EOF > "$BUILD/README.md"
# Ninja $RELEASE

| Program | Version | Documentation |
| ------- | ------- | ------------- |
| Ninja | [$NINJA_VERSION]($NINJA_URL) | <https://ninja-build.org/> |
EOF
    fi
}

$CLEAN && rm -rf $BUILD_ROOT
mkdir -p "$BUILD"
detect_os
clone_ninja

case "$COMPILER" in
    gcc)
        compile g++ "$OS-$ARCH"
        ;;
    clang)
        compile clang++ "$OS-$ARCH"
        ;;
    zig)
        install_zig
        compile "$ZIG c++ -target x86_64-linux-gnu"    linux-x86_64        &
        compile "$ZIG c++ -target x86_64-linux-musl"   linux-x86_64-musl   &
        compile "$ZIG c++ -target aarch64-linux-gnu"   linux-aarch64       &
        compile "$ZIG c++ -target aarch64-linux-musl"  linux-aarch64-musl  &
        compile "$ZIG c++ -target x86_64-macos-none"   macos-x86_64        &
        compile "$ZIG c++ -target aarch64-macos-none"  macos-aarch64       &
        compile "$ZIG c++ -target x86_64-windows-gnu"  windows-x86_64      &
        compile "$ZIG c++ -target aarch64-windows-gnu" windows-aarch64     &
        wait
        ;;
esac

if $INSTALL
then
    install -v -D -t "$PREFIX/bin" "$BUILD"/"ninja-build-$RELEASE-$OS-$ARCH"/ninja*
fi
