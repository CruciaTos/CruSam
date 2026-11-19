# CruSam Society Automation & Optimisation: Build Instructions

You are extending the **finished Society workspace** (`crusam/lib/features/society/`, plan in `society_plan/`, all 9 phases done, 114 tests passing). This plan adds an **automation layer** and **speed/usability optimisations**. It does not change accounting rules.

## Start here

Read in this order before writing code:

1. [Execution rules](society_automation_plan/00_EXECUTION_RULES.md)
2. [Progress tracker](society_automation_plan/PROGRESS.md)
3. [Automation architecture](society_automation_plan/01_ARCHITECTURE.md)
4. [Schema migration m002](society_automation_plan/02_SCHEMA_M002.sql)
5. [Automation specifications](society_automation_plan/03_AUTOMATION_SPECS.md)
6. [UI specification](society_automation_plan/04_UI_SPEC.md)
7. [Build phases](society_automation_plan/05_PHASES.md)

**Start at the first unfinished phase in `PROGRESS.md` and build through Phase A8 in one continuous run.** Verify and report each phase, then continue. Stop only for a blocker listed in the execution rules or after the final report.

## Why this exists

The target user keeps the books of **many housing societies** from one Windows desktop app. Today every step is manual: enter meters, run bills, key receipts from bank statements, chase dues, key recurring vendor bills, remember GST/TDS/FD dates, and check nothing was missed before closing the month. With 10+ societies that is hundreds of repetitive actions a month and the main source of mistakes.

## Goal

1. **Remove repetitive work**: recurring things draft themselves; bank statements turn into matched receipts; reminders queue themselves.
2. **Tell the user what needs attention today** across all societies, instead of making them hunt.
3. **Catch mistakes early**: duplicates, outliers, missed steps, unbalanced books.
4. **Make heavy screens fast** at 1,000+ units and years of data.

## Core principle: automation proposes, the user approves

The books are legal records. Therefore:

- Default automation mode is **Suggest**. Money is never posted unattended unless the user turned a specific automation to **Auto** for a specific society.
- Everything an automation does goes through the **existing domain services** (`BillingService`, `CollectionService`, `ExpenseService`, `BankService`, `CommunicationService`, `BackupService`). Never write SQL that posts journals. Never bypass `LedgerService`.
- Every automated action is logged in `automation_runs` and `audit_log`, is attributable ("by automation: bank-match"), and is reversible with the normal reverse flow.
- If anything is uncertain, create an **Inbox task** for the user instead of acting.

## In scope

- Automation engine, scheduler, per-society automation settings, Inbox of tasks and findings
- Today screen and cross-society Portfolio dashboard
- Month-End Command Centre with auto-detected checklist
- Recurring bill-run drafts, meter-reading assistance
- Bank statement auto-matching with learned rules, receipt drafts, unidentified handling
- Dues automation: reminder ladder, promise-to-pay tracking, interest preview
- Recurring vendor bills, payment-run suggestions, due calendar, GST/TDS/FD deadline tracker
- Anomaly and duplicate detection, data-quality checks
- Smart Excel import (column auto-mapping, saved mappings, dry-run, error file), fast bulk-entry grids
- Global search and command palette (Ctrl+K)
- Scheduled auto-backup with verification
- Performance work and benchmarks

## Out of scope

Do not build: cloud sync, background Windows services or tray agents (automation runs only while CruSam is open), SMS, WhatsApp, online payments, resident login, phone app, AI/LLM features, Society MCP tools, user roles or approval chains, anything that auto-posts money without the explicit Auto setting. (A Society MCP/Claude layer is a possible later project and must not be started here.)

## Non-negotiable technical decisions

| Topic | Decision |
|---|---|
| Database | Same `society.db`, schema version **2** via migration `m002`, `onUpgrade` from 1 |
| Existing tables | Not altered. New tables only |
| Money | Integer paise, exactly as before |
| Data isolation | Every new table has required `society_id` (except `automation_runs.society_id` nullable for global jobs) |
| Scheduling | In-app only, idempotent, dedupe key per (society, kind, period) |
| Dependencies | No changes |
| Existing app files | Only the files named in the execution rules |

## Finish condition

Complete when Phase A8 passes its tests and acceptance list, `flutter analyze` is clean, every automation has a working off / suggest / auto switch, no placeholders remain, and `PROGRESS.md` holds every phase report.
