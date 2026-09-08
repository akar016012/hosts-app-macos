#!/bin/bash
# Standalone runner for Core unit tests and isolated store/helper write tests.
#
# The tests use a lightweight custom harness compiled directly with swiftc:
# we compile the relevant Core .swift files together with the Tests/ sources into
# separate executables with their own entry points. The app's @main in
# HostsEditor.swift is deliberately NOT included (it would clash with our main).
set -e
cd "$(dirname "$0")/.."

BUILD_DIR=".build-test"
BIN="$BUILD_DIR/hosts-tests"

# Only the Core files the tests actually exercise — kept minimal so we don't drag
# in SwiftUI/AppKit-dependent sources (HostsStore, HelperClient, etc.).
CORE_SOURCES=(
  etc-hosts/Core/AutoLockPreferences.swift
  etc-hosts/Core/HostsParser.swift
  etc-hosts/Core/HostsModel.swift
  etc-hosts/Core/HostsHistory.swift
  etc-hosts/Core/HostsDiff.swift
  etc-hosts/Core/PinStore.swift
)
TEST_SOURCES=(
  Tests/TestRunner.swift
  Tests/Helpers.swift
  Tests/main.swift
)

echo "→ Cleaning $BUILD_DIR…"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "→ Compiling tests…"
swiftc -O "${CORE_SOURCES[@]}" "${TEST_SOURCES[@]}" -o "$BIN"

echo "→ Running tests (under throwaway HOME)…"
# PinStore and HistoryStore derive their paths from NSHomeDirectory(). On macOS
# NSHomeDirectory() IGNORES the HOME env var (it reads getpwuid), but it DOES
# honor CFFIXED_USER_HOME — so we MUST set that to redirect file I/O to a temp
# dir. Setting HOME too keeps any plain getenv("HOME") callers consistent.
# Without CFFIXED_USER_HOME the tests would clobber the real
# ~/Library/Application Support/HostsEditor (pin.json, history.json).
TEST_HOME="$(mktemp -d)"
set +e
HOME="$TEST_HOME" CFFIXED_USER_HOME="$TEST_HOME" "$BIN"
status=$?
set -e

# Best-effort cleanup of the throwaway HOME.
rm -rf "$TEST_HOME"

if [ "$status" -ne 0 ]; then exit "$status"; fi

echo "→ Compiling write-safety regression tests…"
swiftc -O -parse-as-library \
  "${CORE_SOURCES[@]}" \
  etc-hosts/Core/HostsStore.swift etc-hosts/Core/SchemeStore.swift \
  HostsHelper/HostsFileWriter.swift Tests/TestRunner.swift \
  Tests/WriteSafety/Stubs.swift Tests/WriteSafety/main.swift \
  -o "$BUILD_DIR/write-safety-tests"
WRITE_TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/hosts-write-tests.XXXXXX")"
set +e
CFFIXED_USER_HOME="$WRITE_TEST_HOME" "$BUILD_DIR/write-safety-tests"
status=$?
set -e
rm -rf "$WRITE_TEST_HOME"
exit $status
