/// Pure-Dart CruSam business logic shared by the Flutter app and the MCP
/// server. Nothing in here may import Flutter.
library;

export 'src/app_defaults.dart';
export 'src/clients/client_store.dart';
export 'src/email/email_outbox_store.dart';
export 'src/employees/employee_store.dart';
export 'src/export/export_hooks.dart';
export 'src/invoice/invoice_totals.dart';
export 'src/invoice/voucher_factory.dart';
export 'src/invoice/voucher_store.dart';
export 'src/models/bank_column_widths_model.dart';
export 'src/models/company_config_model.dart';
export 'src/models/employee_model.dart';
export 'src/models/margin_settings_model.dart';
export 'src/models/salary_disbursement_model.dart';
export 'src/models/salary_formula_config_model.dart';
export 'src/models/salary_snapshot_model.dart';
export 'src/models/voucher_model.dart';
export 'src/models/voucher_column_widths_model.dart';
export 'src/models/voucher_row_model.dart';
export 'src/pdf/pdf_col_widths.dart';
export 'src/pdf/pdf_house_style.dart';
export 'src/pdf/salary_bill_pdf_service.dart';
export 'src/pdf/salary_pdf_export_service.dart';
export 'src/pdf/salary_statement_pdf_service.dart';
export 'src/pdf/widget_pdf_export_service.dart';
export 'src/salary/salary_formula_engine.dart';
export 'src/salary/salary_math.dart';
export 'src/salary/salary_month.dart';
export 'src/salary/salary_snapshot_store.dart';
export 'src/text/fuzzy_name.dart';
export 'src/util/format_utils.dart';
