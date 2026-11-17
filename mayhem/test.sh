#!/usr/bin/env bash
# mayhem/test.sh — functional oracle: the normal-flags MediaInfoLib build (mayhem/build/mediainfo_selftest,
# made by build.sh) parses each committed sample in mayhem/testdata via MediaInfo::Open, and its
# metadata (format, size, dimensions, channels, sample rate, durations) must match the known values in
# mayhem/testdata/expected.txt. One test per sample file. Emits CTRF.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
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

BIN="$SRC/mayhem/build/mediainfo_selftest"
TD="$SRC/mayhem/testdata"
if [ ! -x "$BIN" ]; then
  echo "test.sh: $BIN missing — run mayhem/build.sh first" >&2
  emit_ctrf mediainfo-selftest 0 1
  exit 1
fi

passed=0 failed=0
for f in sample.png sample.wav sample.ttml; do
  want="$(grep "^$f|" "$TD/expected.txt")"
  got="$(cd "$TD" && "$BIN" "$f" 2>&1)"
  if [ -n "$want" ] && [ "$got" = "$want" ]; then
    echo "PASS $f"; passed=$((passed + 1))
  else
    echo "FAIL $f"; diff <(echo "$want") <(echo "$got") || true; failed=$((failed + 1))
  fi
done
emit_ctrf mediainfo-selftest "$passed" "$failed"
