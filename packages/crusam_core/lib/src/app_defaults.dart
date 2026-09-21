// Business defaults shared by the app (AppConstants re-exposes these) and the
// MCP server.

class AppDefaults {
  AppDefaults._();

  static const deptCodes = ['I&L', 'F&B', 'A&P', 'P&S'];

  static const itemDescriptions = [
    'Local and outstation travelling expenses with daily allowance including mobile expenses and material.',
    'Service Charges for the month of',
    'Manpower Supply Charges',
    'Maintenance Services',
    'Consultancy Fees',
  ];

  static const defaultClientName = 'M/s Diversey India Hygiene Private Ltd.';
  static const defaultClientAddress =
      '501,5th flr,Ackruti center point, MIDC Central Road,Andheri (East), Mumbai-400093';
  static const defaultClientGstin = '27AABCC1597Q1Z2';

  // Salary module defaults (SalaryDataNotifier's initial values).
  static const salaryPoNo = '-';
  static const salaryBillNo = 'AE/-/25-26';
  static const salaryItemDescription = 'Manpower Supply Charges';
  static const mswAmount = 6.0;
}
