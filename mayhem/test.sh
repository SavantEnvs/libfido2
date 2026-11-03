#!/usr/bin/env bash
#
# mayhem/test.sh — RUN upstream's regress suite (ctest, built by mayhem/build.sh) and the known-answer
# probe mayhem/kat.c. The regress binaries print nothing and assert internally, so the KAT output
# diff is what proves the library really executed (a no-op build fails it).
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

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

T="$SRC/build/tests"
[ -x "$T/kat" ] && [ -f "$T/CTestTestfile.cmake" ] || { echo "test runners missing — mayhem/build.sh must build them" >&2; exit 2; }

passed=0; failed=0

# 1) upstream regress suite
ct="$(cd "$T" && ctest --output-on-failure 2>&1)"; echo "$ct"
total="$(printf '%s\n' "$ct" | sed -n 's/.*tests passed, [0-9]* tests failed out of \([0-9]*\).*/\1/p')"
nfail="$(printf '%s\n' "$ct" | sed -n 's/.*tests passed, \([0-9]*\) tests failed out of.*/\1/p')"
if [ -z "$total" ] || [ -z "$nfail" ]; then
  failed=$((failed + 1))
else
  passed=$((passed + total - nfail)); failed=$((failed + nfail))
fi

# 2) known-answer probe, one test per output line
exp="$SRC/mayhem/kat.expected"
got="$("$T/kat" 2>&1)"
while IFS= read -r line; do
  if printf '%s\n' "$got" | grep -qxF -- "$line"; then passed=$((passed + 1))
  else echo "KAT mismatch: expected '$line'" >&2; failed=$((failed + 1)); fi
done < "$exp"

emit_ctrf "ctest+kat" "$passed" "$failed"
