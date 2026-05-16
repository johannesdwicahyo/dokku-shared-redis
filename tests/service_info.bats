#!/usr/bin/env bats
load test_helper

setup() {
  setup_plugin_env
  source "$REPO_ROOT/config"
  source "$REPO_ROOT/functions"
  mkdir -p "$PLUGIN_DATA_ROOT/demo"
  printf 'pw' >"$PLUGIN_DATA_ROOT/demo/PASSWORD"
  : >"$PLUGIN_DATA_ROOT/demo/LINKS"
}

@test "service_info prints all fields including quota defaults" {
  stub_response docker '7 32768'
  run service_info "demo"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"name=demo"* ]]
  [[ "$output" == *"user=demo"* ]]
  [[ "$output" == *"key_prefix=demo:"* ]]
  [[ "$output" == *"host=dokku-shared-redis"* ]]
  [[ "$output" == *"port=6379"* ]]
  [[ "$output" == *"keys=7"* ]]
  [[ "$output" == *"memory_bytes=32768"* ]]
  [[ "$output" == *"quota_mb=25"* ]]
  [[ "$output" == *"quota_keys=10000"* ]]
  [[ "$output" == *"read_only=false"* ]]
}

@test "service_info reports read_only=true when marker is present" {
  : >"$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED"
  stub_response docker '0 0'
  run service_info "demo"
  [[ "$output" == *"read_only=true"* ]]
}

@test "service_info reports linked apps as csv" {
  printf 'app1\napp2\n' >"$PLUGIN_DATA_ROOT/demo/LINKS"
  stub_response docker '0 0'
  run service_info "demo"
  [[ "$output" == *"linked_apps=app1,app2"* ]]
}

@test "service_info errors when tenant is missing" {
  run service_info "ghost"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
}

@test "service_list lists tenants alphabetically and skips _internal" {
  mkdir -p "$PLUGIN_DATA_ROOT/zeta" "$PLUGIN_DATA_ROOT/alpha" "$PLUGIN_DATA_ROOT/_redisdata"
  run service_list
  [[ "$status" -eq 0 ]]
  lines=()
  while IFS= read -r l; do lines+=("$l"); done <<< "$output"
  [[ "${lines[0]}" == "alpha" ]]
  [[ "${lines[1]}" == "demo" ]]
  [[ "${lines[2]}" == "zeta" ]]
  for l in "${lines[@]}"; do
    [[ "$l" != "_redisdata" ]] || { echo "_redisdata leaked into list"; return 1; }
  done
}
