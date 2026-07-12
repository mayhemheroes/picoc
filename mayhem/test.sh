#!/usr/bin/env bash
#
# mayhem/test.sh — run picoc's OWN upstream test suite (already built by mayhem/build.sh).
#
# Upstream's `make test` runs three golden-output suites via tests/Makefile:
#   * the numbered tests   (tests/Makefile        TESTS)
#   * the csmith suite     (tests/csmith/Makefile CSMITH_TESTS)
#   * the jpoirier suite   (tests/jpoirier/Makefile JPOIRIER_TESTS)
# Each test runs `../picoc <case>.c` (with the same args/-s special cases as the
# upstream %.test rule) and diffs stdout against the checked-in .expect golden file
# (`diff -qbu`, exactly as upstream). Upstream's make rule aborts the whole run at
# the FIRST failing case; this runner executes the identical per-case recipe for
# EVERY listed case so it can report full pass/fail counts as CTRF.
# Golden-output diffs assert real interpreter behavior — a sabotaged `exit(0)` picoc
# emits nothing and fails every case.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

PICOC="$SRC/picoc"
[ -x "$PICOC" ] || { echo "FATAL: $PICOC missing — mayhem/build.sh must build it" >&2; emit_ctrf picoc-tests 0 1; exit 1; }

cd tests

# The authoritative case lists, extracted from the same Makefiles `make test` uses.
mapfile -t CASES < <(
  { grep -oE '(^[A-Z_]+=[[:space:]]*|^[[:space:]]+)[0-9A-Za-z_]+\.test' Makefile
    grep -oE 'csmith/[0-9A-Za-z_]+\.test' csmith/Makefile
    grep -oE 'jpoirier/[0-9A-Za-z_]+\.test' jpoirier/Makefile
  } | sed 's/^[A-Z_]*=//; s/^[[:space:]]*//; s/\.test$//' | sort -u
)

passed=0; failed=0
for t in "${CASES[@]}"; do
  out="$t.output"
  # Same invocation matrix as the upstream %.test rule (stdout is what's compared).
  if [[ "$t" == *args* ]]; then
    "$PICOC" "$t.c" - arg1 arg2 arg3 arg4 >"$out" 2>/dev/null
  elif [[ "$t" == *script* ]]; then
    "$PICOC" -s "$t.c" >"$out" 2>/dev/null
  else
    "$PICOC" "$t.c" >"$out" 2>/dev/null
  fi
  if diff -qbu "$t.expect" "$out" >/dev/null 2>&1; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); echo "FAIL: $t"; diff -bu "$t.expect" "$out" | head -20
  fi
  rm -f "$out"
done

cd "$SRC"
echo "picoc upstream suite: $passed passed, $failed failed of ${#CASES[@]}"
emit_ctrf picoc-tests "$passed" "$failed" 0
