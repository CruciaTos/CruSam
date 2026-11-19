-- m002 automation migration. Applied by onUpgrade from version 1 and by onCreate after m001.
-- Do not alter any m001 table. All money is integer paise. All dates are 'YYYY-MM-DD'; timestamps ISO-8601 text.
-- Implement as a Dart function m002Automation(Database db) running these statements in order.

CREATE TABLE automation_runs (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  society_id    INTEGER REFERENCES societies(id),          -- NULL only for global jobs
  kind          TEXT NOT NULL,
  period_key    TEXT NOT NULL,
  mode          TEXT NOT NULL CHECK (mode IN ('off','suggest','auto')),
  status        TEXT NOT NULL CHECK (status IN ('running','ok','error','skipped')),
  items_found   INTEGER NOT NULL DEFAULT 0,
  items_acted   INTEGER NOT NULL DEFAULT 0,
  error_message TEXT,
  started_at    TEXT NOT NULL,
  finished_at   TEXT
);
CREATE INDEX idx_runs_soc_kind ON automation_runs(society_id, kind, started_at DESC);
CREATE UNIQUE INDEX idx_runs_dedupe_ok
  ON automation_runs(society_id, kind, period_key) WHERE status = 'ok';

CREATE TABLE automation_tasks (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  society_id   INTEGER NOT NULL REFERENCES societies(id),
  kind         TEXT NOT NULL CHECK (kind IN (
                 'draft_bill_run','missing_meter','odd_meter','bank_match','unidentified_receipt',
                 'reminder_batch','promise_due','interest_preview','recurring_expense','payment_run',
                 'gst_due','tds_due','fd_maturity','fd_interest','month_end','finding',
                 'backup_due','automation_error','custom')),
  severity     TEXT NOT NULL CHECK (severity IN ('info','action','urgent')),
  title        TEXT NOT NULL,
  detail       TEXT,
  deeplink     TEXT,                                       -- society route, e.g. /society/bank?tab=match
  dedupe_key   TEXT NOT NULL,
  due_date     TEXT,
  status       TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','done','snoozed','dismissed')),
  snooze_until TEXT,
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL,
  resolved_at  TEXT,
  UNIQUE (society_id, dedupe_key)
);
CREATE INDEX idx_tasks_open ON automation_tasks(society_id, status, severity, due_date);

CREATE TABLE anomaly_findings (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  society_id   INTEGER NOT NULL REFERENCES societies(id),
  rule_key     TEXT NOT NULL,
  entity_type  TEXT NOT NULL,
  entity_id    INTEGER,
  severity     TEXT NOT NULL CHECK (severity IN ('info','warning','error')),
  message      TEXT NOT NULL,
  fingerprint  TEXT NOT NULL,                              -- stable hash so rescans do not duplicate
  status       TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','acknowledged','fixed')),
  note         TEXT,
  first_seen   TEXT NOT NULL,
  last_seen    TEXT NOT NULL,
  UNIQUE (society_id, fingerprint)
);
CREATE INDEX idx_findings_soc_status ON anomaly_findings(society_id, status, severity);

CREATE TABLE bank_match_rules (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  society_id   INTEGER NOT NULL REFERENCES societies(id),
  pattern      TEXT NOT NULL,                              -- normalised narration token or payer id
  pattern_kind TEXT NOT NULL CHECK (pattern_kind IN ('payer_id','narration_token','cheque_payer')),
  target_kind  TEXT NOT NULL CHECK (target_kind IN ('unit','vendor','account','other_party')),
  target_id    INTEGER NOT NULL,
  hits         INTEGER NOT NULL DEFAULT 1,
  last_used    TEXT,
  active       INTEGER NOT NULL DEFAULT 1,
  created_at   TEXT NOT NULL,
  UNIQUE (society_id, pattern_kind, pattern)
);

CREATE TABLE bank_match_proposals (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  society_id       INTEGER NOT NULL REFERENCES societies(id),
  statement_line_id INTEGER NOT NULL REFERENCES bank_statement_lines(id),
  proposal_kind    TEXT NOT NULL CHECK (proposal_kind IN ('receipt_for_unit','vendor_payment','existing_receipt','existing_payment','transfer','ignore')),
  target_id        INTEGER,
  unit_id          INTEGER REFERENCES units(id),
  score            INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100),
  reason           TEXT NOT NULL,
  status           TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','accepted','rejected','superseded')),
  created_at       TEXT NOT NULL,
  decided_at       TEXT,
  UNIQUE (society_id, statement_line_id, proposal_kind, target_id)
);
CREATE INDEX idx_proposals_open ON bank_match_proposals(society_id, status, score DESC);

