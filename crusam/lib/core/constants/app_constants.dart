import 'package:crusam_core/crusam_core.dart';

// Values live in crusam_core (AppDefaults / InvoiceRates) so the MCP server
// uses the same ones.
class AppConstants {
  static const deptCodes = AppDefaults.deptCodes;

  static const itemDescriptions = AppDefaults.itemDescriptions;

  static const defaultAartiAcNo = '0680651100000338';
  static const defaultSbCode    = '10';
  static const cgstRate         = InvoiceRates.cgst;
  static const sgstRate         = InvoiceRates.sgst;

  static const defaultClientName    = AppDefaults.defaultClientName;
  static const defaultClientAddress = AppDefaults.defaultClientAddress;
  static const defaultClientGstin   = AppDefaults.defaultClientGstin;
}
