export interface Employee {
  id: string;
  srNo: number;
  name: string;
  pfNo: string;
  uanNo: string;
  code: string;
  ifscCode: string;
  accountNumber: string;
  aartiAcNo: string;
  sbCode: string;
  bankDetails: string;
  branch: string;
  zone: string;
  dateOfJoining: string;
}

export interface VoucherRow {
  id: string;
  employeeId: string;
  employeeName: string;
  amount: number;
  fromDate: string;
  toDate: string;
  ifscCode: string;
  accountNumber: string;
  sbCode: string;
  bankDetails: string;
  branch: string;
  deptCode: string;
  debitAccountNumber: string;
  debitAccountName: string;
  voucherTitle: string; // Used for "Bank Detail" field in disbursement
}

export interface Voucher {
  id: string;
  title: string;
  description: string;
  deptCode: string;
  date: string;
  rows: VoucherRow[];
  baseTotal: number;
  cgst: number;
  sgst: number;
  totalTax: number;
  roundOff: number;
  finalTotal: number;
  status: 'draft' | 'saved';
  billNo: string;
  poNo: string;
  itemDescription: string;
  clientName: string;
  clientAddress: string;
  clientGstin: string;
}

export interface CompanyConfig {
  companyName: string;
  address: string;
  gstin: string;
  pan: string;
  jurisdiction: string;
  bankName: string;
  branch: string;
  accountNo: string;
  ifscCode: string;
  declarationText: string;
  phone: string;
}
