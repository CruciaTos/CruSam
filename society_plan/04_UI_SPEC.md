# 04. UI Specification

Build CruSam's own interface. Do not imitate ADDA's layout, colours, icons or wording.

## 1. Workspace behaviour

| Rule | Exact behaviour |
|---|---|
| Workspace source | `uri.path == '/society'` or starts with `/society/` means Society |
| First Society visit | `/society/overview` |
| Return to Society | Last Society path saved by `WorkspaceMemory` |
| Return to CruSam | Last non-Society path, otherwise `/dashboard` |
| Saved paths | Path only, no query. If a saved path is no longer valid, use the workspace default |
| Phone width | Existing `_MobileShell` unchanged |

### Phase 0 edits

Make only these changes in `shell_screen.dart`:

1. Add `_kSocietyNav` next to `_kNav`, using the tree in section 3.
2. Add to `_ShellScreenState`:

```dart
bool get _isSociety => isSocietyLocation(_currentLocation);
List<_NavItem> get _navItems => _isSociety ? _kSocietyNav : _kNav;
```

3. In `didChangeDependencies`, read `GoRouterState.of(context).uri.path`, store it in `_currentLocation`, record it in `WorkspaceMemory`, and set active path and title from `_navItems`. Society fallback is `/society/overview`; CruSam fallback stays `/dashboard`.
4. Add `items` parameters to `_ExpandedSidebar` and `_CollapsedSidebar`. Pass `_navItems`.
5. Add group labels `Billing` and `Collections` to `_open` defaults.
6. In `_Header`, make the title `Flexible` with one-line ellipsis. After it, add `WorkspaceSwitch`. In Society, add `SocietyPicker`.
7. In Society, hide `_FollowClaudeToggle` and AI Assistant. Keep the window-mode button and user area.
8. If the app enters Society while the AI panel is open, close the panel.
9. In `_CompactHeader`, add `WorkspaceSwitch(compact: true)` before the Claude toggle. Hide the toggle in Society.

Add to `claude_follow_controller.dart`, inside `_canLeaveFor`, immediately after `if (here == route) return true;`:

```dart
if (here == '/society' || here.startsWith('/society/')) return false;
```

Add to `app_router.dart`:

- Import `society_routes.dart`.
- Add `...societyRoutes` at the end of the existing `ShellRoute.routes`.

### `WorkspaceSwitch`

- Two segments: `CruSam` and `Society`.
- Height 34, width 172 normal, 132 compact.
- Selected Society uses `AppColors.amber700` background and white text.
- Selected CruSam uses the shell's existing blue primary colour.
- Unselected text uses slate 400.
- Keyboard focusable with tooltip `Switch workspace`.

### `SocietyPicker`

- Shown only in Society normal header.
- Width 240 at window width 1100 or more; icon button below that.
- Search field inside menu.
- First item `All societies`, then active societies alphabetically.
- Footer item `Manage societies`.
- Selecting a society keeps the same route when it is valid for one society.
- If there are no societies, label is `Add society` and it opens `/society/societies/new`.

## 2. Shared Society widgets

Create these in `shared/widgets/` before building business screens.

| Widget | Required API and behaviour |
|---|---|
| `SocietyPage` | `title`, `subtitle`, `actions`, `filters`, `child`, `requireSociety = true`, `allowAllSocieties = false`. White content on `AppColors.slate50`; 24 padding; keyed by active society id |
| `SocietyRequiredView` | Shown when a page needs one society and none is selected |
| `SocietyEmptyView` | Icon, title, message, optional action |
| `SocietyErrorView` | Message and Retry |
| `SocietyDataTable<T>` | `columns`, `rows`, `total`, `page`, `pageSize`, `onPage`, `onRowTap`, `selection`, loading skeleton, sticky header, horizontal scroll when narrow |
| `SocietyColumn<T>` | `label`, `cell`, `width`, `numeric`, `sortable`, `tooltip` |
| `SocietyFilterBar` | Search plus compact filter controls; debounce search by 300 ms |
| `MoneyField` | Returns paise, right-aligned, accepts commas |
| `PercentField` | Returns basis points |
| `AreaField` | Returns centi-units |
| `SocietyDateField` | Shows `dd/MM/yyyy`, stores ISO |
| `AccountPicker` | Searchable account by code or name, optional filter by kinds |
| `UnitPicker` | Searchable block, unit and bill-to name |
| `VendorPicker` | Searchable vendor by name, code or GSTIN |
| `PartyPicker` | Searchable party by name or GSTIN |
| `StatusChip` | `draft`, `posted`, `reversed`, `open`, `resolved`, `active`, `closed`, `sent`, `failed` |
| `AmountSummary` | Label/value rows with total emphasis |
| `ReverseDialog` | Date and required reason. Receipt version also asks mistake or bounced |
| `ConfirmTypedDialog` | Requires typed word for close or reopen |
| `ExportMenu` | PDF and Excel actions when supported |

