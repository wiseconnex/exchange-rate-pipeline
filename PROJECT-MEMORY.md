# Project Memory — exchange-rate-pipeline

**Project rules:** read `AGENTS.md` first. Detailed migration state is in `STATUS.md`; execution gates are in `.hermes/ROADMAP.md`.

**Updated:** 2026-09-15 (InsForge migration documentation layer)

---

## State

- Branch: `main`; baseline HEAD at documentation start: `c493d0c`.
- Migration status: **`QUEUED #3`**, not active.
- Hard blocker: do not start M0 until the global orchestrator records an evidenced **`tax_kb PASS`**.
- Global order: `#1 Lowflow`, `#2 tax_kb`, `#3 exchange_rate`, `#4 avaluos`, `#5 sitiowise`, `#6 solidarion`, `#7 facturas`.
- This session is documentation-only. No live system was queried or changed.

### Current architecture described by the repository

- Database `exchange_rate` is described as living in shared Supabase PostgreSQL container `supabase-8954-db`.
- Kong + PostgREST expose the current API under `/rest/v1`.
- A local `launchd` job invokes the capture shell script; the script writes via SSH and direct `psql`.
- Four domain tables: `currencies`, `exchange_rate_sources`, `currency_pairs`, `exchange_rate_snapshots`.
- These are repository-derived claims; M1 must verify the live deployment, data, consumers, scheduler, and backups.

### Target

- Dedicated self-hosted InsForge OSS stack with independent URL, PostgreSQL volume, secrets, API keys, backups, and rollback boundary.
- Consumer data paths adapt from `/rest/v1/{table}` to `/api/database/records/{table}` only after contract tests.
- Old stack remains authoritative through rehearsal and dual-run.

## Decisions

- Do not reuse the shared/canonical InsForge instance for this project.
- Require strict SQL failure semantics (`ON_ERROR_STOP`) before any target restore.
- Validate schema and data for all four domain tables, not only the snapshot table.
- Cut over capture/scheduler separately from read consumers and prevent two authoritative writers.
- Retain source and backups for the approved rollback window; no early teardown.

## Lessons / risks

- Current schema refers to Supabase-style roles and `auth.role()`; compatibility with the dedicated InsForge target is a gate, not an assumption.
- Current CI invokes `psql` without the migration plan's strict gate; CI is unchanged and cannot be used alone as migration proof.
- Current capture targets a specific Supabase container/database directly; changing only the public API does not migrate ingestion.
- Repo schedule descriptions differ (`:00` in the plist/readme versus a recent commit message mentioning `:45`); M1 must inventory the actually loaded job.
- Existing backup documentation contains differing bucket/job descriptions; restore evidence must settle the live truth.

## Pending next session

1. Wait for explicit, evidenced `tax_kb PASS`.
2. When unblocked, execute M0 governance/preflight only.
3. Perform M1 read-only live inventory and save evidence before drafting executable SQL or deployment changes.
4. Do not fix CI or application code as part of the queueing/documentation phase.

## References

- `STATUS.md`
- `.hermes/ROADMAP.md`
- `docs/migration/INSFORGE-MIGRATION-PLAN.md`

## Changelog

- 2026-09-15: Created compact migration memory; status remains `QUEUED #3` and blocked.
