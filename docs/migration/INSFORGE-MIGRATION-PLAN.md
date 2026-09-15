# InsForge migration plan — exchange-rate-pipeline

**Status:** `QUEUED #3 / BLOCKED`
**Execution dependency:** do not start M0 until the global orchestrator records an explicit, evidenced `tax_kb PASS`.
**Scope now:** documentation only. No production queries or changes, code/SQL/CI edits, secrets, commits, or pushes are authorized by this plan.

## 1. Objective

Move the exchange-rate service from its current Supabase-adjacent Kong/PostgREST deployment to a **dedicated self-hosted InsForge OSS stack**, preserving the full four-table data model, ingestion continuity, read contracts, security boundaries, backup recoverability, and a tested rollback path.

The migration is successful only after M0–M5 pass with evidence. Creating a target stack or restoring a dump is not, by itself, completion.

## 2. Queue and release gate

Global order:

`#1 Lowflow → #2 tax_kb → #3 exchange_rate → #4 avaluos → #5 sitiowise → #6 solidarion → #7 facturas`

Release conditions for this repository:

1. The global orchestrator provides a durable evidence link/path for `tax_kb PASS`.
2. The migration owner explicitly changes `.hermes/ROADMAP.md` from `QUEUED #3 / BLOCKED` to `ACTIVE M0`.
3. Owners, maintenance constraints, target version pins, evidence storage, rollback window, and retention are approved.

Until all three hold, every phase below is a plan, not an action list to execute.

## 3. Current and target architectures

### 3.1 Current — described by this repository, not yet live-verified

| Concern | Repo-described current state |
|---|---|
| PostgreSQL | Database `exchange_rate` inside shared Supabase container `supabase-8954-db` |
| API gateway | Kong 2.8.1 |
| Data API | PostgREST 12.2.11 under `/rest/v1/{table}` |
| Auth headers | `apikey` plus `Authorization: Bearer ...` in `docs/API.md` |
| Data | `currencies`, `exchange_rate_sources`, `currency_pairs`, `exchange_rate_snapshots` |
| Ingestion | Public rate providers → shell capture → SSH → direct `psql` |
| Scheduler | macOS `launchd`; checked-in plist and recent commit description disagree on exact minute |
| Backup | Repo docs describe local plus offsite dumps, but job/bucket descriptions disagree |

These facts are hypotheses for M1. No document in this repository proves what is currently loaded or healthy in production.

### 3.2 Target — dedicated InsForge OSS

| Concern | Required target state |
|---|---|
| Isolation | Unique InsForge stack/project, domain, containers, PostgreSQL volume, network boundary, credentials, API keys, and backups |
| Database | PostgreSQL managed by the dedicated InsForge stack; four domain tables preserved |
| API | InsForge-supported database API, with records at `/api/database/records/{tableName}` after version-pinned verification |
| Auth | `Authorization: Bearer <anon/JWT/service credential>` according to least privilege; no values in git |
| Operations | Health, logs, metrics, backups, restore drill, capture monitoring, and runbook owned independently |
| Failure domain | No dependency on another project's InsForge database, volume, credentials, or lifecycle |

Official InsForge documentation says self-hosted and cloud support MCP, while CLI/project-link flows may differ by deployment/version. For the dedicated self-hosted instance, verify the version-pinned supported management path before use; do not assume a cloud Project ID flow.

## 4. Non-goals for this phase

- Fixing or redesigning CI.
- Modifying current SQL, scripts, backfill tools, API consumers, compose files, or scheduler definitions.
- Querying or changing production.
- Reusing the canonical/shared InsForge instance.
- Rotating, copying, printing, or committing credentials.
- Decommissioning the old stack before M5.

## 5. Evidence contract

Future execution must write sanitized evidence under an approved location such as `docs/migration/evidence/<phase>/` or an external restricted store. Never commit dumps, raw rows containing sensitive fields, environment files, tokens, keys, connection strings, or checksums that expose protected object names.

Each phase record must include:

- UTC timestamp, operator, source/target identity, and exact command/tool version.
- Exit code and unedited relevant output, with secrets redacted at capture time.
- Expected versus actual result and PASS/FAIL decision.
- Artifact checksum where applicable, stored alongside protected backup metadata rather than secrets in git.
- Approver and link to unresolved exceptions.