CREATE TABLE payment_promises (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  society_id    INTEGER NOT NULL REFERENCES societies(id),
  unit_id       INTEGER NOT NULL REFERENCES units(id),
  promised_on   TEXT NOT NULL,
  promise_date  TEXT NOT NULL,
  amount_paise  INTEGER NOT NULL CHECK (amount_paise >= 0),
  note          TEXT,
  status        TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','kept','broken','cancelled')),
  created_at    TEXT NOT NULL
);
CREATE INDEX idx_promises_open ON payment_promises(society_id, status, promise_date);

CREATE TABLE reminder_log (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  society_id    INTEGER NOT NULL REFERENCES societies(id),
  unit_id       INTEGER NOT NULL REFERENCES units(id),
  ladder_step   INTEGER NOT NULL,                          -- 1,2,3...
  outstanding_paise INTEGER NOT NULL,
  sent_on       TEXT NOT NULL,
  batch_id      INTEGER REFERENCES reminder_batches(id),
  mode          TEXT NOT NULL CHECK (mode IN ('manual','auto'))
);
CREATE INDEX idx_reminder_log_unit ON reminder_log(society_id, unit_id, sent_on DESC);

CREATE TABLE recurring_templates (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  society_id    INTEGER NOT NULL REFERENCES societies(id),
  kind          TEXT NOT NULL CHECK (kind IN ('expense_bill','journal')),
  name          TEXT NOT NULL,
  vendor_id     INTEGER REFERENCES vendors(id),
  frequency     TEXT NOT NULL CHECK (frequency IN ('monthly','quarterly','half_yearly','yearly')),
  day_of_month  INTEGER NOT NULL CHECK (day_of_month BETWEEN 1 AND 28),
  next_due      TEXT NOT NULL,
  amount_mode   TEXT NOT NULL CHECK (amount_mode IN ('fixed','last_bill','ask')),
  fixed_paise   INTEGER NOT NULL DEFAULT 0 CHECK (fixed_paise >= 0),
  payload_json  TEXT NOT NULL,                             -- lines/accounts/narration, validated by service
  trusted       INTEGER NOT NULL DEFAULT 0,                -- 1 allows auto-posting within tolerance
  active        INTEGER NOT NULL DEFAULT 1,
  last_generated TEXT,
  created_at    TEXT NOT NULL
);
CREATE INDEX idx_recurring_due ON recurring_templates(society_id, active, next_due);

CREATE TABLE month_end_checks (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  society_id    INTEGER NOT NULL REFERENCES societies(id),
  period        TEXT NOT NULL,                             -- 'YYYY-MM'
  check_key     TEXT NOT NULL,
  state         TEXT NOT NULL CHECK (state IN ('pending','done','not_applicable','blocked')),
  detail        TEXT,
  manual_override INTEGER NOT NULL DEFAULT 0,              -- user marked done/NA by hand
  updated_at    TEXT NOT NULL,
  UNIQUE (society_id, period, check_key)
);

CREATE TABLE import_templates (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  society_id    INTEGER REFERENCES societies(id),          -- NULL = shared across societies
  import_kind   TEXT NOT NULL,
  name          TEXT NOT NULL,
  mapping_json  TEXT NOT NULL,                             -- {"targetField":"Source Header"}
  created_at    TEXT NOT NULL
);

CREATE TABLE search_index (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  society_id    INTEGER NOT NULL REFERENCES societies(id),
  entity_type   TEXT NOT NULL CHECK (entity_type IN ('unit','person','vendor','bill','receipt','expense_bill','payment','journal')),
  entity_id     INTEGER NOT NULL,
  label         TEXT NOT NULL,
  sublabel      TEXT,
  keywords      TEXT NOT NULL,                             -- lower-case, space separated
  route         TEXT NOT NULL,
  updated_at    TEXT NOT NULL,
  UNIQUE (society_id, entity_type, entity_id)
);
CREATE INDEX idx_search_kw ON search_index(society_id, keywords);

-- Notes for implementers
-- 1. Backup: include recurring_templates, bank_match_rules, import_templates, payment_promises, month_end_checks
--    in BackupService table list (restore-as-new remaps society_id and foreign keys like any other table).
--    Do NOT back up automation_runs, automation_tasks, anomaly_findings, bank_match_proposals,
--    reminder_log (rebuildable or transient), or search_index (rebuilt after restore).
-- 2. search_index is maintained by SearchService.reindex(societyId) after imports/restores and by
--    SearchService.touch(entityType, id) calls added in A1 where entities are created. Keep it rebuildable.
-- 3. Nothing here is a source of truth for accounting. Dropping all m002 tables must leave books intact.
