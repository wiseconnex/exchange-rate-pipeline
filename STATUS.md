# Status — exchange-rate-pipeline InsForge migration

**Updated:** 2026-09-15
**Migration state:** `QUEUED #3 / BLOCKED`
**Active execution:** none
**Blocker:** explicit, evidenced `tax_kb PASS` has not been recorded for this repository

## Queue

1. Lowflow
2. tax_kb
3. **exchange_rate (this repository)**
4. avaluos
5. sitiowise
6. solidarion
7. facturas

The queue is a hard dependency chain. Planning documents do not authorize M0, inventory against production, provisioning, data movement, dual-run, or cutover.

## Accomplished in this documentation pass

- Established agent guardrails and source-of-truth hierarchy.
- Defined M0–M5 with binary gates and evidence expectations.
- Separated the repo-described current Supabase/Kong/PostgREST architecture from the dedicated InsForge OSS target.
- Defined future work for live inventory, strict SQL validation, backup/restore, four-table reconciliation, API adaptation, capture/scheduler migration, dual-run, cutover, rollback, and retention.

## Current-system baseline (repository evidence only)

| Area | Repo-described state | Live confidence |
|---|---|---|
| Database | `exchange_rate` in shared PostgreSQL container `supabase-8954-db` | Unverified; M1 pending |
| API | Kong 2.8.1 + PostgREST 12.2.11; `/rest/v1/*` | Unverified; M1 pending |
| Domain data | Four tables: `currencies`, `exchange_rate_sources`, `currency_pairs`, `exchange_rate_snapshots` | DDL verified in repo; live state pending |
| Capture | `capture-exchange-rate.sh` fetches three providers and writes via SSH/`psql` | Code verified in repo; deployed copy pending |
| Scheduler | `launchd` plist lists 00/06/12/18; latest commit message says moved to `:45` | Contradiction; live loaded job pending |
| Backups | Repo docs describe daily dumps and local/offsite retention, with differing job/bucket details | Restore proof and live inventory pending |
| Consumers | README/API mention Facturas, SitioWise, Avalúos and future apps | Complete live dependency map pending |

## Target contract

- One dedicated InsForge OSS deployment for this project.
- Independent domain/URL, containers, PostgreSQL volume, credentials, API keys, backups, monitoring, and restore procedure.
- Database reads/writes exposed through InsForge's supported API; target record path is `/api/database/records/{tableName}` subject to M2/M3 contract tests.
- No use of another project's InsForge credentials or volumes.

## Gates not yet passed

- [ ] Upstream `tax_kb PASS` evidence linked.
- [ ] M0 authorization and scope freeze.
- [ ] M1 live inventory captured.
- [ ] M2 dedicated target and strict SQL rehearsal passed.
- [ ] M3 backup restore, four-table parity, and API compatibility passed.
- [ ] M4 dual-run and cutover approval passed.
- [ ] M5 rollback window and retention closure passed.

## Known migration blockers and decisions pending

1. Supabase-specific roles/functions in `sql/02-schema.sql` (`anon`, `authenticated`, `service_role`, `auth.role()`) require verified InsForge-compatible handling.
2. The current CI SQL step is not strict enough to prove migration safety; CI remains intentionally untouched in this phase.
3. The future ingestion path must be selected: supported InsForge API, controlled target-side worker, or direct PostgreSQL under an explicitly approved security model.
4. Actual scheduler timing, deployed script hash, current endpoint users, and backup restoreability are unknown until M1.
5. Rollback-window duration and final retention policy require owner approval; the plan proposes minimums without authorizing deletion.

## Next authorized action

None while blocked. After the global orchestrator provides `tax_kb PASS`, begin **M0 only**: record authorization, owners, maintenance constraints, evidence location, rollback window, and version pins. Then proceed to read-only M1 inventory.

## Scope statement

This pass changed documentation only. It did not modify code, SQL, CI, deployment manifests, production services, scheduler state, DNS, backups, secrets, or git history.