Interaction rules:

- Tables show 50 rows per page.
- Amounts are right-aligned and use tabular monospace only where needed.
- Save and Post buttons disable while busy.
- Validation appears beside the field. Service failures appear in a page-level error strip.
- Success uses a snackbar with the document number.
- Forms warn before leaving with unsaved changes.
- Destructive or financial actions state their result before confirming.
- Dates default to today except report ranges, which default to the current month.
- All tab, Enter and Escape behaviour must work on desktop.
- Minimum supported content width is 760. Tables scroll inside their cards; the page must not overflow.

## 3. Sidebar

```dart
const _kSocietyNav = <_NavItem>[
  _Route('/society/overview', Icons.space_dashboard_outlined, 'Overview'),
  _Route('/society/societies', Icons.apartment_outlined, 'Societies'),
  _Group(Icons.people_alt_outlined, 'Members & Units', [
    _Route('/society/units', Icons.meeting_room_outlined, 'Units'),
    _Route('/society/unit-types', Icons.category_outlined, 'Unit Types'),
    _Route('/society/members', Icons.groups_outlined, 'Members'),
    _Route('/society/import', Icons.upload_file_outlined, 'Import'),
  ]),
  _Group(Icons.request_quote_outlined, 'Billing', [
    _Route('/society/charge-heads', Icons.list_alt_outlined, 'Charge Heads'),
    _Route('/society/billing-rules', Icons.rule_outlined, 'Billing Rules'),
    _Route('/society/meters', Icons.speed_outlined, 'Meter Readings'),
    _Route('/society/bill-runs', Icons.playlist_add_check_outlined, 'Bill Runs'),
    _Route('/society/bills', Icons.receipt_long_outlined, 'Bills'),
  ]),
  _Group(Icons.payments_outlined, 'Collections', [
    _Route('/society/receipts', Icons.point_of_sale_outlined, 'Receipts'),
    _Route('/society/notes', Icons.note_alt_outlined, 'Credit & Debit Notes'),
    _Route('/society/unidentified', Icons.help_outline, 'Unidentified Receipts'),
    _Route('/society/dues', Icons.notification_important_outlined, 'Dues & Reminders'),
  ]),
  _Route('/society/other-income', Icons.add_card_outlined, 'Other Income'),
  _Group(Icons.shopping_bag_outlined, 'Expenses', [
    _Route('/society/vendors', Icons.storefront_outlined, 'Vendors'),
    _Route('/society/expenses', Icons.receipt_outlined, 'Expense Bills'),
    _Route('/society/payments', Icons.outbox_outlined, 'Payments'),
    _Route('/society/budget', Icons.savings_outlined, 'Budget'),
    _Route('/society/expense-comparison', Icons.compare_arrows_outlined, 'Expense Comparison'),
  ]),
  _Group(Icons.account_balance_outlined, 'Bank & Cash', [
    _Route('/society/bank', Icons.account_balance_wallet_outlined, 'Accounts'),
    _Route('/society/transfers', Icons.swap_horiz_outlined, 'Transfers'),
    _Route('/society/reconciliation', Icons.fact_check_outlined, 'Reconciliation'),
    _Route('/society/deposits', Icons.lock_clock_outlined, 'Fixed Deposits'),
    _Route('/society/tax', Icons.percent_outlined, 'GST & TDS'),
  ]),
  _Group(Icons.menu_book_outlined, 'Accounts', [
    _Route('/society/accounts', Icons.account_tree_outlined, 'Chart of Accounts'),
    _Route('/society/journals', Icons.edit_note_outlined, 'Journal Entries'),
    _Route('/society/ledger', Icons.manage_search_outlined, 'Ledger Enquiry'),
    _Route('/society/trial-balance', Icons.balance_outlined, 'Trial Balance'),
    _Route('/society/statements', Icons.summarize_outlined, 'Financial Statements'),
    _Route('/society/year-end', Icons.event_available_outlined, 'Year End'),
  ]),
  _Route('/society/reports', Icons.assessment_outlined, 'Reports'),
  _Route('/society/settings', Icons.tune_outlined, 'Society Settings'),
  _Route('/society/about', Icons.info_outline, 'About & Credits'),
];
```

If `_Route`, `_Group` or `_NavItem` constructors differ, adapt only the syntax.

## 4. Screen catalogue

Each route has one screen file under `screens/`. New and edit pages use child routes.

### Overview and societies

