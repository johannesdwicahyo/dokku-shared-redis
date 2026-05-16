#!/usr/bin/env bats
load test_helper

setup() {
  setup_plugin_env
}

@test "subcommands/help prints usage with all planned subcommands" {
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

@test "subcommands/help works when invoked directly with cmd:sub as \$1 (Dokku 0.38 style)" {
  # Dokku 0.38+ invokes subcommand scripts as: subcommands/help shared-redis:help
  # The help script must not choke on this — it ignores args entirely.
  run "$REPO_ROOT/subcommands/help" "shared-redis:help"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"shared-redis:create"* ]]
}
