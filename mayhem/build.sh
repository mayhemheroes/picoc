#!/usr/bin/env bash
#
# mayhem/build.sh — build the picoc fuzz target + the upstream test-suite binary.
#
#   fuzz_picoc             sanitized + libFuzzer   -> target `picoc` (in-process interpreter fuzzer)
#   fuzz_picoc-standalone  sanitized + file-driver -> standalone reproducer (runs one input file)
#   picoc                  normal flags (make)     -> upstream CLI, used by mayhem/test.sh to run
#                                                     the project's own golden-output test suite
#
# The fork's original Mayhem target ran the CLI over a file (`/picoc @@`). The libFuzzer
# harness (mayhem/fuzz_picoc.c) drives the SAME code path in-process — scan the source,
# then call main(), exactly what `picoc <file.c>` does — for dense in-process coverage.
# picoc is plain C with no configure step; the whole interpreter is compiled in one
# clang invocation (same TU set as upstream's Makefile, minus the CLI driver picoc.c,
# which defines main()). No network, no upstream edits — re-runnable and air-gapped
# (libreadline-dev is baked into the image by mayhem/Dockerfile).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "${SRC:-/mayhem}"

# The interpreter: upstream Makefile's SRCS minus picoc.c (the CLI main(), replaced by
# the fuzz driver). -I. so mayhem/fuzz_picoc.c finds picoc.h at the repo root.
LIB=(table.c lex.c parse.c expression.c heap.c type.c variable.c clibrary.c
     platform.c include.c debug.c
     platform/platform_unix.c platform/library_unix.c
     cstdlib/stdio.c cstdlib/math.c cstdlib/string.c cstdlib/stdlib.c
     cstdlib/time.c cstdlib/errno.c cstdlib/ctype.c cstdlib/stdbool.c
     cstdlib/unistd.c)
DEFS="-DUNIX_HOST -I."
LIBS="-lm -lreadline"   # platform.h force-defines USE_READLINE for UNIX_HOST

# picoc is a C INTERPRETER, so signed shifts / signed overflow are inherent to both its
# own string-table hash (table.c: `Hash ^= *Key++ << Offset`, shifts a char up to 25 bits)
# and to the C arithmetic it EXECUTES on behalf of the fuzzed program. Under halting UBSan
# these fire on essentially every input (the hash runs during PicocInitialize), which would
# make the harness "crash" at startup and report meaningless UB rather than real interpreter
# bugs. Likewise picoc's bump allocator packs `union AnyValue` cells unaligned BY DESIGN
# (expression.c fires `alignment` even on upstream's own passing tests — harmless on x86).
# Drop ONLY those pervasive-by-design classes; ASan (memory safety) and the rest of UBSan
# (null/OOB/vla-bound/divide/bool/enum, etc. — which DO flag real picoc defects) stay on.
UBSAN_RELAX="-fno-sanitize=shift,signed-integer-overflow,alignment"

# 1) libFuzzer target (sanitized, instrumented) — single compile+link, leaves no .o in-tree.
# shellcheck disable=SC2086
$CC $DEFS $SANITIZER_FLAGS $UBSAN_RELAX $DEBUG_FLAGS $LIB_FUZZING_ENGINE -w \
    mayhem/fuzz_picoc.c "${LIB[@]}" $LIBS -o fuzz_picoc

# 2) Standalone reproducer (same harness + file-input main) for triage outside Mayhem.
# shellcheck disable=SC2086
$CC $DEFS $SANITIZER_FLAGS $UBSAN_RELAX $DEBUG_FLAGS -w \
    "$STANDALONE_FUZZ_MAIN" mayhem/fuzz_picoc.c "${LIB[@]}" $LIBS -o fuzz_picoc-standalone

# 3) Upstream CLI with the project's NORMAL flags (no sanitizers/fuzzer) — the honest
#    oracle binary mayhem/test.sh runs the upstream golden-output suite against.
make -s -j"$MAYHEM_JOBS" CC="$CC" CFLAGS="-O2 -w $COVERAGE_FLAGS -std=gnu11 -pedantic -DUNIX_HOST" LIBS="$LIBS"

echo "build.sh: built fuzz_picoc, fuzz_picoc-standalone and ./picoc (test-suite oracle)"
