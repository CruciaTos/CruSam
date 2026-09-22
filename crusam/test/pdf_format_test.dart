// Every PDF the app produces must share one format: A4 pages, invoice-type
// pages in portrait and table-type pages in landscape, whatever the content
// or page count.
//
// Set CRUSAM_PDF_OUT to a folder to also write the generated PDFs there
// for visual inspection.

import 'dart:io';
import 'dart:typed_data';

import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import 'package:crusam/shared/document_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crusam_core/crusam_core.dart';

const _portrait = 'P';
const _landscape = 'L';

/// Page orientations in document order, read from each page's MediaBox.
/// Fails unless every page is A4.
List<String> _orientations(Uint8List pdf) {
  final text = String.fromCharCodes(pdf);
  final boxes = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]')
      .allMatches(text)
      .map((m) => (double.parse(m.group(1)!), double.parse(m.group(2)!)))
      .toList();
  expect(boxes, isNotEmpty, reason: 'no pages found');
  return [
    for (final (w, h) in boxes) ...[
      if ((w - 595.28).abs() < 1 && (h - 841.89).abs() < 1) _portrait
      else if ((w - 841.89).abs() < 1 && (h - 595.28).abs() < 1) _landscape
      else fail('page is not A4: $w x $h'),
    ],
  ];
}

void _save(String name, Uint8List bytes) {
  final dir = Platform.environment['CRUSAM_PDF_OUT'];
  if (dir == null || dir.isEmpty) return;
  File('$dir${Platform.pathSeparator}$name.pdf').writeAsBytesSync(bytes);
}

const _config = CompanyConfigModel();
const _margins = PdfHouseStyle.defaultMargins;

VoucherModel _voucher(int rows) => VoucherModel(
      title: 'Expenses Statement for the month of FEB-2026 & MAR-2026',
      deptCode: 'F&B',
      date: '2026-03-30',
      billNo: 'AE/122/25-26',
      poNo: '4535265458',
      itemDescription: 'Local and outstation travelling expenses with daily '
          'allowance including mobile expenses and material.',
      clientName: 'M/s Diversey India Hygiene Private Ltd.',
      clientAddress: '501,5th flr,Ackruti center point//MIDC Central Road,'
          'Andheri (East)//Mumbai-400093',
      clientGstin: '27AABCC1597Q1Z2',
      baseTotal: 410651,
      cgst: 36958.59,
      sgst: 36958.59,
      totalTax: 73917.18,
      roundOff: -0.18,
      finalTotal: 484568,
      rows: [
        for (var i = 0; i < rows; i++)
          VoucherRowModel(
            id: '$i',
            employeeName: 'Employee Number ${i + 1}',
            amount: 10000.0 + i * 137,
            fromDate: '2026-03-${(i % 28 + 1).toString().padLeft(2, '0')}',
            toDate: '2026-03-${(i % 28 + 1).toString().padLeft(2, '0')}',
            ifscCode: i.isEven ? 'IBKL0000680' : 'SBIN0016484',
            accountNumber: '4381550000${14180 + i}',
            bankDetails: i.isEven ? 'IDBI Bank' : 'State Bank Of India',
            branch: 'Goregaon-West, Mumbai',
          ),
      ],
    );

List<EmployeeModel> _employees(int count) => [
      for (var i = 0; i < count; i++)
        EmployeeModel(
          id: i + 1,
          name: 'Technician Name ${i + 1}',
          pfNo: 'MH/212395/${(i + 10).toString().padLeft(4, '0')}',
          uanNo: '1001985863${(i % 90 + 10)}',
          code: i % 3 == 0 ? 'F&B' : 'I&L',
          zone: 'West',
          ifscCode: 'SBIN0016484',
          accountNumber: '43593955${3530 + i}',
          bankDetails: 'State Bank Of India',
          basicCharges: 14756,
          otherCharges: 9000.0 + i * 311,
          gender: i % 5 == 0 ? 'F' : 'M',
        ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    wireSharedDocumentHooks();
    final n = SalaryDataNotifier.instance;
    n.setMonthYear(3, 2026);
    for (var i = 1; i <= 60; i++) {
      n.setDays(i, i % 7 == 0 ? 0 : 31);
    }
  });

  test('Tax invoice + expenses statement: portrait invoice, landscape table',
      () async {
    final bytes = await WidgetPdfExportService.buildInvoiceBundleBytes(
      voucher: _voucher(45),
      config: _config,
      taxMargins: _margins,
      voucherMargins: _margins,
    );
    _save('01_tax_invoice_and_expenses_statement', bytes);
    final pages = _orientations(bytes);
    expect(pages.first, _portrait);
    expect(pages.skip(1), everyElement(_landscape));
    expect(pages.length, greaterThan(2), reason: '45 rows should paginate');
  });

  test('Bank disbursement: landscape table pages', () async {
    final bytes = await WidgetPdfExportService.buildBankDisbursementBytes(
      voucher: _voucher(45),
      config: _config,
      margins: _margins,
    );
    _save('02_bank_disbursement', bytes);
    expect(_orientations(bytes), everyElement(_landscape));
  });

  const header = SalaryBillHeader(
    billNo: 'AE/129/25-26',
    date: '31/03/2026',
    poNo: '700034713',
    customerName: 'M/s Diversey India Hygiene Private Ltd.',
    customerAddress: '501,5th flr,Ackruti center point, MIDC Central Road,'
        'Andheri (East), Mumbai-400093',
    customerGst: '27AABCC1597Q1Z2',
    departmentCode: 'I&L',
    period: 'March 2026',
  );

  test('Finalised salary bill: three portrait invoices, landscape statement',
      () async {
    final employees = _employees(40);
    final bytes = await SalaryBillPdfService.buildBytes(
      config: _config,
      margins: _margins,
      departmentCode: 'I&L',
      pages: [
        SalaryBillPdfService.salaryInvoiceSpec(
          header: header,
          itemDescription: 'Manpower Supply Charges',
          invoiceBaseAmount: 672047,
        ),
        SalaryBillPdfService.attachmentASpec(
          header: header,
          itemDescription: 'Salary for the month of March 2026-2027',
          itemAmount: 591151,
          pfAmount: 42174,
          esicAmount: 1909,
        ),
        SalaryBillPdfService.attachmentBSpec(
          header: header,
          itemDescription: 'Service charges for the month of March 2026-2027',
          employeeCount: 21,
        ),
      ],
      statement: SalaryStatementInput(
        employees: employees,
        monthName: 'March',
        year: 2026,
        isMsw: false,
        mswAmount: 6,
        isFeb: false,
        daysMap: {for (final e in employees) e.id!: 31},
        daysInMonth: 31,
      ),
    );
    _save('03_final_salary_invoice', bytes);
    final pages = _orientations(bytes);
    expect(pages.take(3), everyElement(_portrait));
    expect(pages.skip(3), everyElement(_landscape));
    expect(pages.length, greaterThan(4), reason: '40 rows should paginate');
  });

  test('Salary statement: landscape table pages', () async {
    final employees = _employees(40);
    final bytes = await SalaryStatementPdfService.buildSalaryStatementBytes(
      config: _config,
      employees: employees,
      monthName: 'March',
      year: 2026,
      isMsw: false,
      mswAmount: 6,
      isFeb: false,
      daysMap: {for (final e in employees) e.id!: e.id! % 7 == 0 ? 0 : 31},
      daysInMonth: 31,
      departmentCode: 'F&B',
      margins: _margins,
    );
    _save('04_salary_statement', bytes);
    expect(_orientations(bytes), everyElement(_landscape));
  });

  test('Salary slips: portrait, two per page', () async {
    final bytes = await SalaryPdfExportService.buildSalarySlipsBytes(
      config: _config,
      employees: _employees(5),
      monthName: 'March',
      year: 2026,
      daysInMonth: 31,
      isMsw: false,
      isFeb: false,
      margins: _margins,
    );
    _save('05_salary_slips', bytes);
    final pages = _orientations(bytes);
    expect(pages, everyElement(_portrait));
    expect(pages.length, 3);
  });

  test('Amount in words', () {
    expect(PdfHouseStyle.amountInWords(793015),
        'Rupees Seven Lakh Ninety Three Thousand Fifteen Only');
    expect(PdfHouseStyle.amountInWords(410651.5),
        'Rupees Four Lakh Ten Thousand Six Hundred Fifty One and Fifty Paise Only');
    expect(PdfHouseStyle.amountInWords(0), 'Rupees Zero Only');
  });
}
