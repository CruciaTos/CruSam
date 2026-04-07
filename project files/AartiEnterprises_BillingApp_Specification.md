# AARTI ENTERPRISES — BILLING & DOCUMENT GENERATION APP
## Complete Project Specification Document

---

## SECTION 1 — PROJECT GOAL

The objective of this project is to develop a cross-platform Flutter application (desktop and mobile) that fully automates the generation of financial documents for Aarti Enterprises — specifically expense vouchers, tax invoices, and bank disbursement statements — using a structured employee master database maintained inside the app.

The system is designed to replace a currently manual, Excel-driven workflow. Today, the user manually maintains employee records in a spreadsheet, hand-fills expense amounts, copies bank data row-by-row, performs tax calculations independently, and then assembles PDFs manually. This is time-consuming, error-prone, and difficult to audit. The app eliminates all of this friction.

At its core, the application is a data-driven financial document engine divided into three layers: an input layer (employee master + user entries), a processing layer (calculations, mappings, auto-enrichment), and an output layer (formatted PDFs — invoice, voucher, and bank disbursement sheet).

The employee master database is maintained inside the app and serves as the single source of truth for all employee data: names, PF numbers, UAN numbers, bank account numbers, IFSC codes, zones, branches, and more. When a user creates a new expense voucher, they only need to select an employee name from a searchable dropdown, enter the expense amount, and specify the date range. All remaining employee fields are auto-populated from the master — no manual re-entry required.

A critical design principle is that vouchers are immutable snapshots. Once an employee's data is pulled into a voucher and saved, future changes to the master do not affect that voucher. This ensures audit integrity and consistency across historical billing records.

The calculation engine implements GST taxation with full transparency: CGST (9%) and SGST (9%) are computed on the voucher base total, with intermediate values (tax amounts, raw total, round-off adjustment) all displayed explicitly in the invoice — not hidden or implicitly applied. The final invoice strictly follows Aarti Enterprises' existing real-world format, ensuring continuity with current accounting and compliance practices.

The app will also generate a bank disbursement PDF, mapping each employee's payment to their debit/credit bank data — formatted for manual upload to the bank.

A secondary layer includes user authentication (Google or manual login), an in-app audit trail of edits, autosave drafts during entry, and the ability to revisit and overwrite past vouchers. The result is a compact but powerful internal billing tool that standardises operations, minimises human error, and produces consistent, compliant, professional documents every billing cycle.

---

## SECTION 2 — DATA REFERENCE (FROM ACTUAL FILES)

### 2.1 Master File — Employee Record Fields
Each employee record in the master database contains:

| Field | Description | Example |
|---|---|---|
| Sr. No | Sequential number | 1 |
| Name of Technician | Full employee name | Goutam Roy |
| PF No. | Provident Fund number | MH/212395/0058 |
| UAN NO. | Universal Account Number | 100151994821 |
| Code | Department code | F&B / I&L |
| IFSC Code | Bank IFSC | SBIN0001448 |
| Account Number | Employee's credit account | 30790679553 |
| Aarti Entp. A/c No. | Aarti's debit account (always 0680651100000338) | 0680651100000338 |
| S/b Code | Internal code (always 10) | 10 |
| Bank Details | Bank name | State Bank Of India |
| Branch | Branch name | Changrabandha |
| Zone | Geographic zone | East / South |
| Date of Joining | Joining date | 20/01/2012 |

