#!/usr/bin/env bats
load test_helper

setup() {
  setup_plugin_env
  source "$REPO_ROOT/config"
  source "$REPO_ROOT/functions"
  # Pretend the container is already running so ensure_shared_container short-circuits.
  stub_response docker 'dokku-shared-redis'
}

@test "service_create writes metadata files" {
  service_create "demo"
  [[ -f "$PLUGIN_DATA_ROOT/demo/PASSWORD" ]]
  [[ -f "$PLUGIN_DATA_ROOT/demo/LINKS" ]]
  pw="$(<"$PLUGIN_DATA_ROOT/demo/PASSWORD")"
  [[ "${#pw}" -eq 32 ]]
}

@test "service_create issues ACL SETUSER scoped to the tenant prefix" {
  service_create "demo"
  acl_calls=()
  while IFS= read -r line; do acl_calls+=("$line"); done < <(grep '^docker exec.*ACL' "$STUB_LOG")
  [[ "${acl_calls[0]}" == *"ACL SETUSER demo on"* ]]
  [[ "${acl_calls[0]}" == *"~demo:*"* ]]
  [[ "${acl_calls[0]}" == *"+@all"* ]]
  [[ "${acl_calls[1]}" == *"ACL SAVE"* ]]
}

@test "service_create refuses an existing tenant" {
  service_create "demo"
  run service_create "demo"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"already exists"* ]]
}

@test "service_create rejects invalid name" {
  run service_create "BadName"
  [[ "$status" -ne 0 ]]
  run service_create ""
  [[ "$status" -ne 0 ]]
  run service_create "with spaces"
  [[ "$status" -ne 0 ]]
}

@test "service_destroy issues purge + ACL DELUSER and removes data dir" {
  service_create "demo"
  : >"$STUB_LOG"
  service_destroy "demo"
  [[ ! -d "$PLUGIN_DATA_ROOT/demo" ]]
  # Purge runs an EVAL targeting demo:* before DELUSER fires.
  run grep -c 'docker exec.*EVAL.*demo:\*' "$STUB_LOG"
  [[ "$output" -ge 1 ]]
  run grep -c 'docker exec.*ACL DELUSER demo' "$STUB_LOG"
  [[ "$output" -ge 1 ]]
}

@test "service_destroy is idempotent when tenant is missing" {
  run service_destroy "ghost"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
}

@test "service_dsn includes username, password, host, port, db" {
  service_create "demo"
  run service_dsn "demo"
  [[ "$status" -eq 0 ]]
  pw="$(<"$PLUGIN_DATA_ROOT/demo/PASSWORD")"
  [[ "$output" == "redis://demo:${pw}@dokku-shared-redis:6379/0" ]]
}
