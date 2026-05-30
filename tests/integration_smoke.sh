#!/usr/bin/env bash
#
# Integration smoke for shared-redis. Run on a real Dokku host after
# installing the plugin. Not invoked by CI — local bats stubs can't catch
# the failure modes this script exists to verify (perms, ACL persistence,
# docker-network DNS, Dokku 0.38 dispatch).
#
# Usage:
#   ssh root@my-dokku-host 'bash -s' < tests/integration_smoke.sh
# or run directly on the host as root.

set -euo pipefail

TENANT="${TENANT:-smoke$(date +%s)}"
TENANT2="${TENANT2:-smoke$(date +%s)b}"
APP="${APP:-smokeapp$(date +%s)}"

step() { printf '\n=== %s ===\n' "$1"; }

cleanup() {
  set +e
  step "cleanup"
  sudo -u dokku dokku apps:destroy "$APP" --force 2>/dev/null || true
  sudo -u dokku dokku shared-redis:destroy "$TENANT" -f  2>/dev/null || true
  sudo -u dokku dokku shared-redis:destroy "$TENANT2" -f 2>/dev/null || true
}
trap cleanup EXIT

step "1. plugin installed and dispatcher responds"
sudo -u dokku dokku shared-redis:help | grep -q "create <name>" \
  || { echo "FAIL: :help output missing 'create <name>'"; exit 1; }

step "2. data dir is dokku-owned"
ls -ld /var/lib/dokku/services/shared-redis | awk '{print "  perm/owner:", $1, $3, $4}'
[[ "$(stat -c '%U:%G' /var/lib/dokku/services/shared-redis)" == "dokku:dokku" ]] \
  || { echo "FAIL: data dir not owned by dokku:dokku"; exit 1; }

step "3. shared container is up"
docker ps --filter "name=^dokku-shared-redis$" --format '{{.Names}} {{.Status}}' | grep -q dokku-shared-redis \
  || { echo "FAIL: shared container not running"; exit 1; }

step "4. create tenant '$TENANT' via the dokku user"
sudo -u dokku dokku shared-redis:create "$TENANT" | tee /tmp/.smoke-dsn
grep -q "redis://${TENANT}:" /tmp/.smoke-dsn \
  || { echo "FAIL: DSN didn't print"; exit 1; }

step "5. info reports the tenant"
sudo -u dokku dokku shared-redis:info "$TENANT" | tee /tmp/.smoke-info
grep -q "Name:.*$TENANT"          /tmp/.smoke-info || { echo "FAIL: info missing Name"; exit 1; }
grep -q "ACL user:.*$TENANT"      /tmp/.smoke-info || { echo "FAIL: info missing ACL user"; exit 1; }
grep -q "Key prefix:.*${TENANT}:" /tmp/.smoke-info || { echo "FAIL: info missing Key prefix"; exit 1; }

step "6. write within prefix succeeds; outside prefix fails with NOPERM"
pw="$(</var/lib/dokku/services/shared-redis/$TENANT/PASSWORD)"
ok="$(docker exec dokku-shared-redis redis-cli --no-auth-warning --user "$TENANT" -a "$pw" SET "${TENANT}:hello" world)"
[[ "$ok" == "OK" ]] || { echo "FAIL: prefixed SET didn't return OK: $ok"; exit 1; }
nope="$(docker exec dokku-shared-redis redis-cli --no-auth-warning --user "$TENANT" -a "$pw" SET "other-prefix:hi" world 2>&1 || true)"
[[ "$nope" == *"NOPERM"* ]] || { echo "FAIL: ACL didn't block out-of-prefix write: $nope"; exit 1; }

step "7. cross-tenant isolation: tenant2 cannot read tenant1 keys"
sudo -u dokku dokku shared-redis:create "$TENANT2" >/dev/null
pw2="$(<"/var/lib/dokku/services/shared-redis/$TENANT2/PASSWORD")"
crossread="$(docker exec dokku-shared-redis redis-cli --no-auth-warning --user "$TENANT2" -a "$pw2" GET "${TENANT}:hello" 2>&1 || true)"
[[ "$crossread" == *"NOPERM"* ]] || { echo "FAIL: cross-tenant read not blocked: $crossread"; exit 1; }