| Route | Content |
|---|---|
| `/society/overview`, all societies | `allowAllSocieties = true`. Table: society, units, billed this month, collected this month, outstanding, bank and cash, last bill run, open FY, attention. Row opens that society |
| `/society/overview`, one society | KPI cards: Billed, Collected, Outstanding, Bank & Cash. Lists: Top dues, cheques not cleared, FDs maturing in 30 days, draft bill runs, setup checklist. Quick actions: New Bill Run, Add Receipt, Add Expense, New Journal. Footer credit link |
| `/society/societies` | `allowAllSocieties = true`. Columns: name, city, registration, units, active FY, status. Action: Add Society |
| `/society/societies/new`, `/:id` | Sections: Identity; Address; Tax; Books. Fields match `societies`. `books_start_date` becomes read-only after any journal exists |

Setup checklist: profile complete; bank account added; opening balances balanced; units added; each active unit has bill-to; charge rules added; interest setting reviewed; document settings reviewed.

### Members and units

| Route | Columns or fields | Actions |
|---|---|---|
| `/society/units` | Block, unit, type, area 1, area 2, occupancy, primary contact, bill-to, balance, status. Filters: block, type, occupancy, active, balance | Add, Export |
| `/society/units/new`, `/:id/edit` | Block, unit no, type, area 1, area 2, floor, occupancy, notes, active | Save |
| `/society/units/:id` | Tabs: Overview, Statement, Bills, Receipts, People, Meters | Add Bill, Add Receipt, Credit Note, Print Statement, Email Statement |
| `/society/unit-types` | Type, units, order, status. Block management card on same screen | Add type, Add block |
| `/society/members` | Name, phone, email, units, roles, status. Filters: role, active, missing email or phone | Add |
| `/society/members/new`, `/:id` | Name, phone, email, alternate email, PAN, GSTIN, address; assignment list | Save, Assign to Unit, End Assignment |
| `/society/import` | Choose type, download template, upload, preview valid/error rows, import | Commit disabled while errors exist |

### Billing

| Route | Content |
|---|---|
| `/society/charge-heads` | Name, account, interest bearing, GST, rate, HSN/SAC, order, status. Add/edit in dialog. System interest head cannot be deleted or changed to another kind |
| `/society/billing-rules` | Group by unit type. Columns: head, rule, rates or percent, fixed, occupancy, effective from, effective to, status. New rule form changes fields by `rule_type`. Editing a used rule means ending it and creating a new one |
| `/society/meters` | Tabs: Types and Slabs, Unit Meters, Readings. Readings grid: unit, meter, previous, current, consumption, reading date, error |
| `/society/bill-runs` | Period, frequency, bill date, due date, bills, total, status. Action: New Bill Run |
| `/society/bill-runs/new` | Step 1 Period. Step 2 Preview. Step 3 Review. Step 4 Post |
| `/society/bill-runs/:id` | Summary, blockers, warnings, table of units and bills. Actions depend on status |
| `/society/bills` | Bill no, date, due, unit, bill-to, period, kind, total, paid, balance, status. Filters: period, unit, status, kind, open only. Actions: New Manual Bill, Bulk Print |
| `/society/bills/new` | Unit, bill date, due date, kind, comment; lines with head, description, amount, GST rate; total. Actions: Post, Post and Collect |
| `/society/bills/:id` | Header, lines, tax, allocations, journal link, interest working. Actions: Print, Email, Reverse |

Bill-run preview must show blocking errors first. Posting is disabled until blockers are zero. Warnings require a confirmation checkbox.

### Collections

| Route | Content |
|---|---|
| `/society/receipts` | Receipt no, date, unit, payer, mode, instrument, bank/cash, amount, TDS, status. Filters: date, unit, mode, status, kind. Actions: New Receipt, Bulk Entry |
| `/society/receipts/new` | Kind; unit; payer; date; mode; instrument no/date/bank; bank/cash; amount; TDS; open bill-line allocation table; unallocated amount; narration. Actions: Post, Post and Print |
| `/society/receipts/bulk` | Grid: unit, date, mode, instrument, bank/cash, amount, TDS, narration. Validate then post all in one transaction using default allocation |
| `/society/receipts/:id` | Details, allocations, journal link. Actions: Print, Email, Allocate Advance, Reverse |
| `/society/notes` | Tabs: Credit Notes, Debit Notes. Filters by date, unit and status |
| `/society/notes/credit/new` | Scope: general, head or selected bill lines. Unit, date, reason, amount, line table when applicable |
| `/society/notes/debit/new` | Uses the manual bill form with `debit_note` kind |
| `/society/unidentified` | Reference, date, amount, mode, instrument, bank/cash, status. Actions: New, Resolve, Reverse |
| `/society/dues` | Tabs: Dues, Ageing, Reminders. Filters: due before, amount range, unit type, head. Select rows and send reminder |

### Other income and expenses

