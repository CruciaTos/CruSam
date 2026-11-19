import 'package:crusam/features/society/data/models/society_models.dart';

class AccountGroup {
  final int id;
  final int societyId;
  final String accountType; // 'asset','liability','income','expense'
  final String code;
  final String name;
  final int? parentId;
  final String? systemKey;
  final int sortOrder;
  final bool isActive;

  const AccountGroup({
    required this.id,
    required this.societyId,
    required this.accountType,
    required this.code,
    required this.name,
    this.parentId,
    this.systemKey,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory AccountGroup.fromMap(Map<String, Object?> map) {
    return AccountGroup(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      accountType: map['account_type'] as String,
      code: map['code'] as String,
      name: map['name'] as String,
      parentId: map['parent_id'] as int?,
      systemKey: map['system_key'] as String?,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      isActive: (map['is_active'] as int? ?? 1) == 1,
    );
  }
}

class Account {
  final int id;
  final int societyId;
  final int groupId;
  final String code;
  final String name;
  final String accountKind;
  final String? systemKey;
  final bool isActive;
  final String createdAt;
  final String updatedAt;

  String get accountType {
    if (code.startsWith('1')) return 'asset';
    if (code.startsWith('2')) return 'liability';
    if (code.startsWith('3')) return 'income';
    return 'expense';
  }

  const Account({
    required this.id,
    required this.societyId,
    required this.groupId,
    required this.code,
    required this.name,
    required this.accountKind,
    this.systemKey,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Account.fromMap(Map<String, Object?> map) {
    return Account(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      groupId: map['group_id'] as int,
      code: map['code'] as String,
      name: map['name'] as String,
      accountKind: map['account_kind'] as String,
      systemKey: map['system_key'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdAt: (map['created_at'] as String?) ?? '',
      updatedAt: (map['updated_at'] as String?) ?? '',
    );
  }
}

class AccountGroupDraft {
  final String accountType;
  final String code;
  final String name;
  final int? parentId;
  final String? systemKey;
  final int sortOrder;
  final bool isActive;

  const AccountGroupDraft({
    required this.accountType,
    required this.code,
    required this.name,
    this.parentId,
    this.systemKey,
    this.sortOrder = 0,
    this.isActive = true,
  });

  Map<String, Object?> toMap(int societyId) {
    return {
      'society_id': societyId,
      'account_type': accountType,
      'code': code.trim(),
      'name': name.trim(),
      'parent_id': parentId,
      'system_key': systemKey,
      'sort_order': sortOrder,
      'is_active': isActive ? 1 : 0,
    };
  }
}

class AccountDraft {
  final int groupId;
  final String code;
  final String name;
  final String accountKind;
  final String? systemKey;
  final bool isActive;

  const AccountDraft({
    required this.groupId,
    required this.code,
    required this.name,
    this.accountKind = 'general',
    this.systemKey,
    this.isActive = true,
  });

  Map<String, Object?> toMap(int societyId) {
    return {
      'society_id': societyId,
      'group_id': groupId,
      'code': code.trim(),
      'name': name.trim(),
      'account_kind': accountKind,
      'system_key': systemKey,
      'is_active': isActive ? 1 : 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}

class AccountTreeGroup {
  final AccountGroup group;
  final List<Account> accounts;
  final List<AccountTreeGroup> children;

  const AccountTreeGroup({
    required this.group,
    required this.accounts,
    this.children = const [],
  });
}

class JournalLineDraft {
  final int accountId;
  final int debitPaise;
  final int creditPaise;
  final int? unitId;
  final int? vendorId;
  final int? partyId;
  final String? note;

  const JournalLineDraft({
    required this.accountId,
    this.debitPaise = 0,
    this.creditPaise = 0,
    this.unitId,
    this.vendorId,
    this.partyId,
    this.note,
  });
}

class JournalDraft {
  final int societyId;
  final String entryDate;
  final String sourceType;
  final int? sourceId;
  final String narration;
  final List<JournalLineDraft> lines;

  const JournalDraft({
    required this.societyId,
    required this.entryDate,
    required this.sourceType,
    this.sourceId,
    required this.narration,
    required this.lines,
  });
}

class PostedJournal {
  final int id;
  final int fyId;
  final String entryNo;

  const PostedJournal({
    required this.id,
    required this.fyId,
    required this.entryNo,
  });
}

class JournalEntryRow {
  final int id;
  final String entryNo;
  final String entryDate;
  final String sourceType;
  final int? sourceId;
  final String narration;
  final int debitTotalPaise;
  final String status;

  const JournalEntryRow({
    required this.id,
    required this.entryNo,
    required this.entryDate,
    required this.sourceType,
    this.sourceId,
    required this.narration,
    required this.debitTotalPaise,
    required this.status,
  });
}

class JournalLineDetail {
  final int id;
  final int lineNo;
  final int accountId;
  final String accountCode;
  final String accountName;
  final int debitPaise;
  final int creditPaise;
  final int? unitId;
  final String? unitNo;
  final int? vendorId;
  final String? vendorName;
  final int? partyId;
  final String? partyName;
  final String? note;

  const JournalLineDetail({
    required this.id,
    required this.lineNo,
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.debitPaise,
    required this.creditPaise,
    this.unitId,
    this.unitNo,
    this.vendorId,
    this.vendorName,
    this.partyId,
    this.partyName,
    this.note,
  });
}

class JournalEntryDetail {
  final int id;
  final int societyId;
  final int fyId;
  final String entryNo;
  final String entryDate;
  final String sourceType;
  final int? sourceId;
  final String narration;
  final String status;
  final int? reversalOfId;
  final int? reversedById;
  final List<JournalLineDetail> lines;

  const JournalEntryDetail({
    required this.id,
    required this.societyId,
    required this.fyId,
    required this.entryNo,
    required this.entryDate,
    required this.sourceType,
    this.sourceId,
    required this.narration,
    required this.status,
    this.reversalOfId,
    this.reversedById,
    required this.lines,
  });
}

class JournalFilter {
  final String? fromDate;
  final String? toDate;
  final String? sourceType;
  final String? status;
  final int? accountId;
  final int? unitId;

  const JournalFilter({
    this.fromDate,
    this.toDate,
    this.sourceType,
    this.status,
    this.accountId,
    this.unitId,
  });
}

class LedgerFilter {
  final int? accountId;
  final int? groupId;
  final int? unitId;
  final int? vendorId;
  final int? partyId;
  final String fromDate;
  final String toDate;

  const LedgerFilter({
    this.accountId,
    this.groupId,
    this.unitId,
    this.vendorId,
    this.partyId,
    required this.fromDate,
    required this.toDate,
  });
}

class LedgerLine {
  final int journalId;
  final String entryNo;
  final String date;
  final String narration;
  final String accountCode;
  final String accountName;
  final int debitPaise;
  final int creditPaise;
  final int runningBalancePaise;
  final String sourceType;
  final int? sourceId;

  const LedgerLine({
    required this.journalId,
    required this.entryNo,
    required this.date,
    required this.narration,
    required this.accountCode,
    required this.accountName,
    required this.debitPaise,
    required this.creditPaise,
    required this.runningBalancePaise,
    required this.sourceType,
    this.sourceId,
  });
}

class LedgerResult {
  final int openingBalancePaise;
  final int totalDebitPaise;
  final int totalCreditPaise;
  final int closingBalancePaise;
  final PageResult<LedgerLine> lines;

  const LedgerResult({
    required this.openingBalancePaise,
    required this.totalDebitPaise,
    required this.totalCreditPaise,
    required this.closingBalancePaise,
    required this.lines,
  });
}

class TrialBalanceRow {
  final int accountId;
  final String accountCode;
  final String accountName;
  final String accountType;
  final String groupName;
  final int openingDebitPaise;
  final int openingCreditPaise;
  final int debitPaise;
  final int creditPaise;
  final int closingDebitPaise;
  final int closingCreditPaise;

  const TrialBalanceRow({
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    required this.groupName,
    required this.openingDebitPaise,
    required this.openingCreditPaise,
    required this.debitPaise,
    required this.creditPaise,
    required this.closingDebitPaise,
    required this.closingCreditPaise,
  });
}

class TrialBalance {
  final String fromDate;
  final String toDate;
  final List<TrialBalanceRow> rows;
  final int totalDebitPaise;
  final int totalCreditPaise;
  final int totalOpeningDebitPaise;
  final int totalOpeningCreditPaise;
  final int totalClosingDebitPaise;
  final int totalClosingCreditPaise;

  const TrialBalance({
    required this.fromDate,
    required this.toDate,
    required this.rows,
    required this.totalDebitPaise,
    required this.totalCreditPaise,
    required this.totalOpeningDebitPaise,
    required this.totalOpeningCreditPaise,
    required this.totalClosingDebitPaise,
    required this.totalClosingCreditPaise,
  });

  bool get isBalanced => totalClosingDebitPaise == totalClosingCreditPaise;
}

class OpeningBalanceDraft {
  final int accountId;
  final int debitPaise;
  final int creditPaise;
  final String asOfDate;
  final String? narration;

  const OpeningBalanceDraft({
    required this.accountId,
    this.debitPaise = 0,
    this.creditPaise = 0,
    required this.asOfDate,
    this.narration,
  });
}
