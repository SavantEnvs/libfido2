#!/usr/bin/env bash
#
# mayhem/build.sh — build libfido2's ten OSS-Fuzz libFuzzer harnesses (fuzz/fuzz_*.c) plus the
# project's regress suite. Runs in the commit image as `mayhem` in /mayhem (see mayhem/Dockerfile).
#
# Layout (all under the gitignored upstream `build/` pattern, so `git clean -ffdX` resets it):
#   build/fuzz        libfido2 + harnesses, ASan+UBSan, linked with libFuzzer
#   build/standalone  same, linked with the run-once StandaloneFuzzTargetMain driver
#   build/tests       project regress suite + the KAT probe, NORMAL flags
# Outputs: /mayhem/<fuzzer> and /mayhem/<fuzzer>-standalone (RUNPATH points into build/).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# Patched libcbor for the fuzz builds, installed into the image by mayhem/Dockerfile.
: "${LIBCBOR_FUZZ:=/opt/libcbor-fuzz}"

HARNESSES="fuzz_assert fuzz_attobj fuzz_bio fuzz_cred fuzz_credman fuzz_hid fuzz_largeblob fuzz_mgmt fuzz_netlink fuzz_pcsc"
B="$SRC/build"
mkdir -p "$B"

# LeakSanitizer off, at build time, for every fuzz + standalone binary.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.c" -o "$B/lsan_off.o"
# The run-once driver as a C object (its LLVMFuzzerTestOneInput reference must keep C linkage).
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$B/standalone_main.o"

# The standalone link has no libFuzzer runtime, so give mutator_aux.c's LLVMFuzzerMutate() a stub.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/standalone_mutate.c" -o "$B/standalone_mutate.o"

# 1) + 2) FUZZ=ON builds: upstream's own recipe (fuzz/README, OSS-Fuzz build.sh). The library is
# compiled with fuzzer-no-link so its code carries coverage; the harness link flavour is FUZZ_LDFLAGS.
build_fuzz() { # <dir> <extra C flags> <FUZZ_LDFLAGS>
  cmake -S "$SRC" -B "$B/$1" \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $2" \
    -DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS $B/lsan_off.o" \
    -DCMAKE_SHARED_LINKER_FLAGS="$SANITIZER_FLAGS" \
    -DCMAKE_PREFIX_PATH="$LIBCBOR_FUZZ" -DPKG_CONFIG_USE_CMAKE_PREFIX_PATH=1 \
    -DCMAKE_BUILD_RPATH="$LIBCBOR_FUZZ/lib" \
    -DFUZZ=ON -DFUZZ_LDFLAGS="$3" \
    -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TOOLS=OFF -DBUILD_MANPAGES=OFF \
    -DBUILD_STATIC_LIBS=OFF -DBUILD_SHARED_LIBS=ON
  cmake --build "$B/$1" -j"$MAYHEM_JOBS"
}
build_fuzz fuzz "-fsanitize=fuzzer-no-link" "$LIB_FUZZING_ENGINE"
build_fuzz standalone "" "$B/standalone_main.o $B/standalone_mutate.o"

for h in $HARNESSES; do
  cp -f "$B/fuzz/fuzz/$h" "$SRC/$h"
  cp -f "$B/standalone/fuzz/$h" "$SRC/$h-standalone"
done

# 3) Regress suite + KAT probe with the project's NORMAL flags (an honest functional oracle).
cmake -S "$SRC" -B "$B/tests" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$COVERAGE_FLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$COVERAGE_FLAGS" \
  -DBUILD_TESTS=ON -DBUILD_EXAMPLES=OFF -DBUILD_TOOLS=OFF -DBUILD_MANPAGES=OFF \
  -DBUILD_STATIC_LIBS=ON -DBUILD_SHARED_LIBS=ON
cmake --build "$B/tests" -j"$MAYHEM_JOBS"
$CC -O2 $COVERAGE_FLAGS -I"$SRC/src" "$SRC/mayhem/kat.c" \
  -L"$B/tests/src" -lfido2 -Wl,-rpath,"$B/tests/src" -o "$B/tests/kat"
