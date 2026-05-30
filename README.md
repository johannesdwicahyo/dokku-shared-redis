# dokku-shared-redis

[![CI](https://github.com/johannesdwicahyo/dokku-shared-redis/actions/workflows/ci.yml/badge.svg)](https://github.com/johannesdwicahyo/dokku-shared-redis/actions/workflows/ci.yml)

A [Dokku](https://dokku.com) plugin that runs **one shared Redis container per host** and provisions tenants on it. Per-tenant isolation is enforced by **Redis 6+ ACL users** scoped to a per-tenant key prefix. Memory and key-count quotas are enforced by a periodic sweep.

Companion to [dokku-shared-postgres](https://github.com/johannesdwicahyo/dokku-shared-postgres). Powers [wokku.cloud](https://wokku.cloud)'s free Redis tier.

## Install

```bash
dokku plugin:install https://github.com/johannesdwicahyo/dokku-shared-redis.git
```

The install hook pulls `redis:7-alpine`, starts the shared container with a generated admin password, sets up `/etc/cron.d/dokku-shared-redis` for the periodic quota sweep, and chowns the plugin data dir to `dokku:dokku` so the runtime user can manage tenants.

## Quick start

```bash
# Provision a tenant. Prints the URL on stdout.
dokku shared-redis:create my-cache
# -> redis://my-cache:<password>@dokku-shared-redis:6379/0

# Wire it into an app (sets REDIS_URL).
dokku shared-redis:link my-cache my-app

# Inspect.
dokku shared-redis:info my-cache
dokku shared-redis:list

# Cap usage. Defaults are 25 MB / 10,000 keys per tenant.
dokku shared-redis:set-quota my-cache --mb 50 --keys 20000

# Interactive shell as the tenant ACL user.
dokku shared-redis:connect my-cache

# Tear down.
dokku shared-redis:unlink my-cache my-app
dokku shared-redis:destroy my-cache -f
```

## The prefix gotcha

The tenant's ACL is `~<name>:*` — **every key your app writes MUST start with `<name>:`** (e.g. `my-cache:session:abc`). Writes to other keys fail with a `NOPERM` error from Redis. This is the trade for not paying the cost of one container per tenant.

If your client library hardcodes plain keys (`session:abc`), wrap it with a prefix layer. In Rails:

```ruby
# config/initializers/redis.rb
$redis = Redis.new(url: ENV.fetch("REDIS_URL"))
# Use `Redis::Namespace` (gem 'redis-namespace') with namespace: 'my-cache'.
```

For `ioredis` (Node), pass `keyPrefix: 'my-cache:'` to the client constructor.

## How tenancy works

- **One container per host.** Image: `redis:7-alpine`. Started with `--requirepass <admin_pw> --appendonly yes --aclfile /data/users.acl` so AOF and ACL changes both survive restarts.
- **One ACL user per tenant.** `ACL SETUSER <name> on ><pw> ~<name>:* +@all`. The admin password is in `/var/lib/dokku/services/shared-redis/.admin_password` (mode 0600).
- **Container hostname** `dokku-shared-redis` resolves from any app on the `dokku-shared-redis` Docker network. The `link` subcommand wires `REDIS_URL=redis://<name>:<pw>@dokku-shared-redis:6379/0` onto the app and connects it to that network.

## Quotas

Two caps per tenant — memory (MB) and key count. Defaults: **25 MB / 10,000 keys**.

The cron job runs `dokku shared-redis:check-quotas` every 5 minutes. When a tenant exceeds *either* cap, the plugin flips its ACL to read-only (`resetcommands +@read +@connection +ping`) until the next sweep finds it back under both caps, at which point the full command set is restored. The ACL flip preserves the tenant's password.

Operators can run the sweep on demand:

```bash
dokku shared-redis:check-quotas
```

Output is one `flipped` / `released` line per state change; otherwise silent.

## Commands

```text
shared-redis:create <name>                  Create a tenant (ACL user + key prefix).
shared-redis:destroy <name> -f              ACL DELUSER + DEL all <name>:* keys.
shared-redis:link <name> <app>              Set REDIS_URL on <app>.
shared-redis:unlink <name> <app>            Remove REDIS_URL from <app>.
shared-redis:list                           All tenants on this host.
shared-redis:info <name>                    Keys, memory, quota, links, read-only state.
shared-redis:connect <name>                 Open redis-cli as the tenant user.
shared-redis:set-quota <name> [--mb N] [--keys N]   Set per-tenant caps.
shared-redis:unset-quota <name>             Revert to default caps.
shared-redis:check-quotas                   Run the quota sweep manually.
shared-redis:export <name>                  Dump all tenant keys to stdout (redis-cli pipe format). Preserves TTLs + all value types.
shared-redis:import <name>                  Read a dump from stdin and replay via redis-cli --pipe. ACL-scoped: cross-tenant import is blocked at the Redis layer.
shared-redis:help                           Show usage.
```

## When NOT to use this

- You need replication, sentinel, or any HA. Out of scope.
- You need >100 MB per tenant. Don't try to make this a tier-2 store; provision a real `dokku-redis` instance.
- You need keyspace notifications scoped to a tenant. They're host-wide here.

## Development

```bash
make lint   # shellcheck -x
make test   # bats tests
```

Integration smoke (run on a real Dokku host):

```bash
ssh root@my-dokku-host 'bash -s' < tests/integration_smoke.sh
```

## License

MIT — see `LICENSE`.