## 6. M0 — governance and preflight

### Entry

- EVIDENCED `tax_kb PASS` exists.
- Overall roadmap state is explicitly released to `ACTIVE M0`.

### Work

1. Name service owner, migration operator, target platform owner, consumer owners, and rollback decision-maker.
2. Freeze scope to migration work; exclude opportunistic CI/code fixes.
3. Pin the InsForge OSS release and immutable image digests. Record supported PostgreSQL/PostgREST versions.
4. Choose an isolated target name/domain/ports/volumes without creating them yet during approval.
5. Approve maintenance constraints, RTO/RPO, dual-run duration, rollback triggers, rollback window, and retention.
6. Define the evidence location and redaction policy.

### Gate M0

PASS only when every owner and parameter above is recorded. Otherwise remain blocked; do not begin live inventory.

## 7. M1 — read-only live inventory

M1 resolves contradictions and replaces repo assumptions with measured facts. Commands must be read-only.

### 7.1 Current platform inventory

Capture:

- Host/service topology, Dokploy application identity, network, public domain, DNS target, TLS issuer/expiry.
- Container names, image references/digests, health, restart counts, and resource limits.
- PostgreSQL server version, database name/size, locale/encoding, extensions, schemas, owners, roles, grants, and active connections.
- Kong/PostgREST versions, configuration hashes, routing, headers, JWT mode, CORS, rate limits, and schema cache behavior.
- Deployed file hashes versus repository HEAD for compose, Kong config, schema, capture script, SSH helper, and scheduler.

### 7.2 Four-table baseline

For each table — `currencies`, `exchange_rate_sources`, `currency_pairs`, `exchange_rate_snapshots` — capture:

- Canonical DDL, columns/types/defaults/nullability, PK/FK/unique/check constraints.
- Index definitions, RLS enabled/forced state, policy definitions, table/sequence owners, and grants.
- Exact row count at one consistent boundary.
- Primary/natural key range, null profile, deterministic ordered digest, and sequence value where applicable.
- For snapshots: min/max `fecha`, min/max `captured_at`, counts grouped by base/quote/source, distinct source/pair coverage, duplicates on `(fecha, base_currency, currency_code, source_key)`, and orphan checks against all catalogs.

Do not compare approximate UI counts. Use one transaction/snapshot or a paused-write boundary for the final migration baseline.

### 7.3 Ingestion and scheduler inventory

Capture:

- Actually loaded `launchd` label, full effective schedule/timezone, next/last run, exit status, log paths, and deployed executable hash.
- Environment variable names and secret references only, not values.
- Upstream providers, timeout/retry behavior, failure isolation, natural-key upsert semantics, and partial-run behavior.
- Every other writer/backfill path; confirm whether a single-writer guarantee exists.
- Data freshness and last successful row per source.

Resolve the repository contradiction: the checked-in plist contains hours without minute fields (minute `00` semantics), while baseline commit `c493d0c` describes a move to `:45`. The loaded job is authoritative only after measured.

### 7.4 Consumer/API inventory

For every current consumer, record:

- Repository/service and owner.
- Base URL source, auth mode, secret reference, client library/version.
- Tables, HTTP methods, filters, select/order/limit/range behavior, RPCs, upserts, retries, and expected error shapes.
- Whether it uses raw `/rest/v1`, Supabase SDK, direct SQL, cached data, or another wrapper.
- Deployment and rollback mechanism.

README mentions Facturas, SitioWise, and Avalúos, but that is not a complete live consumer list.

### 7.5 Backup/recovery inventory

Capture the actual job, schedule, included database, dump format/options, encryption, local/offsite destinations, retention, alerting, latest successful object, checksum, and latest independent restore evidence. Resolve differences between `docs/runbook.md` and `scripts/backup/README.md` before relying on either.

### Gate M1

PASS when all inventory artifacts exist, contradictions are resolved or explicitly blocked, and a source-of-truth baseline timestamp is approved.

## 8. M2 — isolated InsForge target and strict SQL gate

### 8.1 Provisioning requirements

Provision only after authorization, through the approved deployment workflow. The target must have:

- Unique compose project/application identity.
- Dedicated PostgreSQL volume and no shared project data.
- Unique `JWT_SECRET`, `ENCRYPTION_KEY`, PostgreSQL password, root admin password, admin/API key, and anon key stored only in the approved secret manager.
- Unique public URL with matching backend/frontend base URLs and TLS.
- Database, PostgREST, and function runtime kept internal; only the InsForge service exposed.
- Version pins/digests, resource limits, health checks, logs, monitoring, scheduled backups, and offsite destination.
- Verified backend authentication through a real authenticated operation (for example MCP `fetch-docs`), not package startup alone.

Do not point this project at the shared canonical InsForge stack. Separate project lifecycle is an invariant.

### 8.2 SQL compatibility risks already visible

`sql/02-schema.sql` currently assumes Supabase-style objects:

- Roles: `anon`, `authenticated`, `service_role`.
- Policy expression: `auth.role()`.
- Grants to those roles and sequence access.

The target may expose PostgREST and RLS, but compatibility must be demonstrated against the pinned InsForge release. Do not create shim roles/functions blindly. Inventory target-provided roles/functions, JWT claims, table ownership, RLS execution context, and API key behavior first; then approve one explicit mapping.

### 8.3 Strict SQL rehearsal

The future executable migration should be assembled as versioned, forward-only SQL. Before target application:

```bash
# Disposable target-equivalent PostgreSQL only; placeholders, no secrets.
createdb "$DISPOSABLE_DB"
psql -X -v ON_ERROR_STOP=1 --single-transaction \
  --dbname "$DISPOSABLE_DB" \
  --file migrations/<version>_exchange_rate_schema.sql
```

Requirements:

1. A clean run exits 0.
2. No expected error is suppressed with shell `|| true`, broad exception handling, or non-strict `psql`.
3. Validate every table, constraint, index, policy, grant, and sequence after the transaction commits.
4. Test the approved repeat/apply-once behavior.
5. Apply to InsForge through its supported forward-only migration mechanism and verify migration history.
6. InsForge migrations execute in their own transaction; do not embed `BEGIN`, `COMMIT`, or `ROLLBACK` in a migration file.

The existing `.github/workflows/ci.yml` invokes `psql` without `-v ON_ERROR_STOP=1`. It may report misleading success after an intermediate SQL error and is **not** the migration gate. This task intentionally does not change CI.

### Gate M2

PASS requires isolated target health plus strict schema rehearsal and InsForge migration history, with approved Supabase→InsForge role/RLS mapping.

## 9. M3 — backup, restore, four-table parity, and API adaptation

### 9.1 Consistent source backup

At an approved boundary, prevent or account for writes and create a logical backup that includes schema, data, sequences, constraints, and required ownership/grant decisions. A future command shape may be:

```bash
pg_dump --format=custom --no-owner --no-acl \
  --dbname "$SOURCE_DATABASE_URL" \
  --file "$PROTECTED_PATH/exchange_rate_<UTC>.dump"
```

Never place a connection URL or dump in git. Record protected-path metadata, tool version, start/end time, size, checksum, snapshot boundary, and retention. Verify the dump with `pg_restore --list`, then restore it into a disposable database before touching target.

Because the destination platform owns system schemas, restore only approved application objects/data. Never overwrite InsForge `auth`, `system`, storage, migration-history, or platform-owned schemas.

### 9.2 Restore order

1. Provision empty dedicated target and complete platform migrations.
2. Apply approved exchange-rate schema migration to `public`.
3. Import catalog tables in FK-safe order:
   1. `currencies`
   2. `exchange_rate_sources`
   3. `currency_pairs`
   4. `exchange_rate_snapshots`
4. Restore/set the snapshot sequence to a safe value above imported IDs.
5. Reapply/verify approved ownership, grants, RLS, and policies through versioned migration.
6. Analyze tables if approved; refresh API schema metadata and verify endpoint discovery.

### 9.3 Four-table validation matrix

| Table | Exact checks |
|---|---|
| `currencies` | Row count; ordered digest by `iso_code`; PK uniqueness; active count; null/default profile |
| `exchange_rate_sources` | Row count; ordered digest by `key`; PK uniqueness; historical flags/dates |
| `currency_pairs` | Row count; ordered digest by `(base_code, quote_code)`; FK/orphan checks to currencies/sources; active and primary-source coverage |
| `exchange_rate_snapshots` | Row count; ordered digest by `id`; natural-key duplicate check; FK/orphan checks; sequence; min/max dates; source/pair/date aggregates; numeric/null profile; latest capture by source |

