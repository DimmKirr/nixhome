#!/usr/bin/env bash
# Build and run the VHE core unit tests.
set -euo pipefail
cd "$(dirname "$0")"
cc -std=gnu11 -Wall -Wextra -Werror -o /tmp/test_vhe_core \
    test_vhe_core.c vhe_core.c
/tmp/test_vhe_core
