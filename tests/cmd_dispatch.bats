#!/usr/bin/env bats
load test_helper

# Verifies that every subcommand script accepts the Dokku 0.38 invocation
# convention: $1 is "shared-redis:<cmd>" and user args start at $2. The
# scripts all `shift` this prefix off before reading positional args.

setup() {
  setup_plugin_env
}

@test "create rejects empty name and points at the right cmd" {
  run "$REPO_ROOT/subcommands/create" "shared-redis:create"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"shared-redis:create"* ]]
}

@test "destroy requires -f and treats positional 1 as the tenant name" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  run "$REPO_ROOT/subcommands/destroy" "shared-redis:destroy" "demo"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"refusing to destroy"* ]]
  [[ "$output" != *"shared-redis:destroy"* || "$output" == *"-f"* ]]
}

@test "list runs cleanly with no tenants" {
  run "$REPO_ROOT/subcommands/list" "shared-redis:list"
  [[ "$status" -eq 0 ]]
}

@test "set-quota parses --mb and --keys flags" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  run "$REPO_ROOT/subcommands/set-quota" "shared-redis:set-quota" "demo" "--mb" "50" "--keys" "5000"
  [[ "$status" -eq 0 ]]
  [[ "$(<"$PLUGIN_DATA_ROOT/demo/QUOTA_MB")" == "50" ]]
  [[ "$(<"$PLUGIN_DATA_ROOT/demo/QUOTA_KEYS")" == "5000" ]]
}

@test "info errors when tenant is missing" {
  run "$REPO_ROOT/subcommands/info" "shared-redis:info" "ghost"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
}

@test "export errors with stretch-goal message and non-zero exit" {
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  run "$REPO_ROOT/subcommands/export" "shared-redis:export" "demo"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"v0.2 stretch goal"* ]]
}

@test "commands dispatcher routes unknown subcommand to error" {
  run "$REPO_ROOT/commands" "shared-redis:does-not-exist"
  [[ "$status" -ne 0 ]]
}
