/// Master list of departments and their codes from the
/// FY 25/26 Signature Authorization sheet.
///
/// Key = department name (must match what Notion returns),
/// Value = 4-digit department code.
const kDepartmentCodes = <String, String>{
  'Corporate': '9900',
  'ECEC (DEC Grant)': '9902',
  'ECEC (CSPP)': '9903',
  'ECEC (Int/Todd)': '9905',
  'ECEC (P/S)': '9906',
  'ECEC (CCAMPIS)': '9909',
  'ECEC (CCTR)': '9911',
  'Project Rebound': '9915',
  'RCG': '9916',
  'Administration': '9921',
  'Accounting': '9922',
  'Human Resources': '9923',
  'Facilities': '9930',
  'Information Technology': '9934',
  'Building Operations': '9935',
  'Art Gallery': '9940',
  'Games Room': '9941',
  'ROMC': '9945',
  'Board of Directors': '9950',
  'Elections': '9951',
  'Governance': '9953',
  'EROS': '9955',
  "Women's Center": '9960',
  'Legal Resource Center': '9965',
  'Project Connect': '9966',
  'Production': '9967',
  'Marketing': '9968',
  'Environmental Res. Ctr': '9971',
  'QTRC': '9972',
  'ED Contingency': '9973',
  'ECEC Facilities': '9974',
  'Admin Program': '9976',
  'Gator Groceries': '9977',
  'Event Services': '9978',
  'Student Orgs': '9980',
  'Murals': '9981',
};

/// A single department entry with name and code.
class Department {
  final String name;
  final String code;

  const Department({required this.name, required this.code});

  /// Display string: "Name (Code)"
  String get display => '$name ($code)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Department && other.name == name && other.code == code;

  @override
  int get hashCode => Object.hash(name, code);

  @override
  String toString() => display;
}

/// Returns only departments that exist in both the master list and Notion.
/// [notionDepartments] is the list of department name strings from the API.
List<Department> resolvedDepartments(List<String> notionDepartments) {
  final notionSet = notionDepartments.toSet();
  return kDepartmentCodes.entries
      .where((e) => notionSet.contains(e.key))
      .map((e) => Department(name: e.key, code: e.value))
      .toList();
}
