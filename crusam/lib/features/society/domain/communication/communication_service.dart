import 'dart:convert';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:crusam/core/email/gmail_service.dart';
import '../../core/money.dart';
import '../../data/models/member_models.dart';
import '../../data/models/society_models.dart';
import '../../data/repositories/society_repository.dart';
import '../../documents/pdf/member_bill_pdf.dart';
import '../../documents/pdf/receipt_pdf.dart';
import '../../documents/pdf/unit_statement_pdf.dart';
import '../billing/billing_service.dart';
import '../collections/collection_service.dart';

typedef EmailSender = Future<String> Function({
  required String to,
  String cc,
  required String subject,
  required String bodyText,
  required Uint8List pdfBytes,
  required String attachmentFilename,
});

class EmailLogRow {
  final int id;
  final int societyId;
  final int? batchId;
  final String docType;
  final int? docId;
  final int? unitId;
  final String toAddress;
  final String? ccAddress;
  final String subject;
  final String? attachmentName;
  final String status;
  final String? providerMessageId;
  final String? errorMessage;
  final String createdAt;

  const EmailLogRow({
    required this.id,
    required this.societyId,
    this.batchId,
    required this.docType,
    this.docId,
    this.unitId,
    required this.toAddress,
    this.ccAddress,
    required this.subject,
    this.attachmentName,
    required this.status,
    this.providerMessageId,
    this.errorMessage,
    required this.createdAt,
  });

  factory EmailLogRow.fromRow(Map<String, Object?> row) {
    return EmailLogRow(
      id: row['id'] as int,
      societyId: row['society_id'] as int,
      batchId: row['batch_id'] as int?,
      docType: row['doc_type'] as String,
      docId: row['doc_id'] as int?,
      unitId: row['unit_id'] as int?,
      toAddress: row['to_address'] as String,
      ccAddress: row['cc_address'] as String?,
      subject: row['subject'] as String,
      attachmentName: row['attachment_name'] as String?,
      status: row['status'] as String,
      providerMessageId: row['provider_message_id'] as String?,
      errorMessage: row['error_message'] as String?,
      createdAt: row['created_at'] as String,
    );
  }
}

class ReminderBatchRow {
  final int id;
  final int societyId;
  final String subject;
  final String body;
  final String filterJson;
  final String createdAt;

  const ReminderBatchRow({
    required this.id,
    required this.societyId,
    required this.subject,
    required this.body,
    required this.filterJson,
    required this.createdAt,
  });

  factory ReminderBatchRow.fromRow(Map<String, Object?> row) {
    return ReminderBatchRow(
      id: row['id'] as int,
      societyId: row['society_id'] as int,
      subject: row['subject'] as String,
      body: row['body'] as String,
      filterJson: row['filter_json'] as String,
      createdAt: row['created_at'] as String,
    );
  }
}

class DocumentFooterRow {
  final int id;
  final int societyId;
  final String docType;
  final String effectiveFrom;
  final String footerText;

  const DocumentFooterRow({
    required this.id,
    required this.societyId,
    required this.docType,
    required this.effectiveFrom,
    required this.footerText,
  });

  factory DocumentFooterRow.fromRow(Map<String, Object?> row) {
    return DocumentFooterRow(
      id: row['id'] as int,
      societyId: row['society_id'] as int,
      docType: row['doc_type'] as String,
      effectiveFrom: row['effective_from'] as String,
      footerText: row['footer_text'] as String,
    );
  }
}

class CommunicationService {
  final Database db;
  final SocietyRepository _socRepo;
  final BillingService _billing;
  final CollectionService _collections;
  final EmailSender? _customSender;

  CommunicationService(
    this.db,
    this._billing,
    this._collections, {
    EmailSender? emailSender,
  })  : _socRepo = SocietyRepository(db),
        _customSender = emailSender;

