#!/bin/bash
# Standalone unit-test runner for the pure-logic Core sources.
#
# The app is built directly with swiftc (no SwiftPM/Xcode), so the tests are too:
# we compile the relevant Core .swift files together with the Tests/ sources into
# a single executable that has its own main.swift entry point. The app's @main in
# HostsEditor.swift is deliberately NOT included (it would clash with our main).
set -e
cd "$(dirname "$0")"

BUILD_DIR=".build-test"
BIN="$BUILD_DIR/hosts-tests"

# Only the Core files the tests actually exercise — kept minimal so we don't drag
# in SwiftUI/AppKit-dependent sources (HostsStore, HelperClient, etc.).
CORE_SOURCES=(
  Core/HostsParser.swift
  Core/HostsModel.swift
  Core/HostsHistory.swift
  Core/PinStore.swift
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

exit $status
