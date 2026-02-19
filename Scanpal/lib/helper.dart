// lib/helper.dart
import 'package:intl/intl.dart';

String fmtDate(DateTime d) {
  try {
    final f = DateFormat.yMMMd().add_jm(); // e.g. "Sep 12, 2025 6:45 PM"
    return f.format(d);
  } catch (_) {
    return d.toIso8601String(); // fallback
  }
}

String moneyNum(num? v) {
  if (v == null) return '';
  return '\$${v.toStringAsFixed(2)}';
}