Digest SQL must serialize typed values deterministically (`NULL` sentinel, UTC timestamps, explicit numeric/text formatting, stable key order). Save the exact query with the result. If a table is changing during comparison, use the same logical boundary or compare an incremental delta separately.

No tolerance is allowed for catalog/snapshot row parity at the restore boundary. A difference may pass only with written owner approval and a replayable explanation.

### 9.4 API adaptation: `/rest/v1` to InsForge

Current raw pattern:

```text
GET <old-base>/rest/v1/exchange_rate_snapshots
  ?fecha=eq.2026-01-15
  &currency_code=eq.VES
  &source_key=eq.bcv_xls
  &order=fecha.desc
  &limit=1
apikey: <old public key>
Authorization: Bearer <old token/key>
```

Target pattern documented by InsForge:

```text
GET <target-base>/api/database/records/exchange_rate_snapshots
  ?fecha=eq.2026-01-15
  &currency_code=eq.VES
  &source_key=eq.bcv_xls
  &order=fecha.desc
  &limit=1
Authorization: Bearer <target anon/JWT credential>
```

Compatibility work must not be a blind string replacement. Contract-test:

- Authentication/header requirements and anonymous versus service behavior.
- RLS for all four tables and denial of privileged writes with public credentials.
- Filter operators used by consumers (`eq`, `gte`, `lte`, `in`, `is`, `like`/`ilike`).
- `select`, sort syntax, pagination/default/max limits, response headers, singular-result expectations, and error bodies.
- Upserts: InsForge record creation expects an array body even for one record; verify `Prefer: resolution=merge-duplicates,return=representation` against the snapshot unique key.
- Supabase SDK calls: migrate to the supported InsForge SDK or an explicit adapter; do not assume client interchangeability.
- Retry behavior: remove workarounds only after target evidence shows they are unnecessary.

Keep target non-serving to production consumers until M4 approval.

### Gate M3

PASS requires a verified backup and independent restore, exact approved parity for all four tables, API contract coverage for every M1 consumer/query shape, and documented per-consumer rollback.

## 10. M4 — capture/scheduler migration, dual-run, and cutover

### 10.1 Choose the target ingestion path

Current capture writes directly into a named Supabase PostgreSQL container via SSH. Select and approve one target path:

1. InsForge database records API with a write-only service credential.
2. A controlled target-side worker/custom compute service with internal database access.
3. Direct PostgreSQL only if network isolation, least privilege, rotation, auditing, and operational ownership are explicitly approved.

Do not expose PostgreSQL publicly. Whichever path wins must preserve the unique key `(fecha, base_currency, currency_code, source_key)`, idempotent replay, exact numerics, timestamps, provider isolation, retries, and secret-safe logs.

### 10.2 Scheduler controls

- Record timezone and exact minute/hour semantics.
- Package/deploy one immutable script or worker artifact and save its hash.
- Externalize endpoint and credential references.
- Add fencing/locking so old and target jobs cannot both become authoritative accidentally.
- Demonstrate manual run, scheduled run, duplicate replay, provider timeout, partial provider failure, restart, and alerting.
- Keep the old job loaded/available but clearly authoritative during shadow dual-run; target must not serve consumers yet.

### 10.3 Dual-run

Use one of these controlled patterns:

- Preferred: one acquisition event fans out the same normalized payload to old and target stores, preserving a common run ID/boundary.
- Alternative: two independently scheduled captures only if source timestamps and reconciliation semantics make exact comparison possible.

After each approved cycle, reconcile:

- Insert/update outcome per natural key.
- Latest `fecha`/`captured_at` by source.
- Catalog parity and source/pair coverage.
- Exact numeric values and null fields.
- API responses for the consumer contract suite.
- Scheduler logs, duration, retries, and errors.

Any unexplained delta resets the consecutive-pass counter. The owner sets duration/count during M0; until then, no number is implied.

### 10.4 Cutover order

1. Announce window and freeze migration-related configuration.
2. Confirm rollback owner, old health, latest restorable backup, and consumer rollback configs.
3. Fence both writers; take final source backup and boundary counts/digests.
4. Restore/replay the final delta to target and re-run four-table/API gates.
5. Stop the old authoritative writer.
6. Move read consumers in controlled batches; smoke-test each.
7. Enable the target writer only after reads pass.
8. Verify exactly one writer, freshness, API behavior, consumers, logs, and backups.
9. Keep old stack intact and rollback-ready.

### Gate M4

PASS requires approved dual-run evidence, exactly one target writer after cutover, successful consumer smoke tests, final four-table parity, monitoring, and a still-viable rollback path.

## 11. M5 — rollback, retention, and closure

### 11.1 Rollback triggers

Rollback rather than improvise when any approved threshold is crossed, including:

- Missing/duplicate/corrupt snapshot data or unexplained parity delta.
- Capture freshness breach or repeated provider ingestion failure caused by target path.
- Authentication/RLS leak or unauthorized write/read.
- Consumer error/latency threshold breach.
- Target database/platform instability.
- Backup failure or inability to restore within RTO/RPO.
- Evidence of two authoritative writers.

### 11.2 Rollback procedure

1. Declare rollback and stop/fence the target writer.
2. Preserve target logs and a protected final target backup for diagnosis.
3. Determine whether target-only accepted writes exist; export and validate a replayable delta if safe.
4. Restore old consumer configuration/DNS in the pre-recorded order.
5. Resume the old writer only after confirming no target writer remains.
6. Reconcile all four tables and freshness; smoke-test every consumer.
7. Confirm old backup job and monitoring.
8. Record RTO/RPO, data delta disposition, root cause, and next decision. Do not delete target.

DNS rollback alone is insufficient because ingestion currently bypasses the public API.

### 11.3 Retention

M0 must approve exact values. Proposed minimum policy:

- Keep old stack operational and rollback-ready for at least 14 days after cutover.
- Preserve offsite migration/source backups for at least 35 days.
- Preserve local encrypted staging backups for at least 7 days when capacity and policy allow.
- Enable and verify dedicated InsForge scheduled backups; do not assume cloud-managed retention applies to self-hosted without configuration.
- Keep manual pre-cutover/final archives until explicit owner deletion approval.
- Never delete source volume, dump, DNS rollback configuration, or old credentials merely because dual-run passed.

After the rollback window, take a final archive, verify restore independently, obtain explicit decommission approval, remove old consumers/writer/routing in a controlled change, then revoke old credentials. Archive sanitized evidence and update all docs.

### Gate M5 / final PASS

- Rollback window completed without unresolved severity-1/2 issues.
- Post-cutover backup and restore test passed.
- Retention controls are implemented and observed.
- Consumers, scheduler, DNS, monitoring, and runbooks reference only the target.
- Final archive has protected checksum and restore evidence.
- Decommission approval precedes every destructive step.
- Migration owner records final `PASS`, updates `.hermes/ROADMAP.md`, and releases queue item #4 (`avaluos`).

## 12. Required acceptance summary

| Requirement | Phase | Current state |
|---|---|---|
| Upstream `tax_kb PASS` | M0 | BLOCKED / missing evidence |
| Live source inventory | M1 | Pending |
| Dedicated InsForge OSS target | M2 | Pending |
| Strict SQL gate | M2 | Pending |
| Backup and independent restore | M3 | Pending |
| Four-table validation | M3 | Pending |
| `/rest/v1` → InsForge API adaptation | M3 | Pending |
| Capture/scheduler migration | M4 | Pending |
| Dual-run reconciliation | M4 | Pending |
| Controlled cutover | M4 | Pending |
| Rollback and retention | M5 | Pending |

## 13. References

Repository:

- `sql/02-schema.sql`
- `docker-compose.yml`
- `files/volumes/api/kong.yml`
- `scripts/capture/capture-exchange-rate.sh`
- `launchd/com.wiseconnex.exchange-rate.plist`
- `docs/API.md`
- `docs/runbook.md`
- `scripts/backup/README.md`

InsForge upstream documentation consulted for this plan:

- <https://docs.insforge.dev/core-concepts/database/overview>
- <https://docs.insforge.dev/sdks/rest/database>
- <https://docs.insforge.dev/core-concepts/database/migrations>
- <https://docs.insforge.dev/core-concepts/database/backups>
- <https://docs.insforge.dev/deployment/deploy-to-dokploy>

Re-check these against the pinned target release during M0/M2; documentation can drift.
