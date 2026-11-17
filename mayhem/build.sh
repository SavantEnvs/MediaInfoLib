#!/usr/bin/env bash
# mayhem/build.sh — build MediaInfoLib (sanitized + SanCov) and one libFuzzer target per line of
# mayhem/targets.txt, each with a -standalone reproducer; then a normal-flags build of the library
# plus mayhem/selftest.cpp for mayhem/test.sh. Re-runnable and offline: ZenLib comes prebuilt from
# /opt/toolchains/deps (Dockerfile), zlib from apt. Build trees live in mayhem/build/ (gitignored).
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${ZENLIB_PREFIX:=/opt/toolchains/deps/zenlib-0.4.41-2c5dfac}"
export CC CXX

cd "$SRC"
B="$SRC/mayhem/build"
mkdir -p "$B"

# Shared CMake settings: static lib, system zlib, ZenLib from deps, no libcurl (network URLs only).
common=(-S Project/CMake -DBUILD_SHARED_LIBS=OFF -DBUILD_ZENLIB=OFF -DBUILD_ZLIB=OFF
        -DCMAKE_PREFIX_PATH="$ZENLIB_PREFIX" -DCMAKE_DISABLE_FIND_PACKAGE_CURL=ON)
ZEN_INC="$ZENLIB_PREFIX/include"
ZEN_LIB="$ZENLIB_PREFIX/lib/libzen.a"
INC=(-I"$SRC/Source" -I"$ZEN_INC" -DUNICODE -D_UNICODE)
LIBS=(-lz -lpthread -ldl)

# 1) Fuzz build of the library: sanitizers + SanCov (fuzzer-no-link, unconditionally) + DWARF 3.
FUZZ_CFLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS -O1"
# The C files are only bundled ThirdParty code (tfsxml, gladman aes/sha/hmac, md5, base64). tfsxml
# computes `buf + len` with buf == NULL, len == 0 on every empty XML buffer (tfsxml.c:397), which
# UBSan's pointer-overflow check halts on before any parser runs, so that one check is relaxed for C
# sources only. Every other UBSan check, ASan, and pointer-overflow in the C++ parsers stay halting.
FUZZ_C_ONLY=""
case "$SANITIZER_FLAGS" in *undefined*) FUZZ_C_ONLY="-fno-sanitize=pointer-overflow" ;; esac
cmake "${common[@]}" -B "$B/fuzz" -DCMAKE_BUILD_TYPE=None \
  -DCMAKE_C_FLAGS="$FUZZ_CFLAGS $FUZZ_C_ONLY" -DCMAKE_CXX_FLAGS="$FUZZ_CFLAGS"
cmake --build "$B/fuzz" -j"$MAYHEM_JOBS" --target mediainfo
MILIB="$B/fuzz/libmediainfo.a"

# 2) Harness: one libFuzzer binary + one -standalone reproducer, named per target below.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$B/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c -x c "$STANDALONE_FUZZ_MAIN" -o "$B/standalone_main.o"
$CXX $FUZZ_CFLAGS -std=c++17 "${INC[@]}" -c "$SRC/mayhem/harnesses/fuzz_mediainfo.cpp" -o "$B/fuzz_mediainfo.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$B/fuzz_mediainfo.o" "$B/lsan_off.o" \
  "$MILIB" "$ZEN_LIB" "${LIBS[@]}" -o "$SRC/mediainfo_fuzz"
$CXX $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS "$B/fuzz_mediainfo.o" "$B/lsan_off.o" \
  "$B/standalone_main.o" "$MILIB" "$ZEN_LIB" "${LIBS[@]}" -o "$SRC/mediainfo_fuzz-standalone"
# Every target is the same binary under its own name (hardlinks; the harness reads argv[0]), so the
# image carries one 240 MB sanitized binary instead of forty.
while read -r name _; do
  case "$name" in ''|'#'*) continue ;; esac
  ln -f "$SRC/mediainfo_fuzz" "$SRC/$name"
  ln -f "$SRC/mediainfo_fuzz-standalone" "$SRC/$name-standalone"
done < "$SRC/mayhem/targets.txt"

# 3) Oracle build: the library with its normal (Release) flags, and the selftest driver.
cmake "${common[@]}" -B "$B/test" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS"
cmake --build "$B/test" -j"$MAYHEM_JOBS" --target mediainfo
$CXX -O2 -std=c++17 $COVERAGE_FLAGS "${INC[@]}" "$SRC/mayhem/selftest.cpp" \
  "$B/test/libmediainfo.a" "$ZEN_LIB" "${LIBS[@]}" -o "$B/mediainfo_selftest"
echo "build.sh: done"