  Future<String> _dispatchEmail({
    required String to,
    String cc = '',
    required String subject,
    required String bodyText,
    required Uint8List pdfBytes,
    required String attachmentFilename,
  }) async {
    final sender = _customSender;
    if (sender != null) {
      return await sender(
        to: to,
        cc: cc,
        subject: subject,
        bodyText: bodyText,
        pdfBytes: pdfBytes,
        attachmentFilename: attachmentFilename,
      );
    }
    return await GmailService.instance.sendPdfEmail(
      to: to,
      cc: cc,
      subject: subject,
      bodyText: bodyText,
      pdfBytes: pdfBytes,
      attachmentFilename: attachmentFilename,
    );
  }

  // ----------------------------------------------------------------------
  // 1. Send Member Bill
  // ----------------------------------------------------------------------
  Future<int> sendBillEmail({
    required int societyId,
    required int billId,
    String? overrideTo,
    String? overrideCc,
  }) async {
    final society = await _socRepo.getSociety(societyId);
    if (society == null) throw Exception('Society not found');

    final bill = await _billing.getBill(billId);
    if (bill == null) throw Exception('Bill not found');

    // Find recipient email
    String toAddress = (overrideTo ?? '').trim();
    if (toAddress.isEmpty) {
      final unitRows = await db.rawQuery('''
        SELECT p.email
        FROM unit_people up
        JOIN people p ON p.id = up.person_id
        WHERE up.unit_id = ? AND up.to_date IS NULL AND up.is_bill_to = 1
        LIMIT 1
      ''', [bill.unitId]);
      if (unitRows.isNotEmpty && unitRows.first['email'] != null) {
        toAddress = (unitRows.first['email'] as String).trim();
      }
    }

    if (toAddress.isEmpty) {
      return await _logEmail(
        societyId: societyId,
        docType: 'member_bill',
        docId: billId,
        unitId: bill.unitId,
        toAddress: 'unknown@recipient.local',
        ccAddress: overrideCc,
        subject: 'Maintenance Bill ${bill.billNo ?? ""}',
        attachmentName: 'Bill_${bill.billNo ?? billId}.pdf',
        status: 'failed',
        errorMessage: 'No email address registered for unit bill recipient',
      );
    }

    final pdfBytes = await MemberBillPdf.generatePdf(society: society, bill: bill);
    final filename = 'Bill_${bill.billNo ?? billId}.pdf';
    final subject = '${society.name} - Maintenance Bill ${bill.billNo ?? ""}';
    final bodyText = 'Dear Member,\n\nPlease find attached maintenance bill ${bill.billNo ?? ""} for unit ${bill.unitId}. Total amount due: ${formatPaise(bill.totalPaise)}.\n\nThank you,\n${society.name} Management Committee';

    try {
      final msgId = await _dispatchEmail(
        to: toAddress,
        cc: overrideCc ?? '',
        subject: subject,
        bodyText: bodyText,
        pdfBytes: pdfBytes,
        attachmentFilename: filename,
      );

      return await _logEmail(
        societyId: societyId,
        docType: 'member_bill',
        docId: billId,
        unitId: bill.unitId,
        toAddress: toAddress,
        ccAddress: overrideCc,
        subject: subject,
        attachmentName: filename,
        status: 'sent',
        providerMessageId: msgId,
      );
    } catch (e) {
      return await _logEmail(
        societyId: societyId,
        docType: 'member_bill',
        docId: billId,
        unitId: bill.unitId,
        toAddress: toAddress,
        ccAddress: overrideCc,
        subject: subject,
        attachmentName: filename,
        status: 'failed',
        errorMessage: e.toString(),
      );
    }
  }

