# CruSam Society Workspace: Build Instructions

**This replaces the earlier version of this plan.** Follow this file and everything in `society_plan/`.

## Start here

You are implementing a separate **Society** workspace inside the existing CruSam Flutter desktop app.

Read these before writing code:

1. [Execution rules](society_plan/00_EXECUTION_RULES.md)
2. [Progress tracker](society_plan/PROGRESS.md)
3. [Architecture contracts](society_plan/01_ARCHITECTURE_CONTRACTS.md)
4. [Database schema](society_plan/02_SCHEMA.sql)
5. [Accounting rules](society_plan/03_ACCOUNTING_RULES.md)
6. [UI specification](society_plan/04_UI_SPEC.md)
7. [Build phases](society_plan/05_PHASES.md)

**Start with the first unfinished phase in `PROGRESS.md` and build through Phase 9 in one continuous run.** Verify and report each phase, then continue automatically. Stop only for a blocker listed in the execution rules or after the final report.

If you made changes from the earlier plan, compare them with these documents first. Bring them into line when the required edits are inside the allowed scope. Stop only if they require a forbidden edit or could lose work.

## Goal

The user can switch between **CruSam** and **Society** from the top bar. Society has its own dashboard, navigation, screens, database, documents and backups. Existing CruSam behaviour stays unchanged.

The target user manages the books of **many housing societies** from one Windows desktop app.

## In scope

- Multi-society setup and overview
- Units, unit types, members, tenants and Excel import
- Charge heads, billing rules, meters and bill runs
- Receipts, advances, refundable deposits, credit and debit notes, unidentified receipts
- Late-payment interest, dues, ageing and reminders
- Non-member income
- Vendors, expense bills, payments, TDS, budget and comparison
- Bank and cash, transfers, reconciliation and fixed deposits
- GST and TDS registers
- Chart of accounts, journals, ledger enquiry and trial balance
- Income and Expenditure, Balance Sheet, Receipts and Payments
- Year-end close and reopen
- PDF, Excel, email, society backup and restore-as-new
- About & Credits screen thanking ADDA

## Out of scope

Do not build resident login, a phone app, polls, conversations, helpdesk, visitor or amenity booking, SMS, WhatsApp, online payment collection, cloud sync, Society MCP tools, AI features, user roles or approval workflows.

## Reference and originality

ADDA gave permission to use its product as a reference, with thanks shown in CruSam. Use it only to understand what society software needs.

- Do not access or integrate with ADDA.
- Do not copy its code, text, layout, icons, colours, document formats or data.
- Build CruSam's own design and wording.
- Use fictional data in code and tests.

## Non-negotiable technical decisions

| Topic | Decision |
|---|---|
| Workspace source | URL path. `/society` means Society |
| Database | Separate `society.db` |
| Data isolation | Required `society_id` |
| Accounting source of truth | Double-entry journal |
| Money | Integer paise |
| Posted records | Reverse, never edit or delete |
| State | Local screen controllers plus `SocietyContext` |
| Dependencies | No changes |
| Existing app | Only the three files named in the execution rules may change |

## Finish condition

The module is complete only when Phase 9 passes its tests and manual acceptance list, every placeholder is gone, and `PROGRESS.md` contains every phase report.
