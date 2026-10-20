/// Combines monthly dashboard rows by profile ID without estimating salary.
List<Map<String, dynamic>> aggregateYearlyAttendance(List<Map<String, dynamic>> months) {
  const fields = ['present', 'absent', 'late', 'halfLeave', 'earnedLeave', 'approvedLeave', 'excused', 'unexcused'];
  final rows = <String, Map<String, dynamic>>{};
  for (final month in months) {
    for (final raw in (month['employees'] as List? ?? []).whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final id = item['id'];
      if (id == null) throw const FormatException('Employee ID is missing from attendance data');
      final row = rows.putIfAbsent(id.toString(), () => {
        'id': id, 'name': item['name'], 'designation': item['designation'],
        for (final field in fields) field: 0,
        'salary': '—', 'absentDeduction': '—', 'daysPaid': '—',
        'afterLeaves': '—', 'updatedSalary': '—', 'days': <String>[],
      });
      for (final field in fields) {
        final value = item[field];
        row[field] = (row[field] as num) + (value is num ? value : num.tryParse('$value') ?? 0);
      }
    }
  }
  return rows.values.toList();
}