  // ----------------------------------------------------------------------
  // 2. Send Member Receipt
  // ----------------------------------------------------------------------
  Future<int> sendReceiptEmail({
    required int societyId,
    required int receiptId,
    String? overrideTo,
    String? overrideCc,
  }) async {
    final society = await _socRepo.getSociety(societyId);
    if (society == null) throw Exception('Society not found');

    final receipt = await _collections.getReceipt(receiptId);
    if (receipt == null) throw Exception('Receipt not found');

    String toAddress = (overrideTo ?? '').trim();
    if (toAddress.isEmpty) {
      final unitRows = await db.rawQuery('''
        SELECT p.email
        FROM unit_people up
        JOIN people p ON p.id = up.person_id
        WHERE up.unit_id = ? AND up.to_date IS NULL AND up.is_bill_to = 1
        LIMIT 1
      ''', [receipt.unitId]);
      if (unitRows.isNotEmpty && unitRows.first['email'] != null) {
        toAddress = (unitRows.first['email'] as String).trim();
      }
    }

    if (toAddress.isEmpty) {
      return await _logEmail(
        societyId: societyId,
        docType: 'member_receipt',
        docId: receiptId,
        unitId: receipt.unitId,
        toAddress: 'unknown@recipient.local',
        ccAddress: overrideCc,
        subject: 'Receipt ${receipt.receiptNo}',
        attachmentName: 'Receipt_${receipt.receiptNo}.pdf',
        status: 'failed',
        errorMessage: 'No email address registered for unit recipient',
      );
    }

    final allocations = await _collections.listAllocations(societyId, sourceType: 'receipt', sourceId: receiptId);
    final pdfBytes = await ReceiptPdf.generateBytes(society: society, receipt: receipt, allocations: allocations);
    final filename = 'Receipt_${receipt.receiptNo}.pdf';
    final subject = '${society.name} - Payment Receipt ${receipt.receiptNo}';
    final bodyText = 'Dear Member,\n\nWe acknowledge receipt of ${formatPaise(receipt.amountPaise)} towards maintenance dues. Please find the attached receipt.\n\nThank you,\n${society.name} Management Committee';

    try {
      final msgId = await _dispatchEmail(
        to: toAddress,
        cc: overrideCc ?? '',
        subject: subject,
        bodyText: bodyText,
        pdfBytes: pdfBytes,
        attachmentFilename: filename,
      );

      return await _logEmail(
        societyId: societyId,
        docType: 'member_receipt',
        docId: receiptId,
        unitId: receipt.unitId,
        toAddress: toAddress,
        ccAddress: overrideCc,
        subject: subject,
        attachmentName: filename,
        status: 'sent',
        providerMessageId: msgId,
      );
    } catch (e) {
      return await _logEmail(
        societyId: societyId,
        docType: 'member_receipt',
        docId: receiptId,
        unitId: receipt.unitId,
        toAddress: toAddress,
        ccAddress: overrideCc,
        subject: subject,
        attachmentName: filename,
        status: 'failed',
        errorMessage: e.toString(),
      );
    }
  }

