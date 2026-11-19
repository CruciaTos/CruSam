# 03. Accounting Rules

These rules are exact. If a case is missing, stop and ask.

## 1. Number and date rules

| Rule | Value |
|---|---|
| Money | `int` paise only. No `double` anywhere in money logic |
| Rounding | Half up on positive numbers: `(a * b + c ~/ 2) ~/ c` |
| Percent | Basis points. 12.00% = `1200` |
| Area | Hundredths. 650.00 sq ft = `65000` |
| Rate per sq ft | Paise per sq ft per month. ₹3.00 = `300` |
| Meter quantity | Thousandths. 12.500 units = `12500` |
| Date | `YYYY-MM-DD` strings. Inclusive ranges |
| Financial year | 1 April to 31 March. Code `2026-27` |

Area charge: `roundHalfUp(area_centi * rate_paise, 100)`.

Percentage: `roundHalfUp(base_paise * rate_bp, 10000)`.

## 2. Posting gate

`PostingService.post` must reject the entry unless all of these are true:

1. At least two lines.
2. Every line has exactly one positive side.
3. Total debit equals total credit.
4. Entry date is on or after `societies.books_start_date`.
5. Entry date falls in a financial year of that society with `status = 'open'`.
6. Every account belongs to the society and is active.
7. A `receivable` account line for member receivables has `unit_id`.
8. A `receivable` account line for other receivables has `party_id`.
9. A `payable` account line has `vendor_id`.
10. `refundable_deposits` lines have `unit_id`.
11. `vendor_advances` lines have `vendor_id`.

Every domain operation runs inside one `db.transaction`: document row, lines, allocations, number, journal entry and audit row all succeed or all roll back.

## 3. Numbering

Create these series whenever a financial year is created. `FY` is the code, for example `2026-27`.

| `doc_type` | Prefix | Example |
|---|---|---|
| `journal` | `JE/{FY}/` | `JE/2026-27/000001` |
| `member_bill` | `BILL/{FY}/` | `BILL/2026-27/000001` |
| `member_receipt` | `RCPT/{FY}/` | `RCPT/2026-27/000001` |
| `credit_note` | `CN/{FY}/` | `CN/2026-27/000001` |
| `debit_note` | `DN/{FY}/` | `DN/2026-27/000001` |
| `unidentified` | `UR/{FY}/` | `UR/2026-27/000001` |
| `other_invoice` | `OI/{FY}/` | `OI/2026-27/000001` |
| `other_receipt` | `OR/{FY}/` | `OR/2026-27/000001` |
| `expense_voucher` | `EXP/{FY}/` | `EXP/2026-27/000001` |
| `vendor_payment` | `PAY/{FY}/` | `PAY/2026-27/000001` |
| `bank_transfer` | `TRF/{FY}/` | `TRF/2026-27/000001` |

The next number is reserved inside the posting transaction. Reversed documents keep their number.

## 4. Seed data for each new society

Creating a society must, in one transaction: create the society, create the financial year containing `books_start_date`, create number series, seed groups, accounts, charge heads, TDS sections and default settings.

### Account groups

| Code | Type | Name | `system_key` |
|---|---|---|---|
| 1100 | asset | Cash and Bank | `cash_bank` |
| 1200 | asset | Member Receivables | `member_receivables` |
| 1300 | asset | Other Receivables | `other_receivables` |
| 1400 | asset | Investments and Fixed Deposits | `investments` |
| 1500 | asset | Fixed Assets | `fixed_assets` |
| 1600 | asset | Tax Assets | `tax_assets` |
| 1700 | asset | Advances and Prepaid | `advances_prepaid` |
| 2100 | liability | Share Capital | `share_capital` |
| 2200 | liability | Statutory Funds | `statutory_funds` |
| 2300 | liability | Reserves and General Funds | `reserves` |
| 2400 | liability | Member Deposits and Suspense | `member_deposits` |
| 2500 | liability | Creditors | `creditors` |
| 2600 | liability | Tax Payable | `tax_payable` |
| 2700 | liability | Other Liabilities | `other_liabilities` |
| 2800 | liability | Income and Expenditure | `income_expenditure` |
| 3100 | income | Member Charges | `member_income` |
| 3200 | income | Interest Income | `interest_income` |
| 3300 | income | Other Income | `other_income` |
| 4100 | expense | Repairs and Maintenance | `repairs` |
| 4200 | expense | Utilities | `utilities` |
| 4300 | expense | Staff and Security | `staff_security` |
| 4400 | expense | Administration and Professional | `admin_professional` |
| 4500 | expense | Taxes and Statutory | `statutory_expense` |
| 4600 | expense | Bank and Finance | `bank_finance` |
| 4700 | expense | Other Expenses | `other_expense` |

