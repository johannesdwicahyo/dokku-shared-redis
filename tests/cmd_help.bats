#!/usr/bin/env bats
load test_helper

setup() {
  setup_plugin_env
}

@test "subcommands/help prints usage with all subcommands" {
  run "$REPO_ROOT/subcommands/help" "shared-redis:help"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage: dokku shared-redis:"* ]]
  for cmd in create destroy link unlink list info connect set-quota unset-quota check-quotas export import help; do
    [[ "$output" == *"shared-redis:$cmd"* ]] || {
      echo "missing command in help output: $cmd"
      return 1
    }
  done
}

@test "commands dispatcher routes :help to subcommands/help" {
  run "$REPO_ROOT/commands" "shared-redis:help"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage: dokku shared-redis:"* ]]
}

@test "help mentions the key-prefix gotcha" {
  run "$REPO_ROOT/subcommands/help" "shared-redis:help"
  [[ "$output" == *"<name>:*"* ]]
  [[ "$output" == *"NOPERM"* ]]
}
