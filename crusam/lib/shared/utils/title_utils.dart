/// Returns "$baseTitle - $departmentCode" or just "$baseTitle" when code
/// is null, empty, or the catch-all "All" sentinel.
String getTitle(String baseTitle, String? departmentCode) {
  if (departmentCode == null ||
      departmentCode.isEmpty ||
      departmentCode == 'All') {
    return baseTitle;
  }
  return '$baseTitle - $departmentCode';
}