#!/usr/bin/env bash
# Sourced by every .bats file via `load test_helper`.

setup_plugin_env() {
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  export REPO_ROOT

  # Sandbox PLUGIN_DATA_ROOT into the per-test tmpdir.
  export PLUGIN_DATA_ROOT="$BATS_TEST_TMPDIR/data"
  mkdir -p "$PLUGIN_DATA_ROOT"

  # Stub bin must come first if/when tests stub out docker/redis-cli.
  export PATH="$REPO_ROOT/tests/bin:$PATH"

  # Stub I/O channels (reserved for future tests that mock docker).
  export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  export STUB_RESPONSES_DIR="$BATS_TEST_TMPDIR/stub_responses"
  mkdir -p "$STUB_RESPONSES_DIR"
  : >"$STUB_LOG"

  # Make admin password lookup succeed by default.
  printf 'admin-pw\n' >"$BATS_TEST_TMPDIR/data/.admin_password"
  chmod 600 "$BATS_TEST_TMPDIR/data/.admin_password"
}
