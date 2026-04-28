import 'voucher_row_model.dart';

enum VoucherStatus { draft, saved }

class VoucherModel {
  final int?            id;
  final String          title;
  final String          deptCode;
  final String          date;
  final List<VoucherRowModel> rows;
  final double          baseTotal;
  final double          cgst;
  final double          sgst;
  final double          totalTax;
  final double          roundOff;
  final double          finalTotal;
  final VoucherStatus   status;
  final String          billNo;
  final String          poNo;
  final String          itemDescription;
  final String          clientName;
  final String          clientAddress;
  final String          clientGstin;

  const VoucherModel({
    this.id,
    this.title           = '',
    this.deptCode        = 'I&L',
    this.date            = '',
    this.rows            = const [],
    this.baseTotal       = 0,
    this.cgst            = 0,
    this.sgst            = 0,
    this.totalTax        = 0,
    this.roundOff        = 0,
    this.finalTotal      = 0,
    this.status          = VoucherStatus.draft,
    this.billNo          = '',
    this.poNo            = '',
    this.itemDescription = '',
    this.clientName      = '',
    this.clientAddress   = '',
    this.clientGstin     = '',
  });

  VoucherModel copyWith({
    int? id, String? title, String? deptCode, String? date,
    List<VoucherRowModel>? rows, double? baseTotal, double? cgst, double? sgst,
    double? totalTax, double? roundOff, double? finalTotal, VoucherStatus? status,
    String? billNo, String? poNo, String? itemDescription,
    String? clientName, String? clientAddress, String? clientGstin,
  }) => VoucherModel(
    id: id ?? this.id, title: title ?? this.title, deptCode: deptCode ?? this.deptCode,
    date: date ?? this.date, rows: rows ?? this.rows,
    baseTotal: baseTotal ?? this.baseTotal, cgst: cgst ?? this.cgst, sgst: sgst ?? this.sgst,
    totalTax: totalTax ?? this.totalTax, roundOff: roundOff ?? this.roundOff,
    finalTotal: finalTotal ?? this.finalTotal, status: status ?? this.status,
    billNo: billNo ?? this.billNo, poNo: poNo ?? this.poNo,
    itemDescription: itemDescription ?? this.itemDescription,
    clientName: clientName ?? this.clientName, clientAddress: clientAddress ?? this.clientAddress,
    clientGstin: clientGstin ?? this.clientGstin,
  );

  Map<String, dynamic> toDbMap() => {
  if (id != null) 'id': id,
  'title':            title,
  'description':      '',
  'dept_code':        deptCode,
  'bill_no':          billNo,          // ← add
  'po_no':            poNo,            // ← add
  'item_description': itemDescription, // ← add
  'client_name':      clientName,      // ← add
  'client_address':   clientAddress,   // ← add
  'client_gstin':     clientGstin,     // ← add
  'base_total':       baseTotal,
  'cgst':             cgst,
  'sgst':             sgst,
  'total_tax':        totalTax,
  'raw_total':        baseTotal + totalTax,
  'round_off':        roundOff,
  'final_total':      finalTotal,
  'total_in_words':   '',
  'status':           status.name,
};

  static String _dateOnlyFromDb(dynamic value) {
    final raw = (value?.toString() ?? '').trim();
    if (raw.isEmpty) return '';

    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return parsed.toIso8601String().split('T').first;
    }

    final match = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(raw);
    return match?.group(1) ?? raw;
  }

  factory VoucherModel.fromDbMap(Map<String, dynamic> m, List<VoucherRowModel> rows) => VoucherModel(
  id:              m['id'] as int?,
  title:           (m['title']           as String?) ?? '',
  deptCode:        (m['dept_code']        as String?) ?? '',
  date:            _dateOnlyFromDb(m['created_at']),
  rows:            rows,
  baseTotal:       (m['base_total']       as num?)?.toDouble() ?? 0,
  cgst:            (m['cgst']             as num?)?.toDouble() ?? 0,
  sgst:            (m['sgst']             as num?)?.toDouble() ?? 0,
  totalTax:        (m['total_tax']        as num?)?.toDouble() ?? 0,
  roundOff:        (m['round_off']        as num?)?.toDouble() ?? 0,
  finalTotal:      (m['final_total']      as num?)?.toDouble() ?? 0,
  status:          (m['status'] as String?) == 'saved'
                       ? VoucherStatus.saved : VoucherStatus.draft,
  // ── previously missing ──────────────────────────────────
  billNo:          (m['bill_no']          as String?) ?? '',
  poNo:            (m['po_no']            as String?) ?? '',
  itemDescription: (m['item_description'] as String?) ?? '',
  clientName:      (m['client_name']      as String?) ?? '',
  clientAddress:   (m['client_address']   as String?) ?? '',
  clientGstin:     (m['client_gstin']     as String?) ?? '',
);
}