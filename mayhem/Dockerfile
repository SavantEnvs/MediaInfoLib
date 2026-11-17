# syntax=docker/dockerfile:1.7
# Commit image for MediaInfoLib (SPEC §3.1): org base + ZenLib (pinned, prebuilt under
# /opt/toolchains/deps) + mayhem/build.sh (sanitized library + 20 libFuzzer targets + oracle build).
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

# ZenLib: MediaInfoLib's required support library (MediaArea), not packaged at a matching version
# and not vendored upstream. Pinned by commit + sha256, built static and uninstrumented with
# DWARF 3 out of tree from $d/src (SPEC §6.2 item 19).
USER root
ARG ZENLIB_COMMIT=2c5dfac57cc27817206d7402a3122bf0b15c300d
ARG ZENLIB_SHA256=4094b6a4c5119c48e17fdfce58bf05c6d2d8833016074604bb63b51d051e4365
RUN d=/opt/toolchains/deps/zenlib-0.4.41-2c5dfac && mkdir -p "$d/src" /tmp/dep-build \
 && curl -fsSL -o /tmp/dep.tgz https://codeload.github.com/MediaArea/ZenLib/tar.gz/${ZENLIB_COMMIT} \
 && echo "${ZENLIB_SHA256}  /tmp/dep.tgz" | sha256sum -c - \
 && tar -xzf /tmp/dep.tgz --strip-components=1 -C "$d/src" \
 && cmake -S "$d/src/Project/CMake" -B /tmp/dep-build -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_BUILD_TYPE=None -DCMAKE_INSTALL_PREFIX="$d" -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_C_FLAGS="-O2 -g -gdwarf-3" -DCMAKE_CXX_FLAGS="-O2 -g -gdwarf-3" \
 && cmake --build /tmp/dep-build -j"$(nproc)" && cmake --install /tmp/dep-build \
 && rm -rf /tmp/dep-build /tmp/dep.tgz && chmod -R a+rX,a-w "$d"

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
