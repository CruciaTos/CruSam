// lib/data/models/salary_formula_config_model.dart
//
// Holds every salary-formula constant that used to be hardcoded across the
// salary module (PF, ESIC, Professional Tax slabs, employer contributions
// for Attachment A, and the Attachment B per-employee amount). Defaults
// below match the values that were previously inlined in code, so existing
// behaviour is unchanged until someone edits them from the new
// Salary Formula settings screen.
class SalaryFormulaConfigModel {
  final int? id;

  // ── PF (Provident Fund) — employee deduction ──────────────────────────
  final double pfRate;            // 12% of earned basic
  final double pfBasicThreshold;  // earned basic >= this → flat cap applies
  final double pfCapAmount;       // flat PF once basic crosses the threshold

  // ── ESIC (Employee State Insurance) — employee deduction ───────────────
  final double esicRate;           // 0.75% of earned gross
  final double esicGrossThreshold; // employee ineligible above this (full gross)

  // ── Professional Tax slabs ──────────────────────────────────────────────
  final double ptFemaleThreshold;    // female: 0 below this earned gross
  final double ptMaleTier1Threshold; // male: 0 below this earned gross
  final double ptMaleTier2Threshold; // male: tier2 amount between tier1 & tier2
  final double ptMaleTier2Amount;    // male mid-tier flat PT
  final double ptStandardAmount;     // non-February PT (female ≥ threshold / male ≥ tier2)
  final double ptFebAmount;          // February PT for the same groups

  // ── Employer contributions (Attachment A) ───────────────────────────────
  final double employerPfRate;   // 13% of total earned basic
  final double employerEsicRate; // 3.25% of ESIC-eligible earned gross

  // ── Attachment B ─────────────────────────────────────────────────────────
  final double attachmentBPerEmployee; // fixed amount per active employee

  const SalaryFormulaConfigModel({
    this.id,
    this.pfRate                = 0.12,
    this.pfBasicThreshold      = 15000,
    this.pfCapAmount           = 1800,
    this.esicRate              = 0.0075,
    this.esicGrossThreshold    = 21000,
    this.ptFemaleThreshold     = 25000,
    this.ptMaleTier1Threshold  = 7500,
    this.ptMaleTier2Threshold  = 10000,
    this.ptMaleTier2Amount     = 175,
    this.ptStandardAmount      = 200,
    this.ptFebAmount           = 300,
    this.employerPfRate        = 0.13,
    this.employerEsicRate      = 0.0325,
    this.attachmentBPerEmployee = 1753,
  });

  SalaryFormulaConfigModel copyWith({
    double? pfRate, double? pfBasicThreshold, double? pfCapAmount,
    double? esicRate, double? esicGrossThreshold,
    double? ptFemaleThreshold, double? ptMaleTier1Threshold,
    double? ptMaleTier2Threshold, double? ptMaleTier2Amount,
    double? ptStandardAmount, double? ptFebAmount,
    double? employerPfRate, double? employerEsicRate,
    double? attachmentBPerEmployee,
  }) => SalaryFormulaConfigModel(
    id: id,
    pfRate:                pfRate                ?? this.pfRate,
    pfBasicThreshold:      pfBasicThreshold      ?? this.pfBasicThreshold,
    pfCapAmount:           pfCapAmount           ?? this.pfCapAmount,
    esicRate:              esicRate              ?? this.esicRate,
    esicGrossThreshold:    esicGrossThreshold    ?? this.esicGrossThreshold,
    ptFemaleThreshold:     ptFemaleThreshold     ?? this.ptFemaleThreshold,
    ptMaleTier1Threshold:  ptMaleTier1Threshold  ?? this.ptMaleTier1Threshold,
    ptMaleTier2Threshold:  ptMaleTier2Threshold  ?? this.ptMaleTier2Threshold,
    ptMaleTier2Amount:     ptMaleTier2Amount     ?? this.ptMaleTier2Amount,
    ptStandardAmount:      ptStandardAmount      ?? this.ptStandardAmount,
    ptFebAmount:           ptFebAmount           ?? this.ptFebAmount,
    employerPfRate:        employerPfRate        ?? this.employerPfRate,
    employerEsicRate:      employerEsicRate      ?? this.employerEsicRate,
    attachmentBPerEmployee: attachmentBPerEmployee ?? this.attachmentBPerEmployee,
  );

  factory SalaryFormulaConfigModel.fromMap(Map<String, dynamic> m) {
    const d = SalaryFormulaConfigModel();
    double num_(String key, double fallback) =>
        (m[key] as num?)?.toDouble() ?? fallback;
    return SalaryFormulaConfigModel(
      id:                     m['id'] as int?,
      pfRate:                 num_('pf_rate', d.pfRate),
      pfBasicThreshold:       num_('pf_basic_threshold', d.pfBasicThreshold),
      pfCapAmount:            num_('pf_cap_amount', d.pfCapAmount),
      esicRate:               num_('esic_rate', d.esicRate),
      esicGrossThreshold:     num_('esic_gross_threshold', d.esicGrossThreshold),
      ptFemaleThreshold:      num_('pt_female_threshold', d.ptFemaleThreshold),
      ptMaleTier1Threshold:   num_('pt_male_tier1_threshold', d.ptMaleTier1Threshold),
      ptMaleTier2Threshold:   num_('pt_male_tier2_threshold', d.ptMaleTier2Threshold),
      ptMaleTier2Amount:      num_('pt_male_tier2_amount', d.ptMaleTier2Amount),
      ptStandardAmount:       num_('pt_standard_amount', d.ptStandardAmount),
      ptFebAmount:            num_('pt_feb_amount', d.ptFebAmount),
      employerPfRate:         num_('employer_pf_rate', d.employerPfRate),
      employerEsicRate:       num_('employer_esic_rate', d.employerEsicRate),
      attachmentBPerEmployee: num_('attachment_b_per_employee', d.attachmentBPerEmployee),
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'pf_rate':                    pfRate,
    'pf_basic_threshold':         pfBasicThreshold,
    'pf_cap_amount':              pfCapAmount,
    'esic_rate':                  esicRate,
    'esic_gross_threshold':       esicGrossThreshold,
    'pt_female_threshold':        ptFemaleThreshold,
    'pt_male_tier1_threshold':    ptMaleTier1Threshold,
    'pt_male_tier2_threshold':    ptMaleTier2Threshold,
    'pt_male_tier2_amount':       ptMaleTier2Amount,
    'pt_standard_amount':         ptStandardAmount,
    'pt_feb_amount':              ptFebAmount,
    'employer_pf_rate':           employerPfRate,
    'employer_esic_rate':         employerEsicRate,
    'attachment_b_per_employee':  attachmentBPerEmployee,
  };
}
