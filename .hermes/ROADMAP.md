# ROADMAP — exchange-rate → InsForge OSS

## Estado

- Posición global: **QUEUED #3**.
- Bloqueado por: PASS de `tax_kb` (#2).
- Plan: `../docs/migration/INSFORGE-MIGRATION-PLAN.md`.
- Ninguna fase está en ejecución mientras el bloqueador siga abierto.

### M0 — inventario y baseline estricto
- [ ] Verificar infraestructura live, cuatro tablas, extensiones, roles, ACL/RLS, funciones, pares, fuentes y scheduler.
- [ ] Ejecutar SQL con `ON_ERROR_STOP=1`; corregir el falso verde antes de migrar.
- [ ] Generar backup y completar restore test.

### M1 — instancia dedicada
- [ ] Crear stack InsForge exclusivo por Dokploy UI/API.
- [ ] Crear dominio y secretos propios; no reutilizar Lowflow.

### M2 — schema, RLS y datos
- [ ] Adaptar roles/grants y contrato PostgREST a InsForge.
- [ ] Importar y validar conteos, checksums, fechas y pares.

### M3 — captura y consumidores
- [ ] Portar scheduler/captura.
- [ ] Adaptar `/rest/v1` al contrato InsForge o añadir compatibilidad explícita.

### M4 — dual-run y cutover
- [ ] Ejecutar shadow/dual-run con escritor único.
- [ ] Probar rollback antes del cambio.

### M5 — retención y retiro
- [ ] Mantener origen 14 días post-cutover.
- [ ] No borrar antes de 30 días, backup final y aprobación de Dimar.

## Changelog

- 2026-09-15 — Diana: Facturas sube a #4; el orden posterior pasa a Avaluos #5, SitioWise #6 y Solidarion #7. Exchange Rate se mantiene #3 y bloqueado por `tax_kb`.
- 2026-09-15 — Diana: creada cola #3 y roadmap M0–M5; ejecución bloqueada por `tax_kb`.
