# CMK — Engineering Evidence & Verification

This page highlights the implemented **PostgreSQL validation and audit mechanisms** in Content Memory Kitchen (CMK). CMK is a content workflow project, **not** a developer IDE plugin or a production-proven coding agent.

## Architecture at a glance

```text
Content / metadata
  → PostgreSQL schema and constraints
  → versioned SQL migrations
  → approval and state rules
  → append-only audit events
  → smoke-test assertions
```

## Inspect the implementation

| Concern | Code | What to check |
|---|---|---|
| Data model and gates | [schema.sql](schema.sql) | Constraints, enums, tables and seed assumptions |
| Versioned changes | [migrations/](migrations/) | Dependencies and migration ordering |
| Format and policy data | [002](migrations/002_spec_formats.sql), [003](migrations/003_format_specs_seed.sql) | Allowed formats and configuration |
| State and audit rules | [005](migrations/005_critique_alignment.sql) | State machine, audit and retry behavior |
| Database checks | [test_002_003.sql](migrations/test_002_003.sql), [test_005.sql](migrations/test_005.sql) | Explicit assertions and failure cases |

## Verification

Use an **isolated disposable PostgreSQL database**. These scripts create and mutate database objects and test data.

The existing [README](README.md) documents the migration order and notes that migration 005 was applied to a local PGlite development database, **not** a hosted production database.

Inspect scripts and dependencies before running. Example for the earlier migrations:

```sh
psql -v ON_ERROR_STOP=1 -f schema.sql
psql -v ON_ERROR_STOP=1 -f migrations/002_spec_formats.sql
psql -v ON_ERROR_STOP=1 -f migrations/003_format_specs_seed.sql
psql -v ON_ERROR_STOP=1 -f migrations/test_002_003.sql
```

The 005 smoke test requires migration 004 and 005 in sequence; review [test_005.sql](migrations/test_005.sql) before running it.

**Verification status:** the documentation update did not execute the SQL scripts. Do not infer production readiness, test success or measured reliability from the presence of test files.

## Technical decisions worth discussing

- **Database-level controls:** enforce certain workflow constraints independently of LLM output.
- **Human approval:** distinguish agent suggestions from authorized publishing.
- **Auditability:** preserve a record of state changes and post-approval edits.
- **Ambiguous outcomes:** handle timeouts as an unknown state rather than blindly retrying side effects.

These are transferable patterns for trustworthy AI workflows; they are not a substitute for code security review or semantic correctness evaluation.

## Known limitations

The main README explicitly marks several capabilities as draft, stub or in progress. The project currently demonstrates a schema-first design and local test scripts, **not** a completed autonomous content platform. The Guardian rules alone do not establish factual truth.

## Next steps

1. Add a one-command ephemeral Postgres test environment.
2. Run SQL smoke tests in CI and publish verified results.
3. Add a concise threat model and sample anonymized test cases.
4. Separate design specifications from completed features.
