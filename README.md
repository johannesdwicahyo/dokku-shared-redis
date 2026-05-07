# dokku-shared-redis

[![CI](https://github.com/johannesdwicahyo/dokku-shared-redis/actions/workflows/ci.yml/badge.svg)](https://github.com/johannesdwicahyo/dokku-shared-redis/actions/workflows/ci.yml)

> **Status: scaffolding.** Sibling project of [dokku-shared-postgres](https://github.com/johannesdwicahyo/dokku-shared-postgres). Implementation begins after that one is at v0.1.0.

A [Dokku](https://dokku.com) plugin that provides **shared, multi-tenant Redis** on a single host. One Redis container per host; per-tenant isolation via Redis 6+ ACL users + key-prefix pattern. Plugin-level memory + key-count quota enforcement.

Powers [wokku.cloud](https://wokku.cloud)'s free Redis tier.

## Install (planned)

```bash
dokku plugin:install https://github.com/johannesdwicahyo/dokku-shared-redis.git
```

## Commands (planned)

```bash
dokku shared-redis:create my-cache
dokku shared-redis:link my-cache my-app          # sets REDIS_URL
dokku shared-redis:connect my-cache              # interactive redis-cli
dokku shared-redis:info my-cache                 # keys, mem, conns
dokku shared-redis:list                          # all tenants on host
dokku shared-redis:set-quota my-cache --mb 50 --keys 20000
dokku shared-redis:export my-cache > dump.bin
dokku shared-redis:import my-cache < dump.bin
dokku shared-redis:destroy my-cache
```

## Why "shared"?

Same rationale as [dokku-shared-postgres](https://github.com/johannesdwicahyo/dokku-shared-postgres) — one container per host, many tenants, Redis ACL isolation. Saves memory at the cost of shared resources. Best for free tiers, multi-tenant SaaS, hobby hosts.

## Tenant isolation

Each tenant gets a Redis ACL user with access only to keys matching `<name>:*`. **Apps must prefix all keys with `<name>:`** — the ACL enforces this server-side; violations fail with a clear ACL error.

## License

MIT — see `LICENSE`.
