import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import '../../data/models/billing_models.dart';
import '../../data/models/society_models.dart';
import 'member_bill_pdf.dart';

class BulkBillPdf {
  const BulkBillPdf._();

  static Future<Uint8List> generatePdf({
    required Society society,
    required List<Bill> bills,
  }) async {
    final pdf = pw.Document();

    for (final bill in bills) {
      pdf.addPage(MemberBillPdf.buildPage(society: society, bill: bill));
    }

    return pdf.save();
  }
}
