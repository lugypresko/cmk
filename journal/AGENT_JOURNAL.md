# CMK Agent Journal

Append-only log of every meaningful agent action. It serves two readers:
- **Agents**: memory. The Orchestrator reads the last N entries (default 20) before it plans.
- **Itay**: a readable record of what happened, what was produced, and what's waiting on you.

## How to read it
- One file per action: `entries/YYYY-MM-DD_NNN_<action>.md`. Files sort chronologically.
- YAML frontmatter fields: `id, ts (Asia/Jerusalem offset), agent, workflow (A|B|C|ops), action, inputs, outputs (paths), status, human_gate, notes`.
- `human_gate` other than `none` means a human decision is involved. `itay_approved` means it was already given.
- DB mirror: `cmk.agent_journal` (`migrations/004_agent_journal.sql`).

## Rules
- Append only. Never edit or delete past entries; correct with a new entry referencing the old `id` in `notes`.
- IDs: `J-YYYYMMDD-NNN`.


## ErrorWatcher
Monitors process quality: Guardian blockers, `correction_log` repeats (≥3 → propose rule), Measurement anomalies. Proposes Memory updates; human approves. Does not publish.