### Accounts

| Code | Group | Name | Kind | `system_key` |
|---|---|---|---|---|
| 1101 | 1100 | Cash in Hand | cash | `cash` |
| 1201 | 1200 | Members Receivable | receivable | `members_receivable` |
| 1301 | 1300 | Other Receivables | receivable | `other_receivable` |
| 1401 | 1400 | Accrued Interest on FDs | general | `accrued_interest` |
| 1601 | 1600 | Input CGST | tax | `input_cgst` |
| 1602 | 1600 | Input SGST | tax | `input_sgst` |
| 1603 | 1600 | Input IGST | tax | `input_igst` |
| 1604 | 1600 | TDS Receivable | tax | `tds_receivable` |
| 1701 | 1700 | Vendor Advances | general | `vendor_advances` |
| 2101 | 2100 | Share Capital | fund | `share_capital` |
| 2201 | 2200 | Sinking Fund | fund | `sinking_fund` |
| 2202 | 2200 | Repair Fund | fund | `repair_fund` |
| 2203 | 2200 | Major Repair Fund | fund | `major_repair_fund` |
| 2301 | 2300 | General Fund | fund | `general_fund` |
| 2302 | 2300 | Reserve Fund | fund | `reserve_fund` |
| 2303 | 2300 | Education and Training Fund | fund | `education_fund` |
| 2401 | 2400 | Refundable Deposits | deposit | `refundable_deposits` |
| 2402 | 2400 | Unidentified Receipts | general | `unidentified_receipts` |
| 2501 | 2500 | Vendors Payable | payable | `vendors_payable` |
| 2601 | 2600 | Output CGST | tax | `output_cgst` |
| 2602 | 2600 | Output SGST | tax | `output_sgst` |
| 2603 | 2600 | Output IGST | tax | `output_igst` |
| 2604 | 2600 | TDS Payable | tax | `tds_payable` |
| 2801 | 2800 | Income and Expenditure Account | retained | `income_expenditure` |
| 2899 | 2800 | Opening Balance Adjustment | general | `opening_adjustment` |
| 3101 | 3100 | Maintenance Charges | general | `maintenance_income` |
| 3102 | 3100 | Water Charges | general | `water_income` |
| 3103 | 3100 | Common Electricity Charges | general | `electricity_income` |
| 3104 | 3100 | Parking Charges | general | `parking_income` |
| 3105 | 3100 | Non-Occupancy Charges | general | `non_occupancy_income` |
| 3106 | 3100 | Insurance Charges | general | `insurance_income` |
| 3107 | 3100 | Property Tax Recovery | general | `property_tax_income` |
| 3201 | 3200 | Late Payment Interest | general | `late_interest_income` |
| 3202 | 3200 | Bank Interest | general | `bank_interest_income` |
| 3203 | 3200 | FD Interest | general | `fd_interest_income` |
| 3301 | 3300 | Member Adjustments | general | `member_adjustments` |
| 3302 | 3300 | Round Off | general | `round_off` |
| 3303 | 3300 | Miscellaneous Income | general | `misc_income` |
| 4101 | 4100 | Lift Maintenance | general | |
| 4102 | 4100 | Building Repairs | general | |
| 4103 | 4100 | Plumbing and Electrical Repairs | general | |
| 4201 | 4200 | Electricity | general | |
| 4202 | 4200 | Water | general | |
| 4301 | 4300 | Security Charges | general | |
| 4302 | 4300 | Housekeeping | general | |
| 4303 | 4300 | Salaries and Wages | general | |
| 4401 | 4400 | Audit Fees | general | |
| 4402 | 4400 | Accounting Charges | general | |
| 4403 | 4400 | Legal and Professional Fees | general | |
| 4404 | 4400 | Printing and Stationery | general | |
| 4501 | 4500 | Property Tax | general | |
| 4502 | 4500 | Insurance Premium | general | |
| 4601 | 4600 | Bank Charges | general | `bank_charges` |
| 4701 | 4700 | Miscellaneous Expenses | general | |