step "8. quota: tiny cap flips read-only"
sudo -u dokku dokku shared-redis:set-quota "$TENANT" --mb 1 --keys 1
sudo -u dokku dokku shared-redis:check-quotas
# We already have ${TENANT}:hello (1 key) → at-cap, not over. Add a second
# to push us over the key cap.
docker exec dokku-shared-redis redis-cli --no-auth-warning --user "$TENANT" -a "$pw" SET "${TENANT}:hello2" world >/dev/null
sudo -u dokku dokku shared-redis:check-quotas
sudo -u dokku dokku shared-redis:info "$TENANT" | grep -q "Read-only:.*true" \
  || { echo "FAIL: quota didn't flip read-only"; exit 1; }

step "9. writes blocked while read-only"
blocked="$(docker exec dokku-shared-redis redis-cli --no-auth-warning --user "$TENANT" -a "$pw" SET "${TENANT}:blocked" x 2>&1 || true)"
[[ "$blocked" == *"NOPERM"* ]] || { echo "FAIL: SET wasn't blocked while read-only: $blocked"; exit 1; }

step "10. lift cap and re-sweep restores write"
sudo -u dokku dokku shared-redis:set-quota "$TENANT" --mb 100 --keys 1000
sudo -u dokku dokku shared-redis:check-quotas
docker exec dokku-shared-redis redis-cli --no-auth-warning --user "$TENANT" -a "$pw" SET "${TENANT}:restored" y >/dev/null

step "11. link to a Dokku app and verify REDIS_URL"
sudo -u dokku dokku apps:create "$APP"
sudo -u dokku dokku shared-redis:link "$TENANT" "$APP"
dsn="$(sudo -u dokku dokku config:get "$APP" REDIS_URL)"
[[ "$dsn" == "redis://${TENANT}:"* ]] \
  || { echo "FAIL: REDIS_URL not set on $APP: $dsn"; exit 1; }
echo "  REDIS_URL=$dsn"

step "12. unlink removes REDIS_URL"
sudo -u dokku dokku shared-redis:unlink "$TENANT" "$APP"
post="$(sudo -u dokku dokku config:get "$APP" REDIS_URL || true)"
[[ -z "$post" ]] || { echo "FAIL: REDIS_URL still set after unlink: $post"; exit 1; }

step "13. list shows the tenants"
sudo -u dokku dokku shared-redis:list | grep -q "^$TENANT$" \
  || { echo "FAIL: list didn't include $TENANT"; exit 1; }

step "14. destroy and verify ACL user is gone"
sudo -u dokku dokku shared-redis:destroy "$TENANT" -f
sudo -u dokku dokku shared-redis:destroy "$TENANT2" -f
sudo -u dokku dokku shared-redis:list | grep -q "^$TENANT$" \
  && { echo "FAIL: tenant still in list after destroy"; exit 1; } || true

step "15. export/import round-trip preserves keys, TTLs, and all value types"
SLUG_RT="smoke-roundtrip-$(date +%s)"
sudo -u dokku dokku shared-redis:create "$SLUG_RT" >/dev/null
PW_RT="$(<"/var/lib/dokku/services/shared-redis/$SLUG_RT/PASSWORD")"

# Seed: string, string-with-TTL, hash, list, sorted set
docker exec dokku-shared-redis redis-cli \
  --user "$SLUG_RT" --pass "$PW_RT" --no-auth-warning \
  SET "${SLUG_RT}:str" "hello" >/dev/null
docker exec dokku-shared-redis redis-cli \
  --user "$SLUG_RT" --pass "$PW_RT" --no-auth-warning \
  SET "${SLUG_RT}:str-ttl" "expires" EX 600 >/dev/null
