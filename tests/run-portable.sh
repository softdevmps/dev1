#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p out/portable
"${CC:-cc}" -std=c11 -Wall -Wextra -Wconversion -Werror -g -O1 \
    -fsanitize=address,undefined -fno-omit-frame-pointer \
    shared/descriptor.c tests/descriptor_tests.c -o out/portable/descriptor_tests
ASAN_OPTIONS=detect_leaks=1 ./out/portable/descriptor_tests
"${CC:-cc}" -std=c11 -Wall -Wextra -Wconversion -Werror -g -O1 \
    -fsanitize=address,undefined -fno-omit-frame-pointer \
    shared/descriptor.c shared/transform.c tests/transform_tests.c -o out/portable/transform_tests
ASAN_OPTIONS=detect_leaks=1 ./out/portable/transform_tests
python3 tests/validate_project.py