> **Note:** The debit account `0680651100000338` (Aarti Enterprises' IDBI account) is constant for all transactions and should be stored once in Company Config, not duplicated per employee.

### 2.2 Voucher Row Fields (from actual voucher files)
Each row in the expense disbursement voucher contains:

| Field | Source |
|---|---|
| Amount | User input |
| Debit Account Number | Company Config (0680651100000338) |
| IFSC Code | Master snapshot |
| Credit Account Number | Master snapshot |
| Code | Master snapshot (S/b Code = 10) |
| Name of Beneficiary | Master snapshot |
| Place | Master snapshot (Branch) |
| Bank Detail | Description field (e.g., "Exp. MAR-2026") |
| Debit Account Name | Company Config ("Aarti Enterprises") |
| Date1 (From) | User input |
| Date2 (To) | User input |
| Department Code | Master snapshot (F&B / I&L) |

### 2.3 Bank Transfer Categories (from voucher files)
At the bottom of each voucher, two separate totals are calculated:

| Category | Description |
|---|---|
| From IDBI to Other Bank | Sum of amounts where employee's bank ≠ IDBI |
| From IDBI to IDBI Bank | Sum of amounts where employee's bank = IDBI |
| Total | Combined total (must equal base total of voucher) |

---

## SECTION 3 — PROJECT ARCHITECTURE

### 3.1 Module Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    AARTI BILLING APP                        │
├─────────────┬──────────────┬───────────────┬───────────────┤
│   Module 1  │   Module 2   │   Module 3    │   Module 4    │
│   MASTER    │   VOUCHER    │   INVOICE     │     PDF       │
│   DATA      │   BUILDER    │  GENERATION   │   ENGINE      │
├─────────────┴──────────────┴───────────────┴───────────────┤
│          Supporting Layers                                  │
│  Auth (Google / Manual) │ Audit Trail │ Draft Autosave     │
│  Calculation Engine     │ Company Config                   │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Data Flow Pipeline

```
MASTER DB
   ↓ (employee selected → snapshot pulled)
VOUCHER BUILDER
   ↓ (amounts entered → real-time total computed)
CALCULATION ENGINE
   ↓ (GST applied → round-off computed)
INVOICE FORM
   ↓ (bill no, date, PO no, item desc entered)
PDF PREVIEW
   ↓ (user approves)
PDF EXPORT
   ├── Output 1: Invoice (Page 1) + Voucher (Page 2+)
   └── Output 2: Bank Disbursement Sheet
```

---

## SECTION 4 — MODULE SPECIFICATIONS

### 4.1 MODULE 1: Master Data

**Purpose:** Single source of truth for all employee / technician records.

**Storage:** Local SQLite database (in-app)

**Fields:** All 13 fields listed in Section 2.1

**Rules:**
- All 13 fields are mandatory. User cannot save a record unless all fields are filled.
- Typeahead / fuzzy search enabled on Name of Technician field everywhere in app.
- Duplicate names: handled inherently by PF No. (each employee is unique by PF No., not by name alone — but UI should surface PF No. in disambiguation).
- Editable at any time. Changes apply only to new vouchers — existing saved vouchers are unaffected (snapshot logic).

**UI:**
- Table/grid view of all employees.
- Inline editing per row.
- Add new employee button.
- Search/filter bar (fuzzy match on name).
- Save button per row (validates all fields before saving).

---

### 4.2 MODULE 2: Voucher Builder

**Purpose:** Create monthly expense statements per employee.

**Voucher-level inputs (set once per voucher):**
- Voucher title / description (e.g., "Exp. MAR-2026 aarti") — free text
- Department code tag (e.g., F&B, I&L) — used for categorisation

**Per-employee row inputs:**
- Employee Name (typeahead dropdown from master)
- Expense Amount (whole number only — no paise)
- From Date (date picker — dd/mm/yyyy)
- To Date (date picker — dd/mm/yyyy)

**Auto-filled fields (from master snapshot, editable by user):**
- IFSC Code
- Credit Account Number
- Code (S/b = 10)
- Name of Beneficiary
- Place (Branch)
- Bank Details

**Snapshot rule:** On employee selection, all master fields are copied into the voucher row. They are stored independently. Future master changes do NOT alter this row. If user re-selects the same employee from dropdown, all auto-filled fields reset to current master values (overriding any manual edits).

**Duplicate rule:** Same employee cannot be added twice in the same voucher. The dropdown should grey out / block already-selected employees.

**Row management:**
- Add row dynamically (button at bottom of table)
- Remove any row (delete button per row)
- Keyboard-first navigation (Tab key moves between fields)

**Real-time totals (always visible at bottom of voucher builder):**
- Numeric total in ₹ (e.g., ₹4,10,651)
- Total in words — Indian format (e.g., "Rupees Four Lakh Ten Thousand Six Hundred Fifty One Only")

**Bank transfer split (calculated live at bottom):**
- "From IDBI to Other Bank" = sum of rows where bank ≠ IDBI
- "From IDBI to IDBI Bank" = sum of rows where bank = IDBI
- Total = sum of both (must equal base total)

---

### 4.3 MODULE 3: Invoice Generator

**Purpose:** Create the GST tax invoice linked to the voucher.

**Inputs (user enters manually):**
- Bill No. (free text — e.g., AE-123)
- Date (date picker — dd/mm/yyyy)
- PO No. (free text)
- Item Description (static dropdown — pre-configured list)

**Data pulled automatically:**
- Base amount from voucher total
- All tax calculations from the Calculation Engine (Section 5)
- Company bank details from Company Config

**Invoice layout (strictly follows existing AE format):**

```
┌─────────────────────────────────────────────────┐
│             AARTI ENTERPRISES                   │
│         [Address / GSTIN / PAN]                 │
├─────────────────────────────────────────────────┤
│  Bill To: [Client Details]                      │
│  Bill No: ___    Date: __/__/____               │
│  GST No: ___     PO No: ___                     │
├─────────────────────────────────────────────────┤
│  Item Description (from dropdown)               │
│                              Amount: ___        │
├─────────────────────────────────────────────────┤
│  Total amount before Tax:              ___      │
│  Add: CGST 9%:                         ___      │
│  Add: SGST 9%:                         ___      │
│  Total Tax Amount:                     ___      │
│  Round Off:                            ___      │
│  Total Amount after Tax:               ___      │
├─────────────────────────────────────────────────┤
│  Amount in Words: Rupees ___ Only               │
├─────────────────────────────────────────────────┤
│  Bank Details:                                  │
│  Bank: ___  Branch: ___                         │
│  A/c No: ___  IFSC: ___                         │
├─────────────────────────────────────────────────┤
│  Declaration / Jurisdiction / PAN / GSTIN       │
│  "Vouchers attached for ₹___"                   │
└─────────────────────────────────────────────────┘
```

**Invoice is always single page** regardless of how many employees are in the voucher. Employee breakdown is only in the voucher pages.

---

### 4.4 MODULE 4: PDF Engine

**Two PDF outputs:**

**PDF Output 1: Tax Invoice + Voucher**
- Page 1: Tax Invoice
- Page 2 onwards: Expense Voucher (one or more pages depending on employee count)

**PDF Output 2: Bank Disbursement Sheet**
- One sheet per department/batch (as per voucher)
- All columns from Section 2.2
- Bank transfer summary at bottom (IDBI to Other / IDBI to IDBI / Total)

**Behaviour:**
- User must preview PDF before exporting
- PDF is not editable after generation
- If generation fails, user can retry — no data is lost
- File naming is done manually by user (no auto-naming)
- Multi-page support: longer vouchers paginate naturally

**Typography:**
- Clean, readable font (e.g., Roboto or similar modern sans-serif)
- Hierarchical weight usage: Bold for headers/totals, Semi-Bold for column labels, Regular for data
- Consistent alignment throughout

---

### 4.5 MODULE 5: Company Configuration

**Stored once, used across all invoices:**

| Field | Example |
|---|---|
| Company Name | Aarti Enterprises |
| Address | [Full address] |
| GSTIN | [GSTIN number] |
| PAN | [PAN number] |
| Jurisdiction | [Jurisdiction text] |
| Bank Name | IDBI Bank |
| Branch | [Branch name] |
| Account No. | 0680651100000338 |
| IFSC Code | [IFSC] |
| Declaration Text | [Static declaration text] |

---

## SECTION 5 — CALCULATION ENGINE (DETAILED LOGIC)

### 5.1 Voucher Base Total
```
Base Total = Sum of all employee expense amounts
```
Example:
```
Employee A: ₹10,000
Employee B: ₹20,000
Employee C: ₹5,000
Base Total = ₹35,000
```

### 5.2 Tax Computation
```
CGST = Base Total × 9%
SGST = Base Total × 9%
Total Tax = CGST + SGST
Raw Total = Base Total + Total Tax
```
Example (from actual file — AE-122):
```
Base Total  = 4,10,651.00
CGST (9%)   =   36,958.59
SGST (9%)   =   36,958.59
Total Tax   =   73,917.18
Raw Total   = 4,84,568.18
```

### 5.3 Rounding Logic
**Rule:** Round only the final grand total. Individual tax lines (CGST, SGST) are shown with their exact decimal values. Rounding is applied only to compute the final payable amount.

```
Round Off = Rounded Total - Raw Total
Final Total = Rounded Total (whole rupees, no paise)
```

**Rounding rule:**
- Decimal ≥ 0.50 → Round Up
- Decimal < 0.50 → Round Down

**Examples:**
```
Raw Total = 4,84,568.18  →  Rounded = 4,84,568  →  Round Off = -0.18
Raw Total = 5,795.63     →  Rounded = 5,796      →  Round Off = +0.37
Raw Total = 62,467.20    →  Rounded = 62,467     →  Round Off = -0.20
Raw Total = 1,00,000.50  →  Rounded = 1,00,001   →  Round Off = +0.50
```

**Round Off can be positive or negative.** Both cases must be handled and displayed.

### 5.4 Invoice Display Fields (All Must Be Shown)
```
Total amount before Tax:         ₹4,10,651.00
Add: CGST 9%:                    ₹36,958.59
Add: SGST 9%:                    ₹36,958.59
Total Tax Amount:                ₹73,917.18
Round Off:                       -₹0.18
Total Amount after Tax:          ₹4,84,568.00
```

> **Critical:** Round Off must appear as a separate line item. It cannot be hidden or merged into the final total.

### 5.5 Amount in Words — Indian Format
**System:** Indian numbering — Thousand, Lakh, Crore. No paise. No decimals.

**Format:** `Rupees [Words] Only`

**Examples:**
```
4,10,651  →  Rupees Four Lakh Ten Thousand Six Hundred Fifty One Only
4,84,568  →  Rupees Four Lakh Eighty Four Thousand Five Hundred Sixty Eight Only
1,00,000  →  Rupees One Lakh Only
1,00,001  →  Rupees One Lakh One Only
```

**Rules:**
- No paise component
- No manual override by user
- Computed from Final Total (after rounding), not Base Total
- Must handle values up to crores

### 5.6 Bank Transfer Split Calculation
```
Transfer (IDBI to Other Bank) = Sum of amounts where employee's IFSC does NOT begin with IDIB
Clearance (IDBI to IDBI Bank)  = Sum of amounts where employee's IFSC begins with IDIB
Total                          = Transfer + Clearance = Base Total
```

> Check: Transfer + Clearance must always equal the Base Total. This is a validation point.

---

## SECTION 6 — UI REQUIREMENTS & CONSTRAINTS

### 6.1 General Principles
- Keyboard-first workflow (Tab navigation between all fields)
- Real-time feedback (totals update as user types)
- Minimal friction — no unnecessary confirmation dialogs for common actions
- Clean, structured layout with clear visual hierarchy

### 6.2 Voucher Builder UI Layout
```
[ Voucher Title / Description ]     [ Dept Code ]

┌──┬──────────────────┬────────┬────────────┬───────────┬──────────────────────────┐
│# │ Employee Name    │ Amount │ From Date  │ To Date   │ Auto-filled Fields       │
│  │ [Typeahead ▼]    │ [____] │ [dd/mm/yy] │[dd/mm/yy] │ IFSC, A/c, Bank, Place   │
│  │                  │        │            │           │ (editable by user)        │
├──┼──────────────────┼────────┼────────────┼───────────┼──────────────────────────┤
│  │ [+ Add Row]                                                                   │
└──┴──────────────────────────────────────────────────────────────────────────────┘

Total (Numeric):  ₹4,10,651
Total (Words):    Rupees Four Lakh Ten Thousand Six Hundred Fifty One Only

From IDBI to Other Bank:  ₹3,50,000
From IDBI to IDBI Bank:   ₹60,651
Total:                    ₹4,10,651
```

### 6.3 UI Constraints
- No empty required fields — inline warning (not crash)
- No duplicate employees in same voucher — dropdown disables already-added names
- Expense amount must be a whole integer — reject decimal input
- Date: From must be ≤ To — validate on date selection
- PDF not editable after generation
- Auto-save draft on every field change (no data loss on crash/exit)
- Manual save required to finalise a voucher (drafts ≠ saved)

---

## SECTION 7 — STORAGE & DATA MANAGEMENT

### 7.1 Strategy
- Primary storage: Local SQLite database
- No Excel dependency for runtime operations
- Import from Excel supported for initial data migration only (future)

### 7.2 Database Tables (Logical)

**employees** — Master records
```
id, sr_no, name, pf_no, uan_no, code, ifsc_code, account_number,
aarti_ac_no, sb_code, bank_details, branch, zone, date_of_joining,
created_at, updated_at
```

**vouchers** — Voucher header
```
id, title, description, dept_code, base_total, cgst, sgst, total_tax,
raw_total, round_off, final_total, total_in_words,
transfer_amount, clearance_amount, status (draft/saved),
created_by, created_at, updated_at
```

**voucher_rows** — Per-employee snapshot (independent of master)
```
id, voucher_id, employee_name, amount, from_date, to_date,
ifsc_code, credit_account, sb_code, bank_detail, place, dept_code,
debit_account, debit_account_name, overridden (bool)
```

**invoices** — Tax invoice data
```
id, voucher_id, bill_no, date, po_no, item_description,
base_amount, cgst, sgst, total_tax, round_off, final_total,
amount_in_words, created_at
```

**audit_log** — Edit history
```
id, user_id, voucher_id, action (create/edit/delete), timestamp, notes
```

**company_config** — Static company settings (single row)
```
id, company_name, address, gstin, pan, jurisdiction, declaration_text,
bank_name, branch, account_no, ifsc_code
```

**users** — Authentication
```
id, name, email, auth_type (google/manual), password_hash, created_at
```

### 7.3 Voucher Editing
- Past vouchers can be opened and edited
- Editing overwrites the existing record (no version history)
- Audit log records: user, action, timestamp, voucher ID
- User must explicitly press Save to commit changes
- Unsaved edits are stored as autosave draft

---

## SECTION 8 — AUTHENTICATION & AUDIT

### 8.1 Authentication
- Two options: Google OAuth login OR manual login (username + password)
- Used for audit trail attribution
- Single user environment (no role-based access for now)

### 8.2 Audit Trail
- Tracks: who, what action, which voucher, when
- Stored locally in SQLite (audit_log table)
- Not exposed to user in V1 (internal logging only, visible in future)

---

## SECTION 9 — ERROR HANDLING

| Scenario | Behaviour |
|---|---|
| Required field empty | Inline warning next to field. Cannot proceed. |
| Duplicate employee in voucher | Dropdown greys out already-selected names. |
| Decimal amount entered | Field rejects decimal input in real time. |
| From date > To date | Warning shown. Cannot save row. |
| PDF generation fails | Toast/dialog shown. Retry button available. No data lost. |
| App crash during entry | Autosave draft recovers all entered data. |
| Master field left blank | Cannot save employee record until all 13 fields filled. |
| Transfer + Clearance ≠ Base Total | Warning shown (edge case, should not occur if logic is correct). |

---

## SECTION 10 — SCOPE BOUNDARIES (V1)

### IN SCOPE
- Master DB management (CRUD)
- Voucher builder (multi-employee, snapshot-based)
- GST calculation engine with explicit round-off
- Tax invoice generation (hardcoded Aarti format)
- PDF Output 1: Invoice + Voucher
- PDF Output 2: Bank Disbursement Sheet
- PDF preview before export
- Audit trail (logging)
- User authentication (Google / manual)
- Autosave drafts
- Voucher edit / overwrite
- Indian amount-in-words engine

### OUT OF SCOPE (V1)
- Multi-client / multi-template support
- Bank API integration
- Role-based access control
- Version history / rollback
- Excel import/export
- Multi-currency
- Tally / GST filing integrations
- Automated bill numbering
- Cloud sync / backup

---

## SECTION 11 — PERFORMANCE PRINCIPLES

- Dataset is expected to be small (< 200 employees, < 100 rows per voucher)
- Accuracy is the top priority — all calculations must be verifiable
- Fuzzy search should respond in < 200ms
- PDF generation should complete in < 10 seconds
- Re-verify all calculated fields before PDF generation (pre-export validation pass)

---

## SECTION 12 — QUICK REFERENCE: KEY DECISIONS

| Decision | Resolution |
|---|---|
| Master storage | SQLite (in-app DB) |
| Voucher data | Snapshot (independent of master) |
| Override on re-select | Yes — resets to current master values |
| Duplicate employees | Not allowed in same voucher |
| Amount input | Whole integers only |
| Tax rounding | On final total only, after tax. Not on individual tax lines. |
| Round-off display | Shown as separate line item (can be + or -) |
| Amount in words | Indian system, final total, no paise, no override |
| Invoice format | Hardcoded — matches existing AE format exactly |
| Item description | Static dropdown |
| PDF after generation | Not editable |
| Voucher editing | Overwrite only (no version history) |
| Audit trail | In-app SQLite, not visible in V1 UI |
| Auth | Google or manual login |
| Draft behaviour | Autosave. Manual save to finalise. |
| Date format | dd/mm/yyyy throughout |
| Bank split logic | By IFSC prefix: IDIB = IDBI Bank, else Other Bank |

---

*Document prepared for: Aarti Enterprises Billing App — Flutter (Desktop + Mobile)*
*Version: 1.0 — Full Specification*