The cash account also gets a `bank_accounts` row with `account_type = 'cash'` and `bank_name = 'Cash in Hand'`.

Bank accounts are created by the user in group 1100, code range `1102` onward. Fixed deposits use group 1400, code range `1402` onward.

### Charge heads

| Sort | Name | Account | Interest bearing | `head_kind` | `system_key` |
|---|---|---|---|---|---|
| 10 | Maintenance Charges | 3101 | yes | charge | `maintenance` |
| 20 | Sinking Fund | 2201 | yes | charge | `sinking_fund` |
| 30 | Repair Fund | 2202 | yes | charge | `repair_fund` |
| 40 | Water Charges | 3102 | no | charge | `water` |
| 50 | Common Electricity Charges | 3103 | no | charge | `electricity` |
| 60 | Parking Charges | 3104 | yes | charge | `parking` |
| 70 | Non-Occupancy Charges | 3105 | yes | charge | `non_occupancy` |
| 80 | Insurance Charges | 3106 | yes | charge | `insurance` |
| 90 | Property Tax Recovery | 3107 | yes | charge | `property_tax` |
| 1000 | Late Payment Interest | 3201 | no | interest | `late_interest` |

### Default settings

| Key | Default |
|---|---|
| `billing.frequency` | `monthly` |
| `billing.due_day_offset` | `20` |
| `billing.round_mode` | `none` (`none` or `rupee`) |
| `billing.show_interest_breakup` | `1` |
| `billing.show_recent_receipts` | `1` |
| `collection.auto_apply_advance` | `0` |
| `interest.enabled` | `0` |
| `interest.grace_days` | `0` |
| `interest.start_date` | blank |
| `document.bill_title` | `Maintenance Bill` |
| `document.receipt_title` | `Receipt` |
| `document.payment_instructions` | blank |
| `document.signatory` | `Authorised Signatory` |
| `email.send_to` | `primary_contact` |

Dated keys in `dated_settings`:

| Key | Value |
|---|---|
| `interest.rate_bp` | Integer string |
| `gst.member_limit_paise` | Integer string |

**Do not seed statutory rates.** The user enters them.

## 5. Posting map

Use `system_key` to find accounts. Do not search by account name.

| `source_type` | Debit | Credit |
|---|---|---|
| `opening` | Assets and expenses with debit opening; balancing `opening_adjustment` if needed | Liabilities and income with credit opening; balancing `opening_adjustment` if needed |
| `manual` | Entered accounts | Entered accounts |
| `member_bill` | `members_receivable` total with `unit_id` | Each line's head account for `amount`; `output_cgst`, `output_sgst`, `output_igst`; `round_off` if positive |
| Negative round-off in `member_bill` | Add `round_off` debit | |
| `member_receipt` kind `bill` or `advance` | Bank or cash for `amount`; `tds_receivable` for `tds` | `members_receivable` for `amount + tds`, with `unit_id` |
| `member_receipt` kind `refundable_deposit` | Bank or cash | `refundable_deposits` with `unit_id` |
| `member_receipt` kind `deposit_refund` | `refundable_deposits` with `unit_id` | Bank or cash |
| `credit_note` | Head account or `member_adjustments`; output GST | `members_receivable` with `unit_id` |
| `unidentified_receipt` | Bank or cash | `unidentified_receipts` |
| `resolve_unidentified` | `unidentified_receipts` | `members_receivable` with `unit_id` |
| `other_invoice` | `other_receivable` with `party_id` | Line accounts; output GST |
| `other_receipt` | Bank or cash | `other_receivable` with `party_id` |
| `expense_bill` | Line accounts; input GST | `vendors_payable` with `vendor_id`; `tds_payable` |
| `expense_debit_note` | `vendors_payable` with `vendor_id` | Line accounts; input GST |
| `vendor_payment` kind `against_bills` | `vendors_payable` with `vendor_id` | Bank or cash |
| `vendor_payment` kind `advance` | `vendor_advances` with `vendor_id` | Bank or cash |
| `vendor_payment` kind `direct_expense` | Expense account | Bank or cash |
| `advance_adjustment` | `vendors_payable` with `vendor_id` | `vendor_advances` with `vendor_id` |
| `bank_transfer` | Destination | Source |
| `fd_open` | FD account | Bank or cash |
| `fd_interest_accrued` | `accrued_interest`; `tds_receivable` | `fd_interest_income` |
| `fd_interest_received` | Bank or cash | `fd_interest_income`, or `accrued_interest` if already accrued |
| `fd_close` | Bank or cash | FD account; `accrued_interest` when applicable |
| `year_close` | Income accounts with credit balance; `income_expenditure` for deficit | Expense accounts with debit balance; `income_expenditure` for surplus |
| `fund_appropriation` | `income_expenditure` | Selected fund account |
| `reversal` | Original credits | Original debits |

