/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect } from 'react';
import { 
  LayoutDashboard, 
  Users, 
  FileText, 
  Receipt, 
  Settings, 
  Plus, 
  Search,
  LogOut,
  ChevronRight,
  Download,
  Trash2,
  Save,
  FileDown
} from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { Employee, Voucher, CompanyConfig, VoucherRow } from './types';
import { DEFAULT_COMPANY_CONFIG, DEPT_CODES, ITEM_DESCRIPTIONS } from './constants';
import { formatCurrency, numberToWords } from './lib/utils';
import { MOCK_EMPLOYEES } from './mockData';

type Tab = 'dashboard' | 'employees' | 'vouchers' | 'invoices' | 'settings';

export default function App() {
  const [activeTab, setActiveTab] = useState<Tab>('dashboard');
  const [employees, setEmployees] = useState<Employee[]>(MOCK_EMPLOYEES);
  const [vouchers, setVouchers] = useState<Voucher[]>([]);
  const [config, setConfig] = useState<CompanyConfig>(DEFAULT_COMPANY_CONFIG);
  const [isSidebarOpen, setIsSidebarOpen] = useState(true);

  // --- Navigation ---
  const navItems = [
    { id: 'dashboard', label: 'Dashboard', icon: LayoutDashboard },
    { id: 'employees', label: 'Employee Master', icon: Users },
    { id: 'vouchers', label: 'Voucher Builder', icon: FileText },
    { id: 'invoices', label: 'Invoices', icon: Receipt },
    { id: 'settings', label: 'Company Config', icon: Settings },
  ];

  return (
    <div className="flex h-screen bg-slate-50 overflow-hidden">
      {/* Sidebar */}
      <motion.aside 
        initial={false}
        animate={{ width: isSidebarOpen ? 260 : 80 }}
        className="bg-slate-900 text-slate-300 flex flex-col border-r border-slate-800"
      >
        <div className="p-6 flex items-center gap-3">
          <div className="w-8 h-8 bg-indigo-500 rounded-lg flex items-center justify-center text-white font-bold shrink-0">
            A
          </div>
          {isSidebarOpen && (
            <motion.span 
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              className="font-bold text-white tracking-tight truncate"
            >
              AARTI ENTERPRISES
            </motion.span>
          )}
        </div>

        <nav className="flex-1 px-3 space-y-1">
          {navItems.map((item) => (
            <button
              key={item.id}
              onClick={() => setActiveTab(item.id as Tab)}
              className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg transition-colors ${
                activeTab === item.id 
                  ? 'bg-indigo-600 text-white' 
                  : 'hover:bg-slate-800 hover:text-white'
              }`}
            >
              <item.icon size={20} />
              {isSidebarOpen && <span>{item.label}</span>}
            </button>
          ))}
        </nav>

        <div className="p-4 border-t border-slate-800">
          <button className="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg hover:bg-slate-800 transition-colors text-slate-400 hover:text-white">
            <LogOut size={20} />
            {isSidebarOpen && <span>Logout</span>}
          </button>
        </div>
      </motion.aside>

      {/* Main Content */}
      <main className="flex-1 flex flex-col overflow-hidden">
        {/* Header */}
        <header className="h-16 bg-white border-b border-slate-200 flex items-center justify-between px-8 shrink-0">
          <div className="flex items-center gap-4">
            <button 
              onClick={() => setIsSidebarOpen(!isSidebarOpen)}
              className="p-2 hover:bg-slate-100 rounded-md text-slate-500"
            >
              <ChevronRight className={`transition-transform ${isSidebarOpen ? 'rotate-180' : ''}`} />
            </button>
            <h1 className="text-lg font-semibold text-slate-800 capitalize">
              {activeTab.replace('-', ' ')}
            </h1>
          </div>
          <div className="flex items-center gap-4">
            <div className="text-right">
              <p className="text-sm font-medium text-slate-900">Admin User</p>
              <p className="text-xs text-slate-500">boridkar24@gmail.com</p>
            </div>
            <div className="w-10 h-10 bg-slate-200 rounded-full flex items-center justify-center text-slate-600 font-medium">
              AU
            </div>
          </div>
        </header>

        {/* Content Area */}
        <div className="flex-1 overflow-y-auto p-8">
          <AnimatePresence mode="wait">
            <motion.div
              key={activeTab}
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              transition={{ duration: 0.2 }}
            >
              {activeTab === 'dashboard' && <DashboardView employees={employees} vouchers={vouchers} />}
              {activeTab === 'employees' && <EmployeeMasterView employees={employees} setEmployees={setEmployees} />}
              {activeTab === 'vouchers' && <VoucherBuilderView employees={employees} vouchers={vouchers} setVouchers={setVouchers} config={config} />}
              {activeTab === 'invoices' && <InvoicesView vouchers={vouchers} />}
              {activeTab === 'settings' && <SettingsView config={config} setConfig={setConfig} />}
            </motion.div>
          </AnimatePresence>
        </div>
      </main>
    </div>
  );
}

// --- PDF Components (Styled to match screenshots) ---

function TaxInvoicePDF({ voucher, config }: { voucher: Voucher, config: CompanyConfig }) {
  return (
    <div className="w-[210mm] min-h-[297mm] bg-white p-[15mm] shadow-lg text-[11px] font-sans text-black leading-tight">
      {/* Header */}
      <div className="flex justify-between items-start border-b-2 border-black pb-4 mb-4">
        <div className="flex gap-4 items-center">
          <div className="w-16 h-16 bg-slate-100 rounded-full flex items-center justify-center border border-slate-300 italic font-serif text-indigo-800 text-center leading-none">
            Aarti<br/>Enterprises
          </div>
          <div>
            <h1 className="text-xl font-bold text-emerald-800 tracking-tight">AARTI ENTERPRISES</h1>
            <p className="max-w-[300px] text-[10px]">{config.address}</p>
            <p className="font-bold">Tel. Office : {config.phone}</p>
          </div>
        </div>
        <div className="text-right">
          <h2 className="text-lg font-bold border-b border-black mb-2">TAX INVOICE</h2>
        </div>
      </div>

      {/* Bill Info */}
      <div className="grid grid-cols-2 gap-8 mb-6">
        <div className="space-y-1">
          <p className="font-bold">BILL To,</p>
          <p className="font-bold">{voucher.clientName}</p>
          <p className="max-w-[300px]">{voucher.clientAddress}</p>
          <p className="font-bold mt-2">( I & L ) GST No. {voucher.clientGstin}</p>
          <p className="italic mt-1">Traveling expenses for the month of MARCH-2026</p>
        </div>
        <div className="space-y-1 text-right">
          <p><span className="font-bold">Bill No : -</span> {voucher.billNo || 'AE/123/25-26'}</p>
          <p><span className="font-bold">Date : -</span> {voucher.date}</p>
          <p><span className="font-bold">PO. No. :</span> {voucher.poNo || '700034713'}</p>
        </div>
      </div>

      {/* Table */}
      <table className="w-full border-collapse border-2 border-black mb-4">
        <thead>
          <tr className="border-b-2 border-black">
            <th className="border-r-2 border-black p-2 w-12">Sr. No</th>
            <th className="border-r-2 border-black p-2 w-24">Date Fr.</th>
            <th className="border-r-2 border-black p-2 w-24">Date upto</th>
            <th className="border-r-2 border-black p-2">Item Description</th>
            <th className="border-r-2 border-black p-2 w-16">QTY</th>
            <th className="border-r-2 border-black p-2 w-20">RATE</th>
            <th className="p-2 w-24">AMOUNT</th>
          </tr>
        </thead>
        <tbody>
          <tr className="h-[300px] align-top">
            <td className="border-r-2 border-black p-2 text-center">1</td>
            <td className="border-r-2 border-black p-2"></td>
            <td className="border-r-2 border-black p-2"></td>
            <td className="border-r-2 border-black p-2">
              <p className="mb-4">{voucher.itemDescription}</p>
              <p className="italic text-center mt-20">( Vouchers attatched with this original bill )</p>
            </td>
            <td className="border-r-2 border-black p-2"></td>
            <td className="border-r-2 border-black p-2"></td>
            <td className="p-2 text-right font-bold">{voucher.baseTotal?.toFixed(2)}</td>
          </tr>
        </tbody>
      </table>

      {/* Footer Info */}
      <div className="grid grid-cols-2 gap-4 mb-4">
        <div className="space-y-1">
          <p className="font-bold">PAN NO :- {config.pan}</p>
          <p className="font-bold">GSTIN : {config.gstin} <span className="ml-4">HSN: SAC99851</span></p>
          <div className="mt-4 space-y-0.5">
            <p>Bank Details for : RTGS / NEFT</p>
            <p>Bank Name : {config.bankName}</p>
            <p>Branch : {config.branch}</p>
            <p>Account No. : {config.accountNo}</p>
            <p>IFSC Code : {config.ifscCode}</p>
          </div>
        </div>
        <div className="border-l-2 border-black pl-4">
          <div className="space-y-2">
            <div className="flex justify-between font-bold">
              <span>Total amount before Tax</span>
              <span>{voucher.baseTotal?.toFixed(2)}</span>
            </div>
            <div className="flex justify-between">
              <span>Add : CGST 9%</span>
              <span>{voucher.cgst?.toFixed(2)}</span>
            </div>
            <div className="flex justify-between">
              <span>Add : SGST 9%</span>
              <span>{voucher.sgst?.toFixed(2)}</span>
            </div>
            <div className="flex justify-between font-bold border-t border-black pt-1">
              <span>Total Tax Amount</span>
              <span>{voucher.totalTax?.toFixed(2)}</span>
            </div>
            <div className="flex justify-between">
              <span>Round Up</span>
              <span>{voucher.roundOff?.toFixed(2)}</span>
            </div>
            <div className="flex justify-between font-bold text-lg border-t-2 border-black pt-1">
              <span>Total Amount after Tax</span>
              <span>{voucher.finalTotal?.toFixed(2)}</span>
            </div>
          </div>
        </div>
      </div>

      <div className="mt-8 flex justify-between items-end">
        <div className="space-y-1">
          <p>{config.declarationText}</p>
          <p>Subject to {config.jurisdiction} jurisdiction.</p>
        </div>
        <div className="text-center">
          <p className="font-bold mb-12">For AARTI ENTERPRISES</p>
          <p className="border-t border-black pt-1 px-8">Partner</p>
        </div>
      </div>
    </div>
  );
}

function VoucherPDF({ voucher, config }: { voucher: Voucher, config: CompanyConfig }) {
  return (
    <div className="w-[210mm] min-h-[297mm] bg-white p-[10mm] shadow-lg text-[9px] font-sans text-black leading-tight">
      <div className="flex justify-between items-center mb-4 border-b border-black pb-2">
        <p className="font-bold uppercase">AARTI ENTERPRISES : Expenses Statement for the month of MARCH-2026</p>
        <p className="font-bold">{voucher.deptCode}</p>
      </div>

      <table className="w-full border-collapse border border-black mb-4">
        <thead>
          <tr className="bg-slate-50">
            <th className="border border-black p-1">Sr.</th>
            <th className="border border-black p-1">Debit Account</th>
            <th className="border border-black p-1">IFSC Code</th>
            <th className="border border-black p-1">Credit Account</th>
            <th className="border border-black p-1">Code</th>
            <th className="border border-black p-1">Name of Beneficiary</th>
            <th className="border border-black p-1">Place</th>
            <th className="border border-black p-1">Bank Detail</th>
            <th className="border border-black p-1">Date Fr.</th>
            <th className="border border-black p-1">Date To</th>
            <th className="border border-black p-1 text-right">Amount</th>
          </tr>
        </thead>
        <tbody>
          {voucher.rows?.map((row, i) => (
            <tr key={row.id}>
              <td className="border border-black p-1 text-center">{i + 1}</td>
              <td className="border border-black p-1 font-mono">{config.accountNo}</td>
              <td className="border border-black p-1 font-mono">{row.ifscCode}</td>
              <td className="border border-black p-1 font-mono">{row.accountNumber}</td>
              <td className="border border-black p-1 text-center">{row.sbCode}</td>
              <td className="border border-black p-1">{row.employeeName}</td>
              <td className="border border-black p-1">{row.branch}</td>
              <td className="border border-black p-1">{voucher.title}</td>
              <td className="border border-black p-1">{row.fromDate}</td>
              <td className="border border-black p-1">{row.toDate}</td>
              <td className="border border-black p-1 text-right font-bold">{row.amount.toFixed(2)}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <div className="flex justify-between items-start">
        <div>
          <p className="font-bold text-sm">{formatCurrency(voucher.baseTotal || 0)}</p>
          <p className="font-bold italic">{numberToWords(voucher.baseTotal || 0)}</p>
        </div>
        <div className="text-center">
          <p className="font-bold mb-8">For AARTI ENTERPRISES</p>
          <p className="border-t border-black pt-1 px-4">Partner</p>
        </div>
      </div>
    </div>
  );
}

function BankDisbursementPDF({ voucher, config }: { voucher: Voucher, config: CompanyConfig }) {
  const idbiToOther = voucher.rows?.filter(r => !r.ifscCode.startsWith('IDIB')).reduce((acc, r) => acc + Number(r.amount || 0), 0) || 0;
  const idbiToIdbi = voucher.rows?.filter(r => r.ifscCode.startsWith('IDIB')).reduce((acc, r) => acc + Number(r.amount || 0), 0) || 0;

  return (
    <div className="w-[210mm] min-h-[297mm] bg-white p-[15mm] shadow-lg text-[10px] font-sans text-black leading-tight">
      <div className="text-center mb-6">
        <h2 className="text-sm font-bold uppercase underline">AARTI ENTERPRISES : TRAVEL EXPENSES FOR MARCH-2026</h2>
      </div>

      <table className="w-full border-collapse border border-black mb-6">
        <thead>
          <tr className="bg-slate-100">
            <th className="border border-black p-2 text-left">Amount</th>
            <th className="border border-black p-2 text-left">Debit Account Number</th>
            <th className="border border-black p-2 text-left">IFSC Code</th>
            <th className="border border-black p-2 text-left">Credit Account Number</th>
            <th className="border border-black p-2 text-left">Code</th>
            <th className="border border-black p-2 text-left">Name of beneficiary</th>
            <th className="border border-black p-2 text-left">Place</th>
            <th className="border border-black p-2 text-left">Bank Detail</th>
            <th className="border border-black p-2 text-left">Debit Account Name</th>
          </tr>
        </thead>
        <tbody>
          {voucher.rows?.map((row) => (
            <tr key={row.id}>
              <td className="border border-black p-2 font-bold">{row.amount}</td>
              <td className="border border-black p-2 font-mono">{config.accountNo}</td>
              <td className="border border-black p-2 font-mono">{row.ifscCode}</td>
              <td className="border border-black p-2 font-mono">{row.accountNumber}</td>
              <td className="border border-black p-2 text-center">{row.sbCode}</td>
              <td className="border border-black p-2">{row.employeeName}</td>
              <td className="border border-black p-2">{row.branch}</td>
              <td className="border border-black p-2">Union Bank Of India</td>
              <td className="border border-black p-2">{config.companyName}</td>
            </tr>
          ))}
          <tr className="font-bold bg-slate-50">
            <td className="border border-black p-2">{voucher.baseTotal}</td>
            <td colSpan={8} className="border border-black p-2 italic">{numberToWords(voucher.baseTotal || 0)}</td>
          </tr>
        </tbody>
      </table>

      <div className="w-64 border border-black">
        <div className="flex justify-between p-2 border-b border-black">
          <span>1</span>
          <span className="w-32">From IDBI to Other Bank</span>
          <span className="font-bold">{idbiToOther}</span>
        </div>
        <div className="flex justify-between p-2 border-b border-black">
          <span>2</span>
          <span className="w-32">From IDBI to IDBI Bank</span>
          <span className="font-bold">{idbiToIdbi.toString().padStart(5, '0')}</span>
        </div>
        <div className="flex justify-between p-2 font-bold bg-slate-100">
          <span>Total</span>
          <span className="w-32"></span>
          <span>{voucher.baseTotal}</span>
        </div>
      </div>
    </div>
  );
}

function DashboardView({ employees, vouchers }: { employees: Employee[], vouchers: Voucher[] }) {
  const stats = [
    { label: 'Total Employees', value: employees.length, icon: Users, color: 'text-blue-600', bg: 'bg-blue-50' },
    { label: 'Active Vouchers', value: vouchers.length, icon: FileText, color: 'text-indigo-600', bg: 'bg-indigo-50' },
    { label: 'Total Invoiced', value: formatCurrency(vouchers.reduce((acc, v) => acc + v.finalTotal, 0)), icon: Receipt, color: 'text-emerald-600', bg: 'bg-emerald-50' },
  ];

  return (
    <div className="space-y-8">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {stats.map((stat, i) => (
          <div key={i} className="card p-6 flex items-center gap-4">
            <div className={`p-4 rounded-xl ${stat.bg} ${stat.color}`}>
              <stat.icon size={24} />
            </div>
            <div>
              <p className="text-sm text-slate-500 font-medium">{stat.label}</p>
              <p className="text-2xl font-bold text-slate-900">{stat.value}</p>
            </div>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        <div className="card p-6">
          <h3 className="text-lg font-semibold mb-4">Recent Vouchers</h3>
          {vouchers.length === 0 ? (
            <div className="text-center py-12 text-slate-400">
              <FileText size={48} className="mx-auto mb-3 opacity-20" />
              <p>No vouchers created yet</p>
            </div>
          ) : (
            <div className="space-y-4">
              {vouchers.slice(0, 5).map(v => (
                <div key={v.id} className="flex items-center justify-between p-3 hover:bg-slate-50 rounded-lg border border-transparent hover:border-slate-100 transition-all">
                  <div>
                    <p className="font-medium text-slate-900">{v.title}</p>
                    <p className="text-xs text-slate-500">{v.date} • {v.deptCode}</p>
                  </div>
                  <div className="text-right">
                    <p className="font-semibold text-slate-900">{formatCurrency(v.finalTotal)}</p>
                    <span className={`text-[10px] uppercase font-bold px-2 py-0.5 rounded-full ${v.status === 'saved' ? 'bg-emerald-100 text-emerald-700' : 'bg-amber-100 text-amber-700'}`}>
                      {v.status}
                    </span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="card p-6">
          <h3 className="text-lg font-semibold mb-4">Quick Actions</h3>
          <div className="grid grid-cols-2 gap-4">
            <button className="flex flex-col items-center justify-center p-6 rounded-xl border border-slate-200 hover:border-indigo-500 hover:bg-indigo-50 transition-all group">
              <Plus className="text-slate-400 group-hover:text-indigo-600 mb-2" size={24} />
              <span className="text-sm font-medium text-slate-600 group-hover:text-indigo-700">New Voucher</span>
            </button>
            <button className="flex flex-col items-center justify-center p-6 rounded-xl border border-slate-200 hover:border-indigo-500 hover:bg-indigo-50 transition-all group">
              <Users className="text-slate-400 group-hover:text-indigo-600 mb-2" size={24} />
              <span className="text-sm font-medium text-slate-600 group-hover:text-indigo-700">Add Employee</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function EmployeeMasterView({ employees, setEmployees }: { employees: Employee[], setEmployees: React.Dispatch<React.SetStateAction<Employee[]>> }) {
  const [searchTerm, setSearchTerm] = useState('');
  const [isAdding, setIsAdding] = useState(false);

  const filteredEmployees = employees.filter(e => 
    e.name.toLowerCase().includes(searchTerm.toLowerCase()) || 
    e.pfNo.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="relative w-96">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" size={18} />
          <input 
            type="text" 
            placeholder="Search employees by name or PF No..." 
            className="input pl-10"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
        </div>
        <button 
          onClick={() => setIsAdding(true)}
          className="btn btn-primary gap-2"
        >
          <Plus size={18} /> Add New Employee
        </button>
      </div>

      <div className="card overflow-hidden">
        <table className="w-full text-left border-collapse">
          <thead>
            <tr className="bg-slate-50 border-b border-slate-200">
              <th className="px-6 py-4 text-xs font-semibold text-slate-500 uppercase tracking-wider">Sr. No</th>
              <th className="px-6 py-4 text-xs font-semibold text-slate-500 uppercase tracking-wider">Name</th>
              <th className="px-6 py-4 text-xs font-semibold text-slate-500 uppercase tracking-wider">PF No / UAN</th>
              <th className="px-6 py-4 text-xs font-semibold text-slate-500 uppercase tracking-wider">Bank Details</th>
              <th className="px-6 py-4 text-xs font-semibold text-slate-500 uppercase tracking-wider">Account No</th>
              <th className="px-6 py-4 text-xs font-semibold text-slate-500 uppercase tracking-wider">Branch / Zone</th>
              <th className="px-6 py-4 text-xs font-semibold text-slate-500 uppercase tracking-wider text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-200">
            {filteredEmployees.map((e) => (
              <tr key={e.id} className="hover:bg-slate-50 transition-colors">
                <td className="px-6 py-4 text-sm text-slate-600">{e.srNo}</td>
                <td className="px-6 py-4">
                  <p className="text-sm font-semibold text-slate-900">{e.name}</p>
                  <p className="text-xs text-slate-500">{e.code}</p>
                </td>
                <td className="px-6 py-4">
                  <p className="text-sm text-slate-600">{e.pfNo}</p>
                  <p className="text-xs text-slate-400">{e.uanNo}</p>
                </td>
                <td className="px-6 py-4">
                  <p className="text-sm text-slate-900">{e.bankDetails}</p>
                  <p className="text-xs text-slate-500 font-mono">{e.ifscCode}</p>
                </td>
                <td className="px-6 py-4 text-sm font-mono text-slate-600">{e.accountNumber}</td>
                <td className="px-6 py-4">
                  <p className="text-sm text-slate-900">{e.branch}</p>
                  <p className="text-xs text-slate-500">{e.zone}</p>
                </td>
                <td className="px-6 py-4 text-right">
                  <button className="btn btn-ghost p-2">
                    <Trash2 size={16} className="text-slate-400 hover:text-red-500" />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function VoucherBuilderView({ employees, vouchers, setVouchers, config }: { employees: Employee[], vouchers: Voucher[], setVouchers: React.Dispatch<React.SetStateAction<Voucher[]>>, config: CompanyConfig }) {
  const [currentVoucher, setCurrentVoucher] = useState<Partial<Voucher>>({
    title: '',
    deptCode: DEPT_CODES[0],
    date: new Date().toISOString().split('T')[0],
    rows: [],
    billNo: '',
    poNo: '',
    itemDescription: ITEM_DESCRIPTIONS[0],
    clientName: 'M/s Diversey India Hygiene Private Ltd.',
    clientAddress: '501,5th flr,Ackruti center point, MIDC Central Road,Andheri (East), Mumbai-400093',
    clientGstin: '27AABCC1597Q1Z2'
  });

  const [showPreview, setShowPreview] = useState<'invoice' | 'bank' | null>(null);

  const addRow = () => {
    const newRow: VoucherRow = {
      id: Math.random().toString(36).substr(2, 9),
      employeeId: '',
      employeeName: '',
      amount: 0,
      fromDate: '',
      toDate: '',
      ifscCode: '',
      accountNumber: '',
      sbCode: '10',
      bankDetails: '',
      branch: '',
      deptCode: currentVoucher.deptCode || '',
      debitAccountNumber: config.accountNo,
      debitAccountName: config.companyName,
      voucherTitle: currentVoucher.title || ''
    };
    setCurrentVoucher({ ...currentVoucher, rows: [...(currentVoucher.rows || []), newRow] });
  };

  const updateRow = (id: string, field: keyof VoucherRow, value: any) => {
    const updatedRows = (currentVoucher.rows || []).map(row => {
      if (row.id === id) {
        let updated = { ...row, [field]: value };
        
        // Auto-fill from master if employee selected
        if (field === 'employeeId') {
          const emp = employees.find(e => e.id === value);
          if (emp) {
            updated = {
              ...updated,
              employeeName: emp.name,
              ifscCode: emp.ifscCode,
              accountNumber: emp.accountNumber,
              bankDetails: emp.bankDetails,
              branch: emp.branch,
              sbCode: emp.sbCode
            };
          }
        }
        return updated;
      }
      return row;
    });
    setCurrentVoucher({ ...currentVoucher, rows: updatedRows });
  };

  const removeRow = (id: string) => {
    setCurrentVoucher({ ...currentVoucher, rows: (currentVoucher.rows || []).filter(r => r.id !== id) });
  };

  // Calculations
  const baseTotal = (currentVoucher.rows || []).reduce((acc, row) => acc + Number(row.amount || 0), 0);
  const cgst = baseTotal * 0.09;
  const sgst = baseTotal * 0.09;
  const totalTax = cgst + sgst;
  const rawTotal = baseTotal + totalTax;
  const finalTotal = Math.round(rawTotal);
  const roundOff = finalTotal - rawTotal;

  const idbiToOther = (currentVoucher.rows || []).filter(r => !r.ifscCode.startsWith('IDIB')).reduce((acc, r) => acc + Number(r.amount || 0), 0);
  const idbiToIdbi = (currentVoucher.rows || []).filter(r => r.ifscCode.startsWith('IDIB')).reduce((acc, r) => acc + Number(r.amount || 0), 0);

  // Enriched voucher for preview and saving
  const enrichedVoucher: Voucher = {
    ...(currentVoucher as Voucher),
    baseTotal,
    cgst,
    sgst,
    totalTax,
    roundOff,
    finalTotal,
    status: 'saved'
  };

  const handleSaveInvoice = () => {
    if (!currentVoucher.title) {
      alert('Please enter a voucher title');
      return;
    }
    const newVoucher = { ...enrichedVoucher, id: Math.random().toString(36).substr(2, 9), status: 'saved' as const };
    setVouchers([...vouchers, newVoucher]);
    alert('Invoice saved successfully in the app!');
  };

  return (
    <div className="space-y-8">
      <div className="card p-6 space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="space-y-2">
            <label className="text-sm font-medium text-slate-700">Voucher Title / Description</label>
            <input 
              type="text" 
              placeholder="e.g. Exp. MAR-2026 aarti" 
              className="input"
              value={currentVoucher.title}
              onChange={e => setCurrentVoucher({ ...currentVoucher, title: e.target.value })}
            />
          </div>
          <div className="space-y-2">
            <label className="text-sm font-medium text-slate-700">Department Code</label>
            <select 
              className="input"
              value={currentVoucher.deptCode}
              onChange={e => setCurrentVoucher({ ...currentVoucher, deptCode: e.target.value })}
            >
              {DEPT_CODES.map(code => <option key={code} value={code}>{code}</option>)}
            </select>
          </div>
          <div className="space-y-2">
            <label className="text-sm font-medium text-slate-700">Date</label>
            <input 
              type="date" 
              className="input"
              value={currentVoucher.date}
              onChange={e => setCurrentVoucher({ ...currentVoucher, date: e.target.value })}
            />
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div className="space-y-2">
            <label className="text-sm font-medium text-slate-700">Client Name</label>
            <input 
              type="text" 
              className="input"
              value={currentVoucher.clientName}
              onChange={e => setCurrentVoucher({ ...currentVoucher, clientName: e.target.value })}
            />
          </div>
          <div className="space-y-2">
            <label className="text-sm font-medium text-slate-700">Client GSTIN</label>
            <input 
              type="text" 
              className="input"
              value={currentVoucher.clientGstin}
              onChange={e => setCurrentVoucher({ ...currentVoucher, clientGstin: e.target.value })}
            />
          </div>
        </div>

        <div className="space-y-2">
          <label className="text-sm font-medium text-slate-700">Item Description (for Invoice)</label>
          <select 
            className="input"
            value={currentVoucher.itemDescription}
            onChange={e => setCurrentVoucher({ ...currentVoucher, itemDescription: e.target.value })}
          >
            {ITEM_DESCRIPTIONS.map(desc => <option key={desc} value={desc}>{desc}</option>)}
          </select>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse min-w-[1000px]">
            <thead>
              <tr className="bg-slate-50 border-y border-slate-200">
                <th className="px-4 py-3 text-xs font-semibold text-slate-500 uppercase w-12">#</th>
                <th className="px-4 py-3 text-xs font-semibold text-slate-500 uppercase w-64">Employee Name</th>
                <th className="px-4 py-3 text-xs font-semibold text-slate-500 uppercase w-32">Amount</th>
                <th className="px-4 py-3 text-xs font-semibold text-slate-500 uppercase w-40">From Date</th>
                <th className="px-4 py-3 text-xs font-semibold text-slate-500 uppercase w-40">To Date</th>
                <th className="px-4 py-3 text-xs font-semibold text-slate-500 uppercase">Auto-filled Details</th>
                <th className="px-4 py-3 text-xs font-semibold text-slate-500 uppercase w-12"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200">
              {(currentVoucher.rows || []).map((row, index) => (
                <tr key={row.id} className="hover:bg-slate-50/50">
                  <td className="px-4 py-3 text-sm text-slate-400">{index + 1}</td>
                  <td className="px-4 py-3">
                    <select 
                      className="input text-sm"
                      value={row.employeeId}
                      onChange={e => updateRow(row.id, 'employeeId', e.target.value)}
                    >
                      <option value="">Select Employee</option>
                      {employees.map(e => (
                        <option key={e.id} value={e.id}>{e.name} ({e.pfNo})</option>
                      ))}
                    </select>
                  </td>
                  <td className="px-4 py-3">
                    <input 
                      type="number" 
                      className="input text-sm text-right"
                      value={row.amount || ''}
                      onChange={e => updateRow(row.id, 'amount', Number(e.target.value))}
                    />
                  </td>
                  <td className="px-4 py-3">
                    <input 
                      type="date" 
                      className="input text-xs"
                      value={row.fromDate}
                      onChange={e => updateRow(row.id, 'fromDate', e.target.value)}
                    />
                  </td>
                  <td className="px-4 py-3">
                    <input 
                      type="date" 
                      className="input text-xs"
                      value={row.toDate}
                      onChange={e => updateRow(row.id, 'toDate', e.target.value)}
                    />
                  </td>
                  <td className="px-4 py-3">
                    <div className="text-[10px] text-slate-500 grid grid-cols-2 gap-x-4">
                      <span>IFSC: <span className="font-mono">{row.ifscCode || '-'}</span></span>
                      <span>A/c: <span className="font-mono">{row.accountNumber || '-'}</span></span>
                      <span>Bank: {row.bankDetails || '-'}</span>
                      <span>Place: {row.branch || '-'}</span>
                    </div>
                  </td>
                  <td className="px-4 py-3 text-right">
                    <button onClick={() => removeRow(row.id)} className="text-slate-300 hover:text-red-500 transition-colors">
                      <Trash2 size={16} />
                    </button>
                  </td>
                </tr>
              ))}
              <tr>
                <td colSpan={7} className="px-4 py-4">
                  <button 
                    onClick={addRow}
                    className="flex items-center gap-2 text-sm font-medium text-indigo-600 hover:text-indigo-700 transition-colors"
                  >
                    <Plus size={16} /> Add Row
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        <div className="card p-6 space-y-4">
          <h3 className="text-sm font-bold text-slate-400 uppercase tracking-wider">Bank Transfer Split</h3>
          <div className="space-y-3">
            <div className="flex justify-between text-sm">
              <span className="text-slate-600">From IDBI to Other Bank</span>
              <span className="font-semibold text-slate-900">{formatCurrency(idbiToOther)}</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-slate-600">From IDBI to IDBI Bank</span>
              <span className="font-semibold text-slate-900">{formatCurrency(idbiToIdbi)}</span>
            </div>
            <div className="pt-3 border-t border-slate-100 flex justify-between font-bold text-slate-900">
              <span>Total Base Amount</span>
              <span>{formatCurrency(baseTotal)}</span>
            </div>
          </div>
        </div>

        <div className="card p-6 bg-slate-900 text-white space-y-4">
          <h3 className="text-sm font-bold text-slate-500 uppercase tracking-wider">Final Calculations</h3>
          <div className="space-y-3">
            <div className="flex justify-between text-sm opacity-80">
              <span>Base Total</span>
              <span>{formatCurrency(baseTotal)}</span>
            </div>
            <div className="flex justify-between text-sm opacity-80">
              <span>CGST (9%)</span>
              <span>{formatCurrency(cgst)}</span>
            </div>
            <div className="flex justify-between text-sm opacity-80">
              <span>SGST (9%)</span>
              <span>{formatCurrency(sgst)}</span>
            </div>
            <div className="flex justify-between text-sm opacity-80">
              <span>Round Off</span>
              <span className={roundOff >= 0 ? 'text-emerald-400' : 'text-rose-400'}>
                {roundOff >= 0 ? '+' : ''}{roundOff.toFixed(2)}
              </span>
            </div>
            <div className="pt-4 border-t border-slate-700 flex flex-col gap-1">
              <div className="flex justify-between items-baseline">
                <span className="text-lg font-bold">Grand Total</span>
                <span className="text-3xl font-bold text-indigo-400">{formatCurrency(finalTotal)}</span>
              </div>
              <p className="text-[10px] text-slate-400 italic text-right">
                {numberToWords(finalTotal)}
              </p>
            </div>
          </div>
        </div>
      </div>

      <div className="flex justify-end gap-4">
        <button className="btn btn-secondary gap-2">
          <Save size={18} /> Save as Draft
        </button>
        <button 
          onClick={handleSaveInvoice}
          className="btn btn-secondary gap-2 text-emerald-600 border-emerald-200 hover:bg-emerald-50"
        >
          <Save size={18} /> Save Invoice
        </button>
        <button 
          onClick={() => setShowPreview('invoice')}
          className="btn btn-secondary gap-2"
        >
          <FileText size={18} /> Preview Invoice
        </button>
        <button 
          onClick={() => setShowPreview('bank')}
          className="btn btn-secondary gap-2"
        >
          <Download size={18} /> Preview Bank Sheet
        </button>
        <button className="btn btn-primary gap-2">
          <FileDown size={18} /> Finalise & Export
        </button>
      </div>

      {showPreview && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-8">
          <div className="bg-white rounded-xl shadow-2xl w-full max-w-5xl h-full flex flex-col overflow-hidden">
            <div className="p-4 border-b flex justify-between items-center bg-slate-50">
              <h3 className="font-bold text-slate-800">PDF Preview - {showPreview === 'invoice' ? 'Tax Invoice & Voucher' : 'Bank Disbursement Sheet'}</h3>
              <div className="flex gap-2">
                <button className="btn btn-primary btn-sm gap-2">
                  <Download size={16} /> Download PDF
                </button>
                <button onClick={() => setShowPreview(null)} className="btn btn-secondary btn-sm">Close</button>
              </div>
            </div>
            <div className="flex-1 overflow-y-auto p-12 bg-slate-200 flex justify-center">
              {showPreview === 'invoice' ? (
                <div className="space-y-8">
                  <TaxInvoicePDF voucher={enrichedVoucher} config={config} />
                  <VoucherPDF voucher={enrichedVoucher} config={config} />
                </div>
              ) : (
                <BankDisbursementPDF voucher={enrichedVoucher} config={config} />
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function InvoicesView({ vouchers }: { vouchers: Voucher[] }) {
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-bold text-slate-900">Generated Invoices</h2>
        <div className="flex gap-2">
          <button className="btn btn-secondary btn-sm gap-2">
            <Download size={16} /> Export List
          </button>
        </div>
      </div>

      <div className="card overflow-hidden">
        <table className="w-full text-left border-collapse">
          <thead>
            <tr className="bg-slate-50 border-b border-slate-200">
              <th className="px-6 py-4 text-xs font-semibold text-slate-500 uppercase tracking-wider">Bill No</th>
              <th className="px-6 py-4 text-xs font-semibold text-slate-500 uppercase tracking-wider">Date</th>
              <th className="px-6 py-4 text-xs font-semibold text-slate-500 uppercase tracking-wider">Voucher Ref</th>
              <th className="px-6 py-4 text-xs font-semibold text-slate-500 uppercase tracking-wider">Amount</th>
              <th className="px-6 py-4 text-xs font-semibold text-slate-500 uppercase tracking-wider text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-200">
            {vouchers.length === 0 ? (
              <tr>
                <td colSpan={5} className="px-6 py-12 text-center text-slate-400">
                  No invoices generated yet. Finalise a voucher to create an invoice.
                </td>
              </tr>
            ) : (
              vouchers.filter(v => v.status === 'saved').map((v) => (
                <tr key={v.id} className="hover:bg-slate-50 transition-colors">
                  <td className="px-6 py-4 text-sm font-bold text-indigo-600">AE-{v.id.slice(0, 4).toUpperCase()}</td>
                  <td className="px-6 py-4 text-sm text-slate-600">{v.date}</td>
                  <td className="px-6 py-4 text-sm text-slate-900">{v.title}</td>
                  <td className="px-6 py-4 text-sm font-semibold text-slate-900">{formatCurrency(v.finalTotal)}</td>
                  <td className="px-6 py-4 text-right space-x-2">
                    <button className="btn btn-ghost p-2 text-slate-400 hover:text-indigo-600">
                      <Download size={16} />
                    </button>
                    <button className="btn btn-ghost p-2 text-slate-400 hover:text-indigo-600">
                      <FileText size={16} />
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function SettingsView({ config, setConfig }: { config: CompanyConfig, setConfig: React.Dispatch<React.SetStateAction<CompanyConfig>> }) {
  return (
    <div className="max-w-4xl mx-auto space-y-8">
      <div className="card p-8 space-y-8">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
          <div className="space-y-6">
            <h3 className="text-lg font-semibold text-slate-900 border-b pb-2">Company Details</h3>
            <div className="space-y-4">
              <div className="space-y-2">
                <label className="text-sm font-medium text-slate-700">Company Name</label>
                <input 
                  type="text" 
                  className="input"
                  value={config.companyName}
                  onChange={e => setConfig({ ...config, companyName: e.target.value })}
                />
              </div>
              <div className="space-y-2">
                <label className="text-sm font-medium text-slate-700">Address</label>
                <textarea 
                  className="input h-24 resize-none"
                  value={config.address}
                  onChange={e => setConfig({ ...config, address: e.target.value })}
                />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <label className="text-sm font-medium text-slate-700">GSTIN</label>
                  <input 
                    type="text" 
                    className="input font-mono"
                    value={config.gstin}
                    onChange={e => setConfig({ ...config, gstin: e.target.value })}
                  />
                </div>
                <div className="space-y-2">
                  <label className="text-sm font-medium text-slate-700">PAN</label>
                  <input 
                    type="text" 
                    className="input font-mono"
                    value={config.pan}
                    onChange={e => setConfig({ ...config, pan: e.target.value })}
                  />
                </div>
              </div>
            </div>
          </div>

          <div className="space-y-6">
            <h3 className="text-lg font-semibold text-slate-900 border-b pb-2">Bank Configuration</h3>
            <div className="space-y-4">
              <div className="space-y-2">
                <label className="text-sm font-medium text-slate-700">Bank Name</label>
                <input 
                  type="text" 
                  className="input"
                  value={config.bankName}
                  onChange={e => setConfig({ ...config, bankName: e.target.value })}
                />
              </div>
              <div className="space-y-2">
                <label className="text-sm font-medium text-slate-700">Branch</label>
                <input 
                  type="text" 
                  className="input"
                  value={config.branch}
                  onChange={e => setConfig({ ...config, branch: e.target.value })}
                />
              </div>
              <div className="space-y-2">
                <label className="text-sm font-medium text-slate-700">Account Number</label>
                <input 
                  type="text" 
                  className="input font-mono"
                  value={config.accountNo}
                  onChange={e => setConfig({ ...config, accountNo: e.target.value })}
                />
              </div>
              <div className="space-y-2">
                <label className="text-sm font-medium text-slate-700">IFSC Code</label>
                <input 
                  type="text" 
                  className="input font-mono"
                  value={config.ifscCode}
                  onChange={e => setConfig({ ...config, ifscCode: e.target.value })}
                />
              </div>
            </div>
          </div>
        </div>

        <div className="space-y-2">
          <label className="text-sm font-medium text-slate-700">Declaration Text</label>
          <textarea 
            className="input h-20 resize-none"
            value={config.declarationText}
            onChange={e => setConfig({ ...config, declarationText: e.target.value })}
          />
        </div>

        <div className="flex justify-end pt-4">
          <button className="btn btn-primary gap-2 px-8">
            <Save size={18} /> Save Configuration
          </button>
        </div>
      </div>
    </div>
  );
}
