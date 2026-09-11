# Existing test failures — separate follow-up

Status: open, tracked separately from the simple-event-recap release at the
user's explicit direction on 2026-09-11. No fixes or test suppression are part
of this decision. It applies only to the baseline-confirmed failures below,
not new regressions or future failures.

## Frontend baseline: `587d8cb`

The replacement full run had 3,439 passes and the exact same 36 failing names
as the unchanged baseline:

| Suite | Failing cases |
| --- | ---: |
| `test/admin_metrics_dashboard_test.dart` | 14 |
| `test/admin_system_health_test.dart` | 11 |
| `test/batch_2026_08_09_admin_sections_test.dart` | 9 |
| `test/admin_dau_engagement_test.dart` | 2 |

Evidence: [frontend test disposition](simple-event-recap-frontend-test-disposition.md)
and local `/tmp/simple-recap-full-flutter-verified.log`. Assertions are unchanged.
Follow-up: diagnose each suite against its real screen/API contract before
changing code or asserting that an expectation is obsolete.

## Backend baseline: `9b08e5f`

Each failure also reproduces in the unchanged backend checkout:

| Suite / case | Observed failure |
| --- | --- |
| `local-global-step-event-entitlements`: active-event dependency closure | Expected FULL, received DEPENDENCY_CLOSURE. |
| Same suite: display artifact crossing entitlement end | Boundary worker returned no claim. |
| `resolved-impact-events-v2`: Drill Sergeant rollback/retry | Final impact missing after retry; preceding rollback checks pass. |
| `query-efficiency-enrollment` | All 600 users enrolled, but expected New York timezone became UTC during reconciliation. |
| `global-event-indexed-recovery`: account-deletion lock safety | PostgreSQL 18 returns SQLSTATE 23001 where the protected assertion expects 23503; PostgreSQL 16 passes. |

Evidence: backend `docs/simple-event-recap-backend-verification.md` and
`docs/simple-event-recap-mixed-test-disposition.md`. Local baseline logs:
`/tmp/simple-recap-baseline-local-entitlements-final.log`,
`/tmp/simple-recap-baseline-drill.log`,
`/tmp/simple-recap-baseline-enrollment.log`, and
`/tmp/simple-recap-baseline-pg18-fk.log`.

Follow-up: investigate behavior versus intended contract; handle the PostgreSQL
version-specific expectation explicitly without weakening lock-safety coverage.
No claim is made that a baseline failure is harmless merely because it predates
this change. The user chose separate tracking; the repository is not all green.