## 6. Bill generation

### Periods

| Frequency | Allowed period | Months |
|---|---|---|
| monthly | One calendar month | 1 |
| quarterly | Apr-Jun, Jul-Sep, Oct-Dec, Jan-Mar | 3 |
| half_yearly | Apr-Sep, Oct-Mar | 6 |
| yearly | Apr-Mar | 12 |

A bill run must lie in one open financial year. Bill date must be in that year. Due date must be on or after bill date.

### Calculation order for each active unit

1. Pick one rule per charge head.
   - Rule must be active and `effective_from <= bill_date` and (`effective_to` is null or `effective_to >= bill_date`).
   - A rule with matching `unit_type_id` beats a general rule.
   - Two equally specific matching rules are a blocking error.
   - If `occupancy_filter` is set and does not match, there is no charge.
2. Calculate non-percentage heads in `sort_order`.
   - `area_and_fixed`: `months * (areaCharge(area1, rate1) + areaCharge(area2, rate2) + fixed)`.
   - `metered_slab`: use the reading for this period.
3. Calculate `percent_of_heads` after all base heads.
   - Base is the sum of the same unit's calculated base head amounts for this bill.
4. Skip zero lines.
5. Add one late-interest line when interest is above zero.
6. Calculate GST by line.
7. Apply optional rupee rounding to the bill total.
8. A unit with no active bill-to person is a blocking error.
9. A unit with no lines appears as a warning and gets no bill.

### Metered charges

`consumption = current reading - previous reading`. The previous reading is the latest earlier reading or `opening_reading_milli`.

- Negative consumption is a blocking error.
- Missing current reading is a blocking error when a metered rule applies.
- `is_cumulative = 1`: price each tier only for the quantity inside that tier.
- `is_cumulative = 0`: find the first slab containing the whole quantity and price the whole quantity at that rate.
- Final amount is at least `minimum_paise`.
- `up_to_milli = null` is the final slab.

Slab amount: `roundHalfUp(quantity_milli * rate_paise, 1000)`.

### Member GST

GST is charged on a line only when all are true:

- `societies.gst_registered = 1`.
- `bill_date >= gst_effective_from`.
- Head has `is_gst_applicable = 1`.
- Head has `default_gst_rate_bp`.
- The member-limit test does not exempt the bill.

Limit test:

```text
monthly_taxable = sum(amount of GST-applicable charge lines) / months
if a gst.member_limit_paise value applies and monthly_taxable <= limit: no GST
otherwise: GST on all applicable lines
```

Split: `gst = percent(amount, rate)`, `cgst = gst ~/ 2`, `sgst = gst - cgst`. Member bills do not use IGST in V1.

Interest GST is off in V1.

### Rounding

If `billing.round_mode = rupee`, target total is `roundHalfUp(rawTotal, 100) * 100`. Put the difference on the bill's last line in `round_off_paise`.

`payable_paise = amount + cgst + sgst + igst + round_off`.

`bills.total_paise` equals the sum of line payables.

## 7. Allocation and balances

- `line_allocated = sum(active bill_allocations.allocated_paise)`.
- `line_remaining = payable - line_allocated`.
- `bill_remaining = sum(line_remaining)`.
- Unit balance = debit minus credit on `members_receivable` for that `unit_id`.
- Unapplied advance = `sum(receipt credit) - sum(active receipt allocations)` for posted `bill` and `advance` receipts.

Default allocation:

1. Posted bills by `due_date`, `bill_date`, `id`.
2. Within a bill, interest lines first.
3. Then charge lines by `line_no`.

A user-edited allocation is valid only if each amount is positive, each amount is no more than the line remaining, and the total is no more than the receipt's `amount + tds`.

