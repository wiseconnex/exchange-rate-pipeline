# Exchange Rate Pipeline — AGENTS.md

## Cola obligatoria — migración InsForge

- Estado: **QUEUED #3**.
- Bloqueador: `tax_kb` (#2) debe terminar con PASS.
- Plan: `docs/migration/INSFORGE-MIGRATION-PLAN.md`.
- Estado operativo: `STATUS.md`.
- Roadmap: `.hermes/ROADMAP.md`.
- Memoria: `PROJECT-MEMORY.md`.

Mientras esté bloqueada:
- Solo documentación y verificación read-only.
- No migrar datos, cambiar consumidores ni tocar producción.
- No interpretar CI verde como SQL válido: M0 debe reproducir el schema con `ON_ERROR_STOP=1`.

Reglas:
- Target = instancia InsForge OSS dedicada, con DB, red, volumen, dominio y secretos propios.
- No reutilizar credenciales de Lowflow ni de otra instancia.
- Deploy solo mediante Dokploy UI/API.
- No guardar secretos en el repo.
- No retirar el stack actual hasta completar backup/restore, paridad, dual-run y rollback.

## Fuentes de verdad

1. `STATUS.md`
2. `.hermes/ROADMAP.md`
3. `docs/migration/INSFORGE-MIGRATION-PLAN.md`
4. `docs/architecture.md`
5. `docs/runbook.md`
6. `README.md`