docker exec dokku-shared-redis redis-cli \
  --user "$SLUG_RT" --pass "$PW_RT" --no-auth-warning \
  HSET "${SLUG_RT}:hash" f1 v1 f2 v2 >/dev/null
docker exec dokku-shared-redis redis-cli \
  --user "$SLUG_RT" --pass "$PW_RT" --no-auth-warning \
  RPUSH "${SLUG_RT}:list" a b c >/dev/null
docker exec dokku-shared-redis redis-cli \
  --user "$SLUG_RT" --pass "$PW_RT" --no-auth-warning \
  ZADD "${SLUG_RT}:zset" 1 one 2 two >/dev/null

# Export to file and verify it is non-empty
sudo -u dokku dokku shared-redis:export "$SLUG_RT" > /tmp/smoke-dump.txt
[[ -s /tmp/smoke-dump.txt ]] \
  || { echo "FAIL: export produced empty file"; exit 1; }

# Wipe the tenant's own keys so we can prove import restores them
docker exec dokku-shared-redis redis-cli \
  --user "$SLUG_RT" --pass "$PW_RT" --no-auth-warning \
  DEL "${SLUG_RT}:str" "${SLUG_RT}:str-ttl" \
      "${SLUG_RT}:hash" "${SLUG_RT}:list" "${SLUG_RT}:zset" >/dev/null

# Import back (same tenant, so ACL prefix matches)
sudo -u dokku dokku shared-redis:import "$SLUG_RT" < /tmp/smoke-dump.txt

# Verify string
ACTUAL_STR="$(docker exec dokku-shared-redis redis-cli \
  --user "$SLUG_RT" --pass "$PW_RT" --no-auth-warning GET "${SLUG_RT}:str")"
[[ "$ACTUAL_STR" == "hello" ]] \
  || { echo "FAIL: string lost after import (got '$ACTUAL_STR')"; exit 1; }

# Verify TTL was preserved (should be >0, <=600)
ACTUAL_TTL="$(docker exec dokku-shared-redis redis-cli \
  --user "$SLUG_RT" --pass "$PW_RT" --no-auth-warning TTL "${SLUG_RT}:str-ttl")"
(( ACTUAL_TTL > 0 && ACTUAL_TTL <= 600 )) \
  || { echo "FAIL: TTL lost after import (got '$ACTUAL_TTL')"; exit 1; }

# Verify hash field
ACTUAL_HASH="$(docker exec dokku-shared-redis redis-cli \
  --user "$SLUG_RT" --pass "$PW_RT" --no-auth-warning HGET "${SLUG_RT}:hash" f1)"
[[ "$ACTUAL_HASH" == "v1" ]] \
  || { echo "FAIL: hash lost after import (got '$ACTUAL_HASH')"; exit 1; }

# Verify list contents
ACTUAL_LIST="$(docker exec dokku-shared-redis redis-cli \
  --user "$SLUG_RT" --pass "$PW_RT" --no-auth-warning LRANGE "${SLUG_RT}:list" 0 -1 \
  | tr '\n' ',')"
[[ "$ACTUAL_LIST" == "a,b,c," ]] \
  || { echo "FAIL: list lost after import (got '$ACTUAL_LIST')"; exit 1; }

# Verify sorted set
ACTUAL_ZSET="$(docker exec dokku-shared-redis redis-cli \
  --user "$SLUG_RT" --pass "$PW_RT" --no-auth-warning ZRANGE "${SLUG_RT}:zset" 0 -1)"
[[ "$ACTUAL_ZSET" == *"one"* ]] \
  || { echo "FAIL: sorted set lost after import (got '$ACTUAL_ZSET')"; exit 1; }

sudo -u dokku dokku shared-redis:destroy "$SLUG_RT" -f >/dev/null
rm -f /tmp/smoke-dump.txt
echo "OK"

echo
echo "=== ALL SMOKE STEPS PASSED ==="