Any unallocated receipt money remains as advance.

### Reversal

| Document | Rule |
|---|---|
| Receipt | Requires a reason and `mistake` or `bounced`. Deactivate its allocations, then post the mirror entry |
| Bill | Blocked if active allocations exist. Also blocked if a later posted interest accrual uses it as `source_bill_id` |
| Credit note | Deactivate its allocations, then post the mirror entry |
| Expense bill | Blocked if active payment allocations exist |
| Vendor payment | Deactivate allocations, then post the mirror entry |
| Bank transfer | Blocked if either journal line is cleared |
| Any bank or cash receipt or payment | Blocked if its bank line is cleared |

A bounced-cheque charge is a separate manual member bill. Do not create it automatically.

## 8. Late-payment interest

Inputs:

- `interest.enabled = 1`
- `interest.start_date`
- `interest.grace_days`
- `interest.rate_bp`, by date
- `bill_runs.interest_through = bill_date - 1 day`

For each posted source bill of the unit, excluding interest lines:

```text
first_day = max(due_date + grace_days + 1, interest.start_date, last accrued to_date + 1)
last_day  = interest_through
```

For each day from `first_day` to `last_day`:

```text
base_on_day = sum over interest-bearing charge lines of
              max(amount_paise - allocations with allocation_date <= day, 0)
```

If a line's allocations cover its full payable, its base is zero.

Group equal consecutive `(base, rate)` days into segments. For one source bill:

```text
numerator = sum(base * rate_bp * days)
interest  = roundHalfUp(numerator, 365 * 10000)
```

Rules:

- A receipt reduces interest from its allocation date.
- No interest on interest, GST or round-off.
- Interest is calculated only during a bill run.
- Later reversals do not rewrite earlier interest. Show a warning on the unit statement.
- `interest_accruals.working_json` stores segments for the preview.
- All source-bill amounts are combined into one Late Payment Interest line on the target bill.
- Missing rate while interest is enabled is a blocking error.

## 9. Expenses

```text
line GST: CGST + SGST for same state, or IGST for different state
subtotal = sum(line amounts)
total    = subtotal + GST
TDS      = user amount, or percent(subtotal, rate)
payable  = total - TDS
```

Vendor same-state test: `vendors.state_code == societies.state_code`. Blank vendor state defaults to same state and is editable per bill.

Vendor balance = credit minus debit on `vendors_payable` for that vendor.

## 10. Statements

Account balance:

| Type | Display balance |
|---|---|
| Asset, expense | debit - credit |
| Liability, income | credit - debit |

Statement rules:

- Trial balance lists every account with opening, debit, credit and closing.
- Income and Expenditure shows income and expense accounts for the period.
- Balance sheet shows assets, liabilities, funds and the Income and Expenditure balance.
- Before year close, current-year unclosed surplus or deficit is shown as a separate liabilities section line.
- Credit balances in `members_receivable` by unit show under liabilities as **Advances from Members**. Debit balances show under assets. Do not net them.
- Debit balances in `vendors_payable` by vendor show under assets as **Advances to Vendors**.
- Receipts and Payments uses only bank and cash account movement, grouped by contra account.

## 11. Year-end

Close preconditions:

- Year is open.
- All earlier years are closed.
- The next year exists, or is created in the same transaction.
- No draft bill runs or draft bills in the year.
- Trial balance balances.
- `opening_adjustment` is zero, or the user types `CLOSE` after a warning.

Close process:

1. Optional appropriations from `income_expenditure` to selected funds.
2. Post `year_close` dated the last day of the year.
3. Mark the year closed.
4. New-year balances continue from the ledger. Do not copy balances.

Reports for later years treat income and expense balances as starting at zero because of the closing entry.

Reopen is only allowed for the latest closed year, after typing `REOPEN`. It reverses the closing and appropriation entries in that year, then sets it to open.

## 12. Golden test data

Use this exact scenario in `test/society/golden_scenario_test.dart`.

Society: **Sample Heights CHS**. Books start `2026-04-01`. `billing.round_mode = none`.

Bank: `Sample Bank`, opening debit ₹50,000.00, balancing credit to General Fund.

Unit type: Residential.