  // ----------------------------------------------------------------------
  // 3. Send Unit Statement
  // ----------------------------------------------------------------------
  Future<int> sendStatementEmail({
    required int societyId,
    required int unitId,
    required String fromDate,
    required String toDate,
    String? overrideTo,
    String? overrideCc,
  }) async {
    final society = await _socRepo.getSociety(societyId);
    if (society == null) throw Exception('Society not found');

    final rows = await _collections.getUnitStatement(societyId, unitId, fromDate: fromDate, toDate: toDate);

    // Get unit
    final unitMapRows = await db.query('units', where: 'id = ?', whereArgs: [unitId]);
    if (unitMapRows.isEmpty) throw Exception('Unit not found');
    final unit = UnitRow.fromMap(unitMapRows.first);

    String toAddress = (overrideTo ?? '').trim();
    if (toAddress.isEmpty) {
      final unitRows = await db.rawQuery('''
        SELECT p.email
        FROM unit_people up
        JOIN people p ON p.id = up.person_id
        WHERE up.unit_id = ? AND up.to_date IS NULL AND up.is_bill_to = 1
        LIMIT 1
      ''', [unitId]);
      if (unitRows.isNotEmpty && unitRows.first['email'] != null) {
        toAddress = (unitRows.first['email'] as String).trim();
      }
    }

    if (toAddress.isEmpty) {
      return await _logEmail(
        societyId: societyId,
        docType: 'member_statement',
        unitId: unitId,
        toAddress: 'unknown@recipient.local',
        ccAddress: overrideCc,
        subject: 'Account Statement',
        attachmentName: 'Statement_Unit_$unitId.pdf',
        status: 'failed',
        errorMessage: 'No email address registered for unit recipient',
      );
    }

    final pdfBytes = await UnitStatementPdf.generateBytes(
      society: society,
      unit: unit,
      rows: rows,
      fromDate: fromDate,
      toDate: toDate,
    );
    final filename = 'Statement_Unit_${unitId}_$fromDate.pdf';
    final subject = '${society.name} - Statement of Account for Unit ${unit.unitNo}';
    final bodyText = 'Dear Member,\n\nPlease find attached your Statement of Account for the period $fromDate to $toDate.\n\nThank you,\n${society.name} Management Committee';

    try {
      final msgId = await _dispatchEmail(
        to: toAddress,
        cc: overrideCc ?? '',
        subject: subject,
        bodyText: bodyText,
        pdfBytes: pdfBytes,
        attachmentFilename: filename,
      );

      return await _logEmail(
        societyId: societyId,
        docType: 'member_statement',
        unitId: unitId,
        toAddress: toAddress,
        ccAddress: overrideCc,
        subject: subject,
        attachmentName: filename,
        status: 'sent',
        providerMessageId: msgId,
      );
    } catch (e) {
      return await _logEmail(
        societyId: societyId,
        docType: 'member_statement',
        unitId: unitId,
        toAddress: toAddress,
        ccAddress: overrideCc,
        subject: subject,
        attachmentName: filename,
        status: 'failed',
        errorMessage: e.toString(),
      );
    }
  }

  // ----------------------------------------------------------------------
  // 4. Send Dues Reminders Batch
  // ----------------------------------------------------------------------
  Future<int> sendReminderBatch({
    required int societyId,
    required String subject,
    required String bodyTemplate,
    required List<int> unitIds,
    String asOfDate = '',
  }) async {
    final society = await _socRepo.getSociety(societyId);
    if (society == null) throw Exception('Society not found');

    final batchId = await db.insert('reminder_batches', {
      'society_id': societyId,
      'subject': subject,
      'body': bodyTemplate,
      'filter_json': jsonEncode({'unit_ids': unitIds, 'as_of_date': asOfDate}),
      'created_at': DateTime.now().toIso8601String(),
    });

    final allDues = await _collections.getDuesSummary(societyId, asOfDate: asOfDate.isEmpty ? null : asOfDate);
    final duesByUnit = {for (final d in allDues) d.unitId: d};

    for (final unitId in unitIds) {
      final dues = duesByUnit[unitId];
      if (dues == null || dues.netDuePaise <= 0) continue;

      // Find unit primary email
      final memberRows = await db.rawQuery('''
        SELECT u.unit_no, p.full_name as member_name, p.email
        FROM units u
        LEFT JOIN unit_people up ON up.unit_id = u.id AND up.to_date IS NULL AND up.is_bill_to = 1
        LEFT JOIN people p ON p.id = up.person_id
        WHERE u.id = ?
      ''', [unitId]);

      if (memberRows.isEmpty) continue;
      final mRow = memberRows.first;
      final unitNo = mRow['unit_no'] as String? ?? unitId.toString();
      final memberName = mRow['member_name'] as String? ?? 'Member';
      final email = (mRow['email'] as String? ?? '').trim();

      // Render merged body
      final mergedBody = bodyTemplate
          .replaceAll('{{unit_no}}', unitNo)
          .replaceAll('{{member_name}}', memberName)
          .replaceAll('{{due_amount}}', formatPaise(dues.netDuePaise));

      final mergedSubject = subject.replaceAll('{{unit_no}}', unitNo);

      if (email.isEmpty) {
        await _logEmail(
          societyId: societyId,
          batchId: batchId,
          docType: 'dues_reminder',
          unitId: unitId,
          toAddress: 'missing@email.local',
          subject: mergedSubject,
          status: 'failed',
          errorMessage: 'No email address registered for unit $unitNo',
        );
        continue;
      }

      final noticePdfBytes = Uint8List(0);
      try {
        final msgId = await _dispatchEmail(
          to: email,
          subject: mergedSubject,
          bodyText: mergedBody,
          pdfBytes: noticePdfBytes,
          attachmentFilename: 'Reminder_$unitNo.txt',
        );

        await _logEmail(
          societyId: societyId,
          batchId: batchId,
          docType: 'dues_reminder',
          unitId: unitId,
          toAddress: email,
          subject: mergedSubject,
          status: 'sent',
          providerMessageId: msgId,
        );
      } catch (e) {
        await _logEmail(
          societyId: societyId,
          batchId: batchId,
          docType: 'dues_reminder',
          unitId: unitId,
          toAddress: email,
          subject: mergedSubject,
          status: 'failed',
          errorMessage: e.toString(),
        );
      }
    }

    return batchId;
  }

