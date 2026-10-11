#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p out/portable
"${CC:-cc}" -std=c11 -Wall -Wextra -Wconversion -Werror -g -O1 \
    -fsanitize=address,undefined -fno-omit-frame-pointer \
    shared/descriptor.c tests/descriptor_tests.c -o out/portable/descriptor_tests
ASAN_OPTIONS=detect_leaks=1 ./out/portable/descriptor_tests
python3 tests/validate_project.py