| Unit | Area 1 | Occupancy |
|---|---:|---|
| A-101 | 650.00 | owner_occupied |
| A-102 | 800.00 | tenanted |

Rules from `2026-04-01`:

| Head | Rule | Interest bearing |
|---|---|---|
| Maintenance Charges | ₹3.00 per sq ft | yes |
| Sinking Fund | ₹0.50 per sq ft | yes |
| Repair Fund | ₹200 fixed | yes |
| Water Charges | ₹150 fixed | no |
| Non-Occupancy Charges | 10.00% of Maintenance, tenanted only | yes |

### April bill

Bill date `2026-04-01`, due date `2026-04-20`.

| Line | A-101 | A-102 | Credit account total |
|---|---:|---:|---:|
| Maintenance | 1,950.00 | 2,400.00 | 4,350.00 |
| Sinking Fund | 325.00 | 400.00 | 725.00 |
| Repair Fund | 200.00 | 200.00 | 400.00 |
| Water | 150.00 | 150.00 | 300.00 |
| Non-Occupancy | | 240.00 | 240.00 |
| **Total** | **2,625.00** | **3,390.00** | **6,015.00** |

### Receipt

A-101 pays ₹1,000.00 by cheque on `2026-04-15`. Default allocation puts all ₹1,000.00 on Maintenance.

Trial balance:

| Account | Debit | Credit |
|---|---:|---:|
| Sample Bank | 51,000.00 | |
| Members Receivable | 5,015.00 | |
| General Fund | | 50,000.00 |
| Maintenance Charges | | 4,350.00 |
| Sinking Fund | | 725.00 |
| Repair Fund | | 400.00 |
| Water Charges | | 300.00 |
| Non-Occupancy Charges | | 240.00 |
| **Total** | **56,015.00** | **56,015.00** |

### May interest

Rate 12.00%, start `2026-04-01`, grace 0. May bill date `2026-05-01`, so interest through `2026-04-30`.

| Unit | Interest-bearing base | Days | Interest |
|---|---:|---:|---:|
| A-101 | 2,475.00 - 1,000.00 = 1,475.00 | 10 | ₹4.85 |
| A-102 | 3,240.00 | 10 | ₹10.65 |

Part-payment test: if A-102 instead pays ₹1,240.00 on `2026-04-25`, allocated to Maintenance:

```text
3240.00 for 4 days + 2000.00 for 6 days
(324000*4 + 200000*6) * 1200 / 3650000 = 820.60 paise
Interest = ₹8.21
```

Rounding test: with `billing.round_mode = rupee`, A-101 May raw total is ₹2,629.85, bill total is ₹2,630.00 and round-off is ₹0.15 credit.

### Vendor bill

Lift Maintenance ₹10,000.00, 18% same-state GST, TDS 2% of subtotal.

| Account | Debit | Credit |
|---|---:|---:|
| Lift Maintenance | 10,000.00 | |
| Input CGST | 900.00 | |
| Input SGST | 900.00 | |
| Vendors Payable | | 11,600.00 |
| TDS Payable | | 200.00 |

Payment of ₹11,600.00 clears the vendor balance.

Using the April bill, A-101 receipt and paid vendor bill, the trial balance total is **₹56,215.00**.

Year-close entry:

| Account | Debit | Credit |
|---|---:|---:|
| Maintenance Charges | 4,350.00 | |
| Water Charges | 300.00 | |
| Non-Occupancy Charges | 240.00 | |
| Income and Expenditure Account | 5,110.00 | |
| Lift Maintenance | | 10,000.00 |

After close, the balance sheet totals **₹46,215.00**:

| Side | Items |
|---|---|
| Assets | Bank 39,400.00; Members Receivable 5,015.00; Input GST 1,800.00 |
| Liabilities and funds | General Fund 50,000.00; Sinking Fund 725.00; Repair Fund 400.00; TDS Payable 200.00; Income and Expenditure deficit (5,110.00) |

### GST tests

- Society GST on, 18%, limit ₹7,500. Monthly taxable ₹7,000: GST ₹0.
- Monthly taxable ₹8,000: GST ₹1,440, split ₹720 and ₹720.
- GST total of 101 paise: CGST 50 paise and SGST 51 paise.

## 13. Statutory note

Rates and limits are user-entered, dated settings. Screens may show a short note saying they must be confirmed for the society. Do not present any seeded legal value as current law.