| Route | Content |
|---|---|
| `/society/other-income` | Tabs: Invoices, Receipts, Parties, Statements |
| `/society/other-income/invoices/new` | Party, date, due date, lines with income account, description, HSN/SAC, amount, GST; total |
| `/society/other-income/receipts/new` | Party, open invoices, payment details, allocation |
| `/society/vendors` | Name, code, phone, email, GSTIN, PAN, default expense, balance, status |
| `/society/vendors/new`, `/:id` | Every `vendors` editable field. Detail tabs: Profile, Statement, Bills, Payments, Attachments |
| `/society/expenses` | Voucher, post date, vendor, vendor bill, total, TDS, payable, paid, balance, status |
| `/society/expenses/new` | Vendor, bill no, bill date, post date, due date, line table, TDS section/rate/amount, payee, attachments, narration |
| `/society/payments` | Payment no, date, kind, vendor or expense head, mode, instrument, bank/cash, amount, status |
| `/society/payments/new` | Kind, vendor, open bills, allocation, expense account for direct expense, mode, instrument, bank/cash, payee, attachment, narration |
| `/society/budget` | FY, group, account, budget, actual, variance, variance percent. Actions: Save, Copy Previous Year, Import, Export |
| `/society/expense-comparison` | Choose monthly, quarterly or FY comparison. Account rows and period columns. Export |

### Bank, tax and accounts

| Route | Content |
|---|---|
| `/society/bank` | Balance cards and table: name, bank, masked number, type, balance, uncleared, status. Add creates ledger and bank rows. Book tab has filters from form requirements |
| `/society/transfers` | Transfer list and new-transfer dialog |
| `/society/reconciliation` | Choose account and as-of date. Top reconciliation summary. Tabs: Book Items, Statement Lines, Suggestions. Actions: Import Statement, Mark Cleared, Unclear, Print |
| `/society/deposits` | Active and Closed tabs. Actions: New FD, Accrue Interest, Receive Interest, Close FD |
| `/society/tax` | GST and TDS tabs, period filter, summary and detail, export |
| `/society/accounts` | Tree by type and group. Account table with code, name, kind, opening, balance, status. Tab: Opening Balances |
| `/society/journals` | Entry no, date, source, narration, debit total, status. Actions: New Journal, Reverse manual entry |
| `/society/journals/new` | Date, narration, lines with account, debit, credit, unit/vendor/party as required. Live difference. Post disabled unless zero |
| `/society/journals/:id` | Entry detail and source link |
| `/society/ledger` | Filters: account or group, unit, vendor, party, date. Rows drill to source |
| `/society/trial-balance` | Date range, opening, debit, credit, closing, totals, difference banner |
| `/society/statements` | Tabs: Income & Expenditure, Balance Sheet, Receipts & Payments. Period or as-of date, horizontal or vertical, hide zero, PDF, Excel, drill-down |
| `/society/year-end` | Year selector, checklist, surplus/deficit, appropriations, Close Year, Reopen |

### Reports, settings and about

| Route | Content |
|---|---|
| `/society/reports` | Search and categories from `05_PHASES.md`. Selecting a report opens parameters, preview table, PDF and Excel |
| `/society/settings` | Sections: General, Billing, Interest, GST & TDS, Numbering, Documents, Email, Backup |
| `/society/about` | Product note, data location, version from existing constants if available, credits |

Credits text is `kAddaCreditText` from `core/society_credit.dart`.

## 5. Form field limits

| Field | Rule |
|---|---|
| Name fields | Trimmed, required when listed, maximum 120 |
| Unit no | Trimmed, maximum 30, unique inside block |
| Account code | Digits and hyphen, maximum 12, unique |
| PAN | Empty or `AAAAA9999A` uppercase |
| GSTIN | Empty or 15 characters uppercase |
| IFSC | Empty or `AAAA0XXXXXX` uppercase |
| Email | Empty or basic valid address |
| Phone | Empty or 7 to 15 digits, with optional leading `+` |
| Amount | Must fit positive rule for that field |
| Percent | 0.00 to 100.00 |
| Narration, reason | Maximum 500. Reversal reason required |

## 6. Printed documents

All documents use CruSam layout code, A4 and society details. Do not imitate another product's document.

| Document | Required content |
|---|---|
| Member bill | Title, society header, registration number, GSTIN if used, unit, bill-to, bill no, date, due, period, lines, tax, interest, round-off, total, amount in words, previous due as information, recent receipts if enabled, payment instructions, footer, signatory |
| Member receipt | Title, receipt no, date, unit, payer, mode, instrument, amount, TDS, allocation summary, advance, signature |
| Credit note | Note no, date, unit, reason, lines, tax, total |
| Unit statement | Period, opening, entries, running balance, closing |
| Vendor payment | Voucher no, vendor, bill allocation, instrument, amount |
| Reports | Society header, report title, parameters, generated date, page numbers |
| Financial statements | Society header, period/as-of, schedules where applicable, signatory lines |