  // ----------------------------------------------------------------------
  // 5. Query Logs & Footers
  // ----------------------------------------------------------------------
  Future<List<EmailLogRow>> listEmailLogs(int societyId, {int limit = 100, int offset = 0}) async {
    final rows = await db.query(
      'email_log',
      where: 'society_id = ?',
      whereArgs: [societyId],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(EmailLogRow.fromRow).toList();
  }

  Future<List<ReminderBatchRow>> listReminderBatches(int societyId) async {
    final rows = await db.query(
      'reminder_batches',
      where: 'society_id = ?',
      whereArgs: [societyId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(ReminderBatchRow.fromRow).toList();
  }

  Future<String?> getDocumentFooter(int societyId, String docType, String date) async {
    final rows = await db.rawQuery('''
      SELECT footer_text
      FROM document_footers
      WHERE society_id = ? AND doc_type = ? AND effective_from <= ?
      ORDER BY effective_from DESC
      LIMIT 1
    ''', [societyId, docType, date]);
    if (rows.isEmpty) return null;
    return rows.first['footer_text'] as String?;
  }

  Future<void> setDocumentFooter(
    int societyId,
    String docType,
    String effectiveFrom,
    String footerText,
  ) async {
    await db.insert(
      'document_footers',
      {
        'society_id': societyId,
        'doc_type': docType,
        'effective_from': effectiveFrom,
        'footer_text': footerText,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<DocumentFooterRow>> listDocumentFooters(int societyId) async {
    final rows = await db.query(
      'document_footers',
      where: 'society_id = ?',
      whereArgs: [societyId],
      orderBy: 'effective_from DESC',
    );
    return rows.map(DocumentFooterRow.fromRow).toList();
  }

  Future<int> _logEmail({
    required int societyId,
    int? batchId,
    required String docType,
    int? docId,
    int? unitId,
    required String toAddress,
    String? ccAddress,
    required String subject,
    String? attachmentName,
    required String status,
    String? providerMessageId,
    String? errorMessage,
  }) async {
    return await db.insert('email_log', {
      'society_id': societyId,
      'batch_id': batchId,
      'doc_type': docType,
      'doc_id': docId,
      'unit_id': unitId,
      'to_address': toAddress,
      'cc_address': ccAddress,
      'subject': subject,
      'attachment_name': attachmentName,
      'status': status,
      'provider_message_id': providerMessageId,
      'error_message': errorMessage,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
