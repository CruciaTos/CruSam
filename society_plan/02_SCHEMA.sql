-- CruSam Society database schema, migration 001.
-- Copy this into lib/features/society/data/migrations/m001_initial.dart as ordered statements.
-- Do not rename, remove or "improve" tables or columns. Ask first if a column seems missing.
--
-- Conventions
--   *_paise      INTEGER rupees x 100
--   *_bp         INTEGER basis points, 1.00% = 100
--   *_centi      INTEGER value x 100 (area)
--   *_milli      INTEGER value x 1000 (meter quantity)
--   dates        TEXT YYYY-MM-DD
--   timestamps   TEXT UTC from datetime('now')

CREATE TABLE societies (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  short_name TEXT,
  registration_no TEXT,
  address_line1 TEXT,
  address_line2 TEXT,
  city TEXT,
  state TEXT NOT NULL DEFAULT 'Maharashtra',
  state_code TEXT NOT NULL DEFAULT '27',
  pincode TEXT,
  phone TEXT,
  email TEXT,
  pan TEXT,
  tan TEXT,
  gstin TEXT,
  gst_registered INTEGER NOT NULL DEFAULT 0 CHECK (gst_registered IN (0,1)),
  gst_effective_from TEXT,
  books_start_date TEXT NOT NULL,
  logo_path TEXT,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE app_settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

CREATE TABLE society_settings (
  society_id INTEGER NOT NULL REFERENCES societies(id),
  key TEXT NOT NULL,
  value TEXT,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (society_id, key)
);

CREATE TABLE dated_settings (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  effective_from TEXT NOT NULL,
  note TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (society_id, key, effective_from)
);

CREATE TABLE financial_years (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  code TEXT NOT NULL,
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
  closing_entry_id INTEGER,
  closed_at TEXT,
  UNIQUE (society_id, code),
  UNIQUE (society_id, start_date)
);

CREATE TABLE number_series (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  fy_id INTEGER NOT NULL REFERENCES financial_years(id),
  doc_type TEXT NOT NULL,
  prefix TEXT NOT NULL,
  next_no INTEGER NOT NULL DEFAULT 1 CHECK (next_no > 0),
  pad INTEGER NOT NULL DEFAULT 6 CHECK (pad BETWEEN 1 AND 10),
  UNIQUE (society_id, fy_id, doc_type)
);

CREATE TABLE audit_log (
  id INTEGER PRIMARY KEY,
  society_id INTEGER REFERENCES societies(id),
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id INTEGER,
  summary TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_audit_society_date ON audit_log(society_id, created_at);

CREATE TABLE attachments (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  owner_type TEXT NOT NULL,
  owner_id INTEGER NOT NULL,
  file_path TEXT NOT NULL,
  original_name TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_attachments_owner ON attachments(society_id, owner_type, owner_id);

CREATE TABLE import_batches (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  import_type TEXT NOT NULL,
  file_name TEXT NOT NULL,
  row_count INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL CHECK (status IN ('imported','failed')),
  error_summary TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Members and units

CREATE TABLE blocks (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  name TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  UNIQUE (society_id, name)
);

CREATE TABLE unit_types (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  UNIQUE (society_id, name)
);

CREATE TABLE units (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  block_id INTEGER NOT NULL REFERENCES blocks(id),
  unit_no TEXT NOT NULL,
  unit_type_id INTEGER NOT NULL REFERENCES unit_types(id),
  area1_centi INTEGER NOT NULL DEFAULT 0 CHECK (area1_centi >= 0),
  area2_centi INTEGER NOT NULL DEFAULT 0 CHECK (area2_centi >= 0),
  floor_no TEXT,
  occupancy TEXT NOT NULL DEFAULT 'owner_occupied'
    CHECK (occupancy IN ('owner_occupied','tenanted','vacant')),
  notes TEXT,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (society_id, block_id, unit_no)
);
CREATE INDEX idx_units_society ON units(society_id, is_active);

CREATE TABLE people (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  full_name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  alternate_email TEXT,
  pan TEXT,
  gstin TEXT,
  address TEXT,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_people_name ON people(society_id, full_name);

CREATE TABLE unit_people (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  unit_id INTEGER NOT NULL REFERENCES units(id),
  person_id INTEGER NOT NULL REFERENCES people(id),
  role TEXT NOT NULL CHECK (role IN ('owner','co_owner','tenant','nominee')),
  is_primary_contact INTEGER NOT NULL DEFAULT 0 CHECK (is_primary_contact IN (0,1)),
  is_bill_to INTEGER NOT NULL DEFAULT 0 CHECK (is_bill_to IN (0,1)),
  share_certificate_no TEXT,
  from_date TEXT NOT NULL,
  to_date TEXT
);
CREATE UNIQUE INDEX uq_unit_primary_contact ON unit_people(unit_id)
  WHERE is_primary_contact = 1 AND to_date IS NULL;
CREATE UNIQUE INDEX uq_unit_bill_to ON unit_people(unit_id)
  WHERE is_bill_to = 1 AND to_date IS NULL;
CREATE INDEX idx_unit_people_person ON unit_people(society_id, person_id);

-- Ledger

CREATE TABLE account_groups (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  account_type TEXT NOT NULL CHECK (account_type IN ('asset','liability','income','expense')),
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  parent_id INTEGER REFERENCES account_groups(id),
  system_key TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  UNIQUE (society_id, code)
);
CREATE UNIQUE INDEX uq_group_system_key ON account_groups(society_id, system_key)
  WHERE system_key IS NOT NULL;

CREATE TABLE accounts (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  group_id INTEGER NOT NULL REFERENCES account_groups(id),
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  account_kind TEXT NOT NULL DEFAULT 'general' CHECK (account_kind IN
    ('general','bank','cash','receivable','payable','fund','tax','deposit','fixed_deposit','retained')),
  system_key TEXT,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (society_id, code)
);
CREATE UNIQUE INDEX uq_account_system_key ON accounts(society_id, system_key)
  WHERE system_key IS NOT NULL;
CREATE INDEX idx_accounts_group ON accounts(society_id, group_id);

CREATE TABLE parties (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  name TEXT NOT NULL,
  contact_name TEXT,
  phone TEXT,
  email TEXT,
  address TEXT,
  pan TEXT,
  gstin TEXT,
  state_code TEXT,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  UNIQUE (society_id, name)
);

CREATE TABLE tds_sections (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  default_rate_bp INTEGER,
  threshold_paise INTEGER,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  UNIQUE (society_id, code)
);

CREATE TABLE vendors (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  vendor_code TEXT,
  name TEXT NOT NULL,
  contact_name TEXT,
  phone TEXT,
  email TEXT,
  alternate_emails TEXT,
  notes TEXT,
  address TEXT,
  state_code TEXT,
  pan TEXT,
  gstin TEXT,
  default_gst_rate_bp INTEGER,
  legal_type TEXT CHECK (legal_type IN ('individual','huf','firm','company','trust','other')),
  payee_name TEXT,
  bank_account_no TEXT,
  bank_branch TEXT,
  ifsc TEXT,
  default_expense_account_id INTEGER REFERENCES accounts(id),
  tds_section_id INTEGER REFERENCES tds_sections(id),
  tds_rate_bp INTEGER,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (society_id, name)
);

CREATE TABLE journal_entries (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  fy_id INTEGER NOT NULL REFERENCES financial_years(id),
  entry_no TEXT NOT NULL,
  entry_date TEXT NOT NULL,
  source_type TEXT NOT NULL,
  source_id INTEGER,
  narration TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'posted' CHECK (status IN ('posted','reversed')),
  reversal_of_id INTEGER REFERENCES journal_entries(id),
  reversed_by_id INTEGER REFERENCES journal_entries(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (society_id, entry_no)
);
CREATE INDEX idx_je_date ON journal_entries(society_id, entry_date);
CREATE INDEX idx_je_source ON journal_entries(society_id, source_type, source_id);

CREATE TABLE journal_lines (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  entry_id INTEGER NOT NULL REFERENCES journal_entries(id),
  line_no INTEGER NOT NULL,
  account_id INTEGER NOT NULL REFERENCES accounts(id),
  debit_paise INTEGER NOT NULL DEFAULT 0 CHECK (debit_paise >= 0),
  credit_paise INTEGER NOT NULL DEFAULT 0 CHECK (credit_paise >= 0),
  unit_id INTEGER REFERENCES units(id),
  vendor_id INTEGER REFERENCES vendors(id),
  party_id INTEGER REFERENCES parties(id),
  note TEXT,
  CHECK ((debit_paise > 0 AND credit_paise = 0) OR (credit_paise > 0 AND debit_paise = 0)),
  UNIQUE (entry_id, line_no)
);
CREATE INDEX idx_jl_account ON journal_lines(society_id, account_id);
CREATE INDEX idx_jl_unit ON journal_lines(society_id, unit_id);
CREATE INDEX idx_jl_vendor ON journal_lines(society_id, vendor_id);
CREATE INDEX idx_jl_party ON journal_lines(society_id, party_id);

-- Billing setup

CREATE TABLE charge_heads (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  name TEXT NOT NULL,
  account_id INTEGER NOT NULL REFERENCES accounts(id),
  head_kind TEXT NOT NULL DEFAULT 'charge' CHECK (head_kind IN ('charge','interest')),
  is_interest_bearing INTEGER NOT NULL DEFAULT 1 CHECK (is_interest_bearing IN (0,1)),
  is_gst_applicable INTEGER NOT NULL DEFAULT 0 CHECK (is_gst_applicable IN (0,1)),
  default_gst_rate_bp INTEGER,
  hsn_sac TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  system_key TEXT,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  UNIQUE (society_id, name)
);
CREATE UNIQUE INDEX uq_head_system_key ON charge_heads(society_id, system_key)
  WHERE system_key IS NOT NULL;

CREATE TABLE meter_types (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  name TEXT NOT NULL,
  charge_head_id INTEGER NOT NULL REFERENCES charge_heads(id),
  is_cumulative INTEGER NOT NULL DEFAULT 1 CHECK (is_cumulative IN (0,1)),
  minimum_paise INTEGER NOT NULL DEFAULT 0 CHECK (minimum_paise >= 0),
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  UNIQUE (society_id, name)
);

CREATE TABLE meter_slabs (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  meter_type_id INTEGER NOT NULL REFERENCES meter_types(id),
  seq INTEGER NOT NULL,
  up_to_milli INTEGER,
  rate_paise INTEGER NOT NULL CHECK (rate_paise >= 0),
  UNIQUE (meter_type_id, seq)
);

CREATE TABLE billing_rules (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  charge_head_id INTEGER NOT NULL REFERENCES charge_heads(id),
  unit_type_id INTEGER REFERENCES unit_types(id),
  rule_type TEXT NOT NULL CHECK (rule_type IN ('area_and_fixed','percent_of_heads','metered_slab')),
  rate1_paise INTEGER NOT NULL DEFAULT 0 CHECK (rate1_paise >= 0),
  rate2_paise INTEGER NOT NULL DEFAULT 0 CHECK (rate2_paise >= 0),
  fixed_paise INTEGER NOT NULL DEFAULT 0 CHECK (fixed_paise >= 0),
  percent_bp INTEGER NOT NULL DEFAULT 0 CHECK (percent_bp >= 0),
  base_head_ids TEXT,
  occupancy_filter TEXT CHECK (occupancy_filter IN ('owner_occupied','tenanted','vacant')),
  meter_type_id INTEGER REFERENCES meter_types(id),
  effective_from TEXT NOT NULL,
  effective_to TEXT,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_rules_head ON billing_rules(society_id, charge_head_id, effective_from);

CREATE TABLE meters (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  unit_id INTEGER NOT NULL REFERENCES units(id),
  meter_type_id INTEGER NOT NULL REFERENCES meter_types(id),
  meter_no TEXT,
  opening_reading_milli INTEGER NOT NULL DEFAULT 0 CHECK (opening_reading_milli >= 0),
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  UNIQUE (unit_id, meter_type_id)
);

CREATE TABLE meter_readings (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  meter_id INTEGER NOT NULL REFERENCES meters(id),
  period_from TEXT NOT NULL,
  period_to TEXT NOT NULL,
  reading_date TEXT NOT NULL,
  reading_milli INTEGER NOT NULL CHECK (reading_milli >= 0),
  UNIQUE (meter_id, period_from)
);

-- Member billing

CREATE TABLE bill_runs (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  fy_id INTEGER NOT NULL REFERENCES financial_years(id),
  frequency TEXT NOT NULL CHECK (frequency IN ('monthly','quarterly','half_yearly','yearly')),
  period_from TEXT NOT NULL,
  period_to TEXT NOT NULL,
  bill_date TEXT NOT NULL,
  due_date TEXT NOT NULL,
  interest_through TEXT,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','posted','cancelled')),
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  posted_at TEXT
);
CREATE UNIQUE INDEX uq_run_period ON bill_runs(society_id, period_from, period_to)
  WHERE status <> 'cancelled';

CREATE TABLE bills (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  fy_id INTEGER NOT NULL REFERENCES financial_years(id),
  run_id INTEGER REFERENCES bill_runs(id),
  bill_no TEXT,
  bill_kind TEXT NOT NULL DEFAULT 'regular'
    CHECK (bill_kind IN ('regular','supplementary','manual','debit_note')),
  unit_id INTEGER NOT NULL REFERENCES units(id),
  bill_to_person_id INTEGER REFERENCES people(id),
  bill_to_name TEXT NOT NULL,
  bill_date TEXT NOT NULL,
  due_date TEXT NOT NULL,
  period_from TEXT,
  period_to TEXT,
  subtotal_paise INTEGER NOT NULL DEFAULT 0,
  cgst_paise INTEGER NOT NULL DEFAULT 0 CHECK (cgst_paise >= 0),
  sgst_paise INTEGER NOT NULL DEFAULT 0 CHECK (sgst_paise >= 0),
  igst_paise INTEGER NOT NULL DEFAULT 0 CHECK (igst_paise >= 0),
  round_off_paise INTEGER NOT NULL DEFAULT 0,
  total_paise INTEGER NOT NULL DEFAULT 0,
  previous_due_paise INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','posted','reversed')),
  comment TEXT,
  journal_entry_id INTEGER REFERENCES journal_entries(id),
  reversal_entry_id INTEGER REFERENCES journal_entries(id),
  reversal_reason TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (society_id, bill_no)
);
CREATE INDEX idx_bills_unit ON bills(society_id, unit_id, bill_date);
CREATE INDEX idx_bills_date ON bills(society_id, bill_date);
CREATE UNIQUE INDEX uq_regular_bill_per_run ON bills(run_id, unit_id)
  WHERE run_id IS NOT NULL AND status <> 'reversed';

CREATE TABLE bill_lines (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  bill_id INTEGER NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
  line_no INTEGER NOT NULL,
  charge_head_id INTEGER NOT NULL REFERENCES charge_heads(id),
  line_kind TEXT NOT NULL DEFAULT 'charge' CHECK (line_kind IN ('charge','interest')),
  description TEXT,
  quantity_milli INTEGER,
  rate_paise INTEGER,
  amount_paise INTEGER NOT NULL CHECK (amount_paise >= 0),
  gst_rate_bp INTEGER NOT NULL DEFAULT 0 CHECK (gst_rate_bp >= 0),
  cgst_paise INTEGER NOT NULL DEFAULT 0 CHECK (cgst_paise >= 0),
  sgst_paise INTEGER NOT NULL DEFAULT 0 CHECK (sgst_paise >= 0),
  igst_paise INTEGER NOT NULL DEFAULT 0 CHECK (igst_paise >= 0),
  round_off_paise INTEGER NOT NULL DEFAULT 0,
  payable_paise INTEGER NOT NULL CHECK (payable_paise >= 0),
  is_interest_bearing INTEGER NOT NULL DEFAULT 0 CHECK (is_interest_bearing IN (0,1)),
  UNIQUE (bill_id, line_no)
);
CREATE INDEX idx_bill_lines_head ON bill_lines(society_id, charge_head_id);

CREATE TABLE interest_accruals (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  run_id INTEGER REFERENCES bill_runs(id),
  target_bill_id INTEGER NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
  source_bill_id INTEGER NOT NULL REFERENCES bills(id),
  from_date TEXT NOT NULL,
  to_date TEXT NOT NULL,
  amount_paise INTEGER NOT NULL CHECK (amount_paise >= 0),
  working_json TEXT NOT NULL,
  UNIQUE (target_bill_id, source_bill_id)
);
CREATE INDEX idx_interest_source ON interest_accruals(society_id, source_bill_id, to_date);

-- Collections

CREATE TABLE unidentified_receipts (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  fy_id INTEGER NOT NULL REFERENCES financial_years(id),
  reference_no TEXT NOT NULL,
  receipt_date TEXT NOT NULL,
  amount_paise INTEGER NOT NULL CHECK (amount_paise > 0),
  mode TEXT NOT NULL CHECK (mode IN ('cash','cheque','neft','rtgs','imps','upi','card','other')),
  instrument_no TEXT,
  instrument_bank TEXT,
  bank_cash_account_id INTEGER NOT NULL REFERENCES accounts(id),
  narration TEXT,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','resolved','reversed')),
  resolved_receipt_id INTEGER,
  journal_entry_id INTEGER REFERENCES journal_entries(id),
  reversal_entry_id INTEGER REFERENCES journal_entries(id),
  reversal_reason TEXT,
  UNIQUE (society_id, reference_no)
);

CREATE TABLE receipts (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  fy_id INTEGER NOT NULL REFERENCES financial_years(id),
  receipt_no TEXT NOT NULL,
  receipt_kind TEXT NOT NULL DEFAULT 'bill'
    CHECK (receipt_kind IN ('bill','advance','refundable_deposit','deposit_refund')),
  unit_id INTEGER NOT NULL REFERENCES units(id),
  payer_person_id INTEGER REFERENCES people(id),
  payer_name TEXT NOT NULL,
  receipt_date TEXT NOT NULL,
  amount_paise INTEGER NOT NULL CHECK (amount_paise >= 0),
  tds_paise INTEGER NOT NULL DEFAULT 0 CHECK (tds_paise >= 0),
  mode TEXT NOT NULL CHECK (mode IN ('cash','cheque','neft','rtgs','imps','upi','card','other','unidentified')),
  instrument_no TEXT,
  instrument_date TEXT,
  instrument_bank TEXT,
  bank_cash_account_id INTEGER REFERENCES accounts(id),
  unidentified_id INTEGER REFERENCES unidentified_receipts(id),
  narration TEXT,
  status TEXT NOT NULL DEFAULT 'posted' CHECK (status IN ('posted','reversed')),
  reversal_kind TEXT CHECK (reversal_kind IN ('mistake','bounced')),
  reversal_reason TEXT,
  journal_entry_id INTEGER REFERENCES journal_entries(id),
  reversal_entry_id INTEGER REFERENCES journal_entries(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (society_id, receipt_no),
  CHECK (amount_paise + tds_paise > 0)
);
CREATE INDEX idx_receipts_unit ON receipts(society_id, unit_id, receipt_date);
CREATE INDEX idx_receipts_date ON receipts(society_id, receipt_date);

CREATE TABLE credit_notes (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  fy_id INTEGER NOT NULL REFERENCES financial_years(id),
  note_no TEXT NOT NULL,
  scope TEXT NOT NULL CHECK (scope IN ('general','head','lines')),
  unit_id INTEGER NOT NULL REFERENCES units(id),
  note_date TEXT NOT NULL,
  charge_head_id INTEGER REFERENCES charge_heads(id),
  amount_paise INTEGER NOT NULL CHECK (amount_paise >= 0),
  cgst_paise INTEGER NOT NULL DEFAULT 0 CHECK (cgst_paise >= 0),
  sgst_paise INTEGER NOT NULL DEFAULT 0 CHECK (sgst_paise >= 0),
  igst_paise INTEGER NOT NULL DEFAULT 0 CHECK (igst_paise >= 0),
  total_paise INTEGER NOT NULL CHECK (total_paise > 0),
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'posted' CHECK (status IN ('posted','reversed')),
  reversal_reason TEXT,
  journal_entry_id INTEGER REFERENCES journal_entries(id),
  reversal_entry_id INTEGER REFERENCES journal_entries(id),
  UNIQUE (society_id, note_no)
);

CREATE TABLE bill_allocations (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  source_type TEXT NOT NULL CHECK (source_type IN ('receipt','credit_note')),
  source_id INTEGER NOT NULL,
  bill_line_id INTEGER NOT NULL REFERENCES bill_lines(id),
  allocated_paise INTEGER NOT NULL CHECK (allocated_paise > 0),
  allocation_date TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_alloc_line ON bill_allocations(society_id, bill_line_id, is_active);
CREATE INDEX idx_alloc_source ON bill_allocations(society_id, source_type, source_id);

-- Other income

CREATE TABLE other_invoices (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  fy_id INTEGER NOT NULL REFERENCES financial_years(id),
  invoice_no TEXT NOT NULL,
  party_id INTEGER NOT NULL REFERENCES parties(id),
  invoice_date TEXT NOT NULL,
  due_date TEXT NOT NULL,
  subtotal_paise INTEGER NOT NULL,
  cgst_paise INTEGER NOT NULL DEFAULT 0,
  sgst_paise INTEGER NOT NULL DEFAULT 0,
  igst_paise INTEGER NOT NULL DEFAULT 0,
  total_paise INTEGER NOT NULL CHECK (total_paise > 0),
  narration TEXT,
  status TEXT NOT NULL DEFAULT 'posted' CHECK (status IN ('posted','reversed')),
  reversal_reason TEXT,
  journal_entry_id INTEGER REFERENCES journal_entries(id),
  reversal_entry_id INTEGER REFERENCES journal_entries(id),
  UNIQUE (society_id, invoice_no)
);

CREATE TABLE other_invoice_lines (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  invoice_id INTEGER NOT NULL REFERENCES other_invoices(id) ON DELETE CASCADE,
  line_no INTEGER NOT NULL,
  account_id INTEGER NOT NULL REFERENCES accounts(id),
  description TEXT,
  hsn_sac TEXT,
  amount_paise INTEGER NOT NULL CHECK (amount_paise > 0),
  gst_rate_bp INTEGER NOT NULL DEFAULT 0,
  cgst_paise INTEGER NOT NULL DEFAULT 0,
  sgst_paise INTEGER NOT NULL DEFAULT 0,
  igst_paise INTEGER NOT NULL DEFAULT 0,
  UNIQUE (invoice_id, line_no)
);

CREATE TABLE other_receipts (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  fy_id INTEGER NOT NULL REFERENCES financial_years(id),
  receipt_no TEXT NOT NULL,
  party_id INTEGER NOT NULL REFERENCES parties(id),
  receipt_date TEXT NOT NULL,
  amount_paise INTEGER NOT NULL CHECK (amount_paise > 0),
  mode TEXT NOT NULL CHECK (mode IN ('cash','cheque','neft','rtgs','imps','upi','card','other')),
  instrument_no TEXT,
  instrument_bank TEXT,
  bank_cash_account_id INTEGER NOT NULL REFERENCES accounts(id),
  narration TEXT,
  status TEXT NOT NULL DEFAULT 'posted' CHECK (status IN ('posted','reversed')),
  reversal_reason TEXT,
  journal_entry_id INTEGER REFERENCES journal_entries(id),
  reversal_entry_id INTEGER REFERENCES journal_entries(id),
  UNIQUE (society_id, receipt_no)
);

CREATE TABLE other_receipt_allocations (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  receipt_id INTEGER NOT NULL REFERENCES other_receipts(id),
  invoice_id INTEGER NOT NULL REFERENCES other_invoices(id),
  allocated_paise INTEGER NOT NULL CHECK (allocated_paise > 0),
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1))
);

-- Expenses

CREATE TABLE expense_bills (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  fy_id INTEGER NOT NULL REFERENCES financial_years(id),
  voucher_no TEXT NOT NULL,
  bill_kind TEXT NOT NULL DEFAULT 'bill' CHECK (bill_kind IN ('bill','debit_note')),
  vendor_id INTEGER NOT NULL REFERENCES vendors(id),
  vendor_bill_no TEXT NOT NULL,
  bill_date TEXT NOT NULL,
  post_date TEXT NOT NULL,
  due_date TEXT,
  subtotal_paise INTEGER NOT NULL,
  cgst_paise INTEGER NOT NULL DEFAULT 0,
  sgst_paise INTEGER NOT NULL DEFAULT 0,
  igst_paise INTEGER NOT NULL DEFAULT 0,
  tds_section_id INTEGER REFERENCES tds_sections(id),
  tds_rate_bp INTEGER,
  tds_paise INTEGER NOT NULL DEFAULT 0 CHECK (tds_paise >= 0),
  total_paise INTEGER NOT NULL CHECK (total_paise > 0),
  payable_paise INTEGER NOT NULL CHECK (payable_paise >= 0),
  payee_name TEXT,
  narration TEXT,
  status TEXT NOT NULL DEFAULT 'posted' CHECK (status IN ('posted','reversed')),
  reversal_reason TEXT,
  journal_entry_id INTEGER REFERENCES journal_entries(id),
  reversal_entry_id INTEGER REFERENCES journal_entries(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (society_id, voucher_no),
  UNIQUE (society_id, vendor_id, vendor_bill_no, bill_kind)
);
CREATE INDEX idx_expense_date ON expense_bills(society_id, post_date);

CREATE TABLE expense_lines (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  expense_bill_id INTEGER NOT NULL REFERENCES expense_bills(id) ON DELETE CASCADE,
  line_no INTEGER NOT NULL,
  account_id INTEGER NOT NULL REFERENCES accounts(id),
  description TEXT,
  hsn_sac TEXT,
  amount_paise INTEGER NOT NULL CHECK (amount_paise > 0),
  gst_rate_bp INTEGER NOT NULL DEFAULT 0,
  cgst_paise INTEGER NOT NULL DEFAULT 0,
  sgst_paise INTEGER NOT NULL DEFAULT 0,
  igst_paise INTEGER NOT NULL DEFAULT 0,
  UNIQUE (expense_bill_id, line_no)
);

CREATE TABLE vendor_payments (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  fy_id INTEGER NOT NULL REFERENCES financial_years(id),
  payment_no TEXT NOT NULL,
  payment_kind TEXT NOT NULL CHECK (payment_kind IN ('against_bills','advance','direct_expense')),
  vendor_id INTEGER REFERENCES vendors(id),
  expense_account_id INTEGER REFERENCES accounts(id),
  payment_date TEXT NOT NULL,
  amount_paise INTEGER NOT NULL CHECK (amount_paise > 0),
  mode TEXT NOT NULL CHECK (mode IN ('cash','cheque','neft','rtgs','imps','upi','card','other')),
  instrument_no TEXT,
  instrument_date TEXT,
  payee_name TEXT,
  bank_cash_account_id INTEGER NOT NULL REFERENCES accounts(id),
  narration TEXT,
  status TEXT NOT NULL DEFAULT 'posted' CHECK (status IN ('posted','reversed')),
  reversal_reason TEXT,
  journal_entry_id INTEGER REFERENCES journal_entries(id),
  reversal_entry_id INTEGER REFERENCES journal_entries(id),
  UNIQUE (society_id, payment_no)
);
CREATE INDEX idx_vendor_payment_date ON vendor_payments(society_id, payment_date);

CREATE TABLE vendor_payment_allocations (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  payment_id INTEGER NOT NULL REFERENCES vendor_payments(id),
  expense_bill_id INTEGER NOT NULL REFERENCES expense_bills(id),
  allocated_paise INTEGER NOT NULL CHECK (allocated_paise > 0),
  allocation_date TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1))
);
CREATE INDEX idx_vpa_bill ON vendor_payment_allocations(society_id, expense_bill_id, is_active);

CREATE TABLE budgets (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  fy_id INTEGER NOT NULL REFERENCES financial_years(id),
  account_id INTEGER NOT NULL REFERENCES accounts(id),
  amount_paise INTEGER NOT NULL CHECK (amount_paise >= 0),
  UNIQUE (society_id, fy_id, account_id)
);

-- Bank and deposits

CREATE TABLE bank_accounts (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  account_id INTEGER NOT NULL UNIQUE REFERENCES accounts(id),
  bank_name TEXT NOT NULL,
  branch TEXT,
  account_number TEXT,
  ifsc TEXT,
  account_type TEXT NOT NULL CHECK (account_type IN ('savings','current','cash','other')),
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1))
);

CREATE TABLE bank_transfers (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  fy_id INTEGER NOT NULL REFERENCES financial_years(id),
  transfer_no TEXT NOT NULL,
  transfer_date TEXT NOT NULL,
  from_account_id INTEGER NOT NULL REFERENCES accounts(id),
  to_account_id INTEGER NOT NULL REFERENCES accounts(id),
  amount_paise INTEGER NOT NULL CHECK (amount_paise > 0),
  instrument_no TEXT,
  narration TEXT,
  status TEXT NOT NULL DEFAULT 'posted' CHECK (status IN ('posted','reversed')),
  reversal_reason TEXT,
  journal_entry_id INTEGER REFERENCES journal_entries(id),
  reversal_entry_id INTEGER REFERENCES journal_entries(id),
  UNIQUE (society_id, transfer_no),
  CHECK (from_account_id <> to_account_id)
);

CREATE TABLE bank_statement_imports (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  bank_account_id INTEGER NOT NULL REFERENCES bank_accounts(id),
  file_name TEXT NOT NULL,
  imported_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE bank_statement_lines (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  import_id INTEGER NOT NULL REFERENCES bank_statement_imports(id),
  bank_account_id INTEGER NOT NULL REFERENCES bank_accounts(id),
  line_date TEXT NOT NULL,
  description TEXT,
  reference TEXT,
  withdrawal_paise INTEGER NOT NULL DEFAULT 0 CHECK (withdrawal_paise >= 0),
  deposit_paise INTEGER NOT NULL DEFAULT 0 CHECK (deposit_paise >= 0),
  statement_balance_paise INTEGER
);
CREATE INDEX idx_statement_account ON bank_statement_lines(society_id, bank_account_id, line_date);

CREATE TABLE bank_clearances (
  journal_line_id INTEGER PRIMARY KEY REFERENCES journal_lines(id),
  society_id INTEGER NOT NULL REFERENCES societies(id),
  cleared_date TEXT NOT NULL,
  statement_line_id INTEGER REFERENCES bank_statement_lines(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE fixed_deposits (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  account_id INTEGER NOT NULL UNIQUE REFERENCES accounts(id),
  fd_no TEXT NOT NULL,
  bank_name TEXT NOT NULL,
  start_date TEXT NOT NULL,
  maturity_date TEXT NOT NULL,
  principal_paise INTEGER NOT NULL CHECK (principal_paise > 0),
  rate_bp INTEGER NOT NULL CHECK (rate_bp >= 0),
  compounding TEXT NOT NULL CHECK (compounding IN ('none','monthly','quarterly','half_yearly','yearly')),
  interest_frequency TEXT NOT NULL CHECK (interest_frequency IN ('monthly','quarterly','half_yearly','yearly','on_maturity')),
  tds_rate_bp INTEGER NOT NULL DEFAULT 0,
  expected_maturity_paise INTEGER,
  instructions TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','closed')),
  UNIQUE (society_id, fd_no)
);

CREATE TABLE fd_transactions (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  fd_id INTEGER NOT NULL REFERENCES fixed_deposits(id),
  fy_id INTEGER NOT NULL REFERENCES financial_years(id),
  txn_type TEXT NOT NULL CHECK (txn_type IN ('open','interest_accrued','interest_received','close')),
  txn_date TEXT NOT NULL,
  amount_paise INTEGER NOT NULL CHECK (amount_paise >= 0),
  tds_paise INTEGER NOT NULL DEFAULT 0 CHECK (tds_paise >= 0),
  bank_cash_account_id INTEGER REFERENCES accounts(id),
  narration TEXT,
  status TEXT NOT NULL DEFAULT 'posted' CHECK (status IN ('posted','reversed')),
  journal_entry_id INTEGER REFERENCES journal_entries(id),
  reversal_entry_id INTEGER REFERENCES journal_entries(id)
);

-- Documents and communication

CREATE TABLE document_footers (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  doc_type TEXT NOT NULL CHECK (doc_type IN ('member_bill','member_receipt','other_invoice','other_receipt')),
  effective_from TEXT NOT NULL,
  footer_text TEXT NOT NULL,
  UNIQUE (society_id, doc_type, effective_from)
);

CREATE TABLE reminder_batches (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  subject TEXT NOT NULL,
  body TEXT NOT NULL,
  filter_json TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE email_log (
  id INTEGER PRIMARY KEY,
  society_id INTEGER NOT NULL REFERENCES societies(id),
  batch_id INTEGER REFERENCES reminder_batches(id),
  doc_type TEXT NOT NULL,
  doc_id INTEGER,
  unit_id INTEGER REFERENCES units(id),
  to_address TEXT NOT NULL,
  cc_address TEXT,
  subject TEXT NOT NULL,
  attachment_name TEXT,
  status TEXT NOT NULL CHECK (status IN ('sent','failed')),
  provider_message_id TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_email_log_date ON email_log(society_id, created_at);
