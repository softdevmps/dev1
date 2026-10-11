#!/bin/sh
# Optional user-mode build; does not build or validate a WDK kernel driver.
set -eu
cd "$(dirname "$0")/.."
mkdir -p out/cross
set --
if [ -n "${MINGW_ROOT:-}" ]; then
    set -- "-B$MINGW_ROOT/usr/bin/" -isystem "$MINGW_ROOT/usr/share/mingw-w64/include"
fi
"${MINGW_CC:-x86_64-w64-mingw32-gcc}" "$@" \
    -std=c11 -Wall -Wextra -Wconversion -Werror -O2 -municode -static \
    -Wl,--dynamicbase,--nxcompat,--high-entropy-va \
    checker/checker.c shared/descriptor.c -o out/cross/Checker.exe
