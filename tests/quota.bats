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

@test "service_get_quota_mb returns default when no override" {
  run service_get_quota_mb "demo"
  [[ "$output" == "25" ]]
}

@test "service_get_quota_keys returns default when no override" {
  run service_get_quota_keys "demo"
  [[ "$output" == "10000" ]]
}

@test "service_set_quota writes both files when both flags provided" {
  service_set_quota "demo" "50" "20000"
  [[ "$(<"$PLUGIN_DATA_ROOT/demo/QUOTA_MB")" == "50" ]]
  [[ "$(<"$PLUGIN_DATA_ROOT/demo/QUOTA_KEYS")" == "20000" ]]
}

@test "service_set_quota writes only what was provided" {
  service_set_quota "demo" "50" ""
  [[ "$(<"$PLUGIN_DATA_ROOT/demo/QUOTA_MB")" == "50" ]]
  [[ ! -f "$PLUGIN_DATA_ROOT/demo/QUOTA_KEYS" ]]
  service_set_quota "demo" "" "5000"
  [[ "$(<"$PLUGIN_DATA_ROOT/demo/QUOTA_KEYS")" == "5000" ]]
}

@test "service_set_quota rejects nothing-provided" {
  run service_set_quota "demo" "" ""
  [[ "$status" -ne 0 ]]
}

@test "service_set_quota rejects non-numeric / zero / negative" {
  run service_set_quota "demo" "huge" ""
  [[ "$status" -ne 0 ]]
  run service_set_quota "demo" "0" ""
  [[ "$status" -ne 0 ]]
  run service_set_quota "demo" "-5" ""
  [[ "$status" -ne 0 ]]
  run service_set_quota "demo" "" "0"
  [[ "$status" -ne 0 ]]
}

@test "service_unset_quota removes both override files" {
  printf '50'    >"$PLUGIN_DATA_ROOT/demo/QUOTA_MB"
  printf '5000' >"$PLUGIN_DATA_ROOT/demo/QUOTA_KEYS"
  service_unset_quota "demo"
  [[ ! -f "$PLUGIN_DATA_ROOT/demo/QUOTA_MB" ]]
  [[ ! -f "$PLUGIN_DATA_ROOT/demo/QUOTA_KEYS" ]]
}

@test "service_check_quota flips read-only when over memory cap" {
  printf '1' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MB"
  # tenant_usage stub: "<keys> <bytes>" — way over 1 MB
  stub_response docker '0 2097152'
  # ACL SETUSER + ACL SAVE
  stub_response docker ''
  stub_response docker ''
  run service_check_quota "demo"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"flipped"* ]]
  [[ -f "$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED" ]]
  run grep -c 'ACL SETUSER demo nocommands +@read' "$STUB_LOG"
  [[ "$output" -ge 1 ]]
}

@test "service_check_quota flips read-only when over key-count cap" {
  printf '5' >"$PLUGIN_DATA_ROOT/demo/QUOTA_KEYS"
  # Under memory but over key count.
  stub_response docker '10 1024'
  stub_response docker ''
  stub_response docker ''
  run service_check_quota "demo"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"flipped"* ]]
  [[ -f "$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED" ]]
}

@test "service_check_quota releases when back under both caps" {
  printf '10' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MB"
  : >"$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED"
  stub_response docker '5 524288'
  stub_response docker ''
  stub_response docker ''
  run service_check_quota "demo"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"released"* ]]
  [[ ! -f "$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED" ]]
  run grep -c 'ACL SETUSER demo allcommands' "$STUB_LOG"
  [[ "$output" -ge 1 ]]
}

@test "service_check_quota is silent when over cap and already enforced" {
  printf '1' >"$PLUGIN_DATA_ROOT/demo/QUOTA_MB"
  : >"$PLUGIN_DATA_ROOT/demo/QUOTA_VIOLATED"
  stub_response docker '0 2097152'
  run service_check_quota "demo"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
  run grep -c 'ACL SETUSER' "$STUB_LOG"
  [[ "$output" == "0" ]]
}

@test "service_check_quota is silent when under cap and not flagged" {
  stub_response docker '5 524288'
  run service_check_quota "demo"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}
