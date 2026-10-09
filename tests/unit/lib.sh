#!/usr/bin/env bash
# Minimal assertion helpers for the unit tests (sourced, not executed).
# Usage: run <command...>, then assert_* on $status and $output, and call finish at the end.

failures=0

pass() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1"
  failures=$((failures + 1))
}

# Runs a command, storing its combined stdout and stderr in $output and its exit code in $status.
run() {
  if output=$("$@" 2>&1); then status=0; else status=$?; fi
}

assert_status() {
  if [[ $status == "$1" ]]; then pass "$2"; else fail "$2 (expected status $1, got $status; output: $output)"; fi
}

assert_output() {
  if [[ $output == "$1" ]]; then pass "$2"; else fail "$2 (expected output '$1', got '$output')"; fi
}

assert_contains() {
  if [[ $output == *"$1"* ]]; then pass "$2"; else fail "$2 (expected output to contain '$1', got '$output')"; fi
}

assert_not_contains() {
  if [[ $output != *"$1"* ]]; then pass "$2"; else fail "$2 (output must not contain '$1', got '$output')"; fi
}

finish() {
  if ((failures > 0)); then
    printf '%d failure(s)\n' "$failures"
    exit 1
  fi
}
