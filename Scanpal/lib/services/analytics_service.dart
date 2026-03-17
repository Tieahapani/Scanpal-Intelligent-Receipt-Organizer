import '../receipt.dart';
import '../models/trip.dart';

/// Data point for bar charts.
class SpendingDataPoint {
  final String label;
  final double amount;
  const SpendingDataPoint({required this.label, required this.amount});
}

/// Trip comparison entry.
class TripExpenseEntry {
  final Trip trip;
  final double totalExpenses;
  final double personalTotal;
  final double amexTotal;
  const TripExpenseEntry({
    required this.trip,
    required this.totalExpenses,
    this.personalTotal = 0,
    this.amexTotal = 0,
  });
}

/// Category total for pie chart.
class CategoryTotal {
  final String name;
  final double amount;
  final double percentage;
  const CategoryTotal({required this.name, required this.amount, required this.percentage});
}

/// Snapshot of analytics for a specific time period.
class PeriodSnapshot {
  final double total;
  final int change; // percentage change vs prior period
  final String changeLabel;
  final int receipts;
  final List<CategoryTotal> categories;
  final List<TripExpenseEntry> trips;
  final double personalTotal;
  final double amexTotal;

  const PeriodSnapshot({
    required this.total,
    required this.change,
    required this.changeLabel,
    required this.receipts,
    required this.categories,
    required this.trips,
    required this.personalTotal,
    required this.amexTotal,
  });

  static const empty = PeriodSnapshot(
    total: 0, change: 0, changeLabel: '', receipts: 0,
    categories: [], trips: [], personalTotal: 0, amexTotal: 0,
  );
}

class AnalyticsService {
  final List<Receipt> receipts;
  final List<Trip> trips;

  AnalyticsService({required this.receipts, required this.trips});

  // ─── Period Snapshot ─────────────────────────────────

  /// Build a snapshot for a given date range, comparing against a prior range.
  PeriodSnapshot snapshot(DateTime start, DateTime end, DateTime priorStart, DateTime priorEnd, String periodWord) {
    final current = _receiptsByDateRange(start, end);
    final prior = _receiptsByDateRange(priorStart, priorEnd);

    final total = current.fold(0.0, (s, r) => s + r.effectiveTotal);
    final priorTotal = prior.fold(0.0, (s, r) => s + r.effectiveTotal);
    final changeVal = priorTotal > 0
        ? ((total - priorTotal) / priorTotal * 100).round()
        : (total > 0 ? 100 : 0);
    final diff = (total - priorTotal).abs();
    final diffFormatted = '\$${diff.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+\.)'), (m) => '${m[1]},')}';
    final changeLabel = total >= priorTotal
        ? '$diffFormatted more than previous $periodWord'
        : '$diffFormatted less than previous $periodWord';

    final personalTotal = current
        .where((r) => r.paymentMethod != 'corporate')
        .fold(0.0, (s, r) => s + r.effectiveTotal);
    final amexTotal = current
        .where((r) => r.paymentMethod == 'corporate')
        .fold(0.0, (s, r) => s + r.effectiveTotal);

    final categories = _categoryTotalsFromReceipts(current);
    final tripEntries = _tripEntriesFromReceipts(current);

    return PeriodSnapshot(
      total: total,
      change: changeVal,
      changeLabel: changeLabel,
      receipts: current.length,
      categories: categories,
      trips: tripEntries,
      personalTotal: personalTotal,
      amexTotal: amexTotal,
    );
  }

  /// Monthly snapshot for a given month (0-indexed) and year.
  PeriodSnapshot monthlySnapshot(int month, int year) {
    final start = DateTime(year, month + 1, 1);
    final end = DateTime(year, month + 2, 1);
    final priorStart = DateTime(year, month, 1);
    final priorEnd = start;
    return snapshot(start, end, priorStart, priorEnd, 'month');
  }

  /// Yearly snapshot for a given year.
  PeriodSnapshot yearlySnapshot(int year) {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);
    final priorStart = DateTime(year - 1, 1, 1);
    final priorEnd = start;
    return snapshot(start, end, priorStart, priorEnd, 'year');
  }

  /// Weekly snapshot for a given week start date (Sunday).
  PeriodSnapshot weeklySnapshot(DateTime weekStart) {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(const Duration(days: 7));
    final priorStart = start.subtract(const Duration(days: 7));
    final priorEnd = start;
    return snapshot(start, end, priorStart, priorEnd, 'week');
  }

  // ─── Helpers ──────────────────────────────────────────

  List<Receipt> _receiptsByDateRange(DateTime start, DateTime end) {
    return receipts.where((r) {
      final d = r.date;
      if (d == null) return false;
      final day = DateTime(d.year, d.month, d.day);
      return !day.isBefore(start) && day.isBefore(end);
    }).toList();
  }

  List<CategoryTotal> _categoryTotalsFromReceipts(List<Receipt> recs) {
    final map = <String, double>{
      'Accommodation Cost': 0,
      'Flight Cost': 0,
      'Ground Transportation': 0,
      'Registration Cost': 0,
      'Meals': 0,
      'Other AS Cost': 0,
    };

    for (final r in recs) {
      final cat = r.travelCategory ?? r.category ?? 'Other AS Cost';
      map[cat] = (map[cat] ?? 0) + r.effectiveTotal;
    }

    final total = map.values.fold(0.0, (s, v) => s + v);
    if (total == 0) return [];

    return map.entries
        .where((e) => e.value > 0)
        .map((e) => CategoryTotal(
              name: e.key,
              amount: e.value,
              percentage: (e.value / total) * 100,
            ))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
  }

  List<TripExpenseEntry> _tripEntriesFromReceipts(List<Receipt> recs) {
    final tripMap = <String, List<Receipt>>{};
    for (final r in recs) {
      final key = r.tripId ?? '_unassigned';
      tripMap.putIfAbsent(key, () => []).add(r);
    }

    final entries = <TripExpenseEntry>[];
    for (final e in tripMap.entries) {
      final trip = trips.cast<Trip?>().firstWhere((t) => t?.id == e.key, orElse: () => null);
      final total = e.value.fold(0.0, (s, r) => s + r.effectiveTotal);
      final personal = e.value.where((r) => r.paymentMethod != 'corporate').fold(0.0, (s, r) => s + r.effectiveTotal);
      final amex = e.value.where((r) => r.paymentMethod == 'corporate').fold(0.0, (s, r) => s + r.effectiveTotal);
      entries.add(TripExpenseEntry(
        trip: trip ?? Trip(id: e.key, travelerEmail: '', travelerName: '', tripPurpose: 'Other'),
        totalExpenses: total,
        personalTotal: personal,
        amexTotal: amex,
      ));
    }
    entries.sort((a, b) => b.totalExpenses.compareTo(a.totalExpenses));
    return entries;
  }

  // ─── Legacy methods (kept for compatibility) ──────────

  bool _tripOverlaps(Trip t, DateTime rangeStart, DateTime rangeEnd) {
    if (t.departureDate == null) return false;
    final tripStart = DateTime(t.departureDate!.year, t.departureDate!.month, t.departureDate!.day);
    final tripEnd = t.returnDate != null
        ? DateTime(t.returnDate!.year, t.returnDate!.month, t.returnDate!.day)
        : tripStart;
    return tripStart.isBefore(rangeEnd) && !tripEnd.isBefore(rangeStart);
  }

  double _tripExpenseInRange(Trip t, DateTime rangeStart, DateTime rangeEnd) {
    if (t.departureDate == null) return 0;
    final tripStart = DateTime(t.departureDate!.year, t.departureDate!.month, t.departureDate!.day);
    final tripEnd = t.returnDate != null
        ? DateTime(t.returnDate!.year, t.returnDate!.month, t.returnDate!.day)
        : tripStart;
    final totalDays = tripEnd.difference(tripStart).inDays + 1;
    final dailyRate = t.totalExpenses / totalDays;
    final overlapStart = tripStart.isBefore(rangeStart) ? rangeStart : tripStart;
    final rangeEndInclusive = rangeEnd.subtract(const Duration(days: 1));
    final overlapEnd = tripEnd.isAfter(rangeEndInclusive) ? rangeEndInclusive : tripEnd;
    final overlapDays = overlapEnd.difference(overlapStart).inDays + 1;
    if (overlapDays <= 0) return 0;
    return dailyRate * overlapDays;
  }

  List<SpendingDataPoint> spendingByDayBucket(int year, int month) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final result = <SpendingDataPoint>[];
    final datedReceipts = <MapEntry<DateTime, double>>[];
    for (final r in receipts) {
      DateTime? effectiveDate = r.date;
      if (effectiveDate == null && r.tripId != null) {
        for (final t in trips) {
          if (t.id == r.tripId && t.departureDate != null) {
            effectiveDate = t.departureDate;
            break;
          }
        }
      }
      if (effectiveDate == null) continue;
      datedReceipts.add(MapEntry(
        DateTime(effectiveDate.year, effectiveDate.month, effectiveDate.day),
        r.effectiveTotal,
      ));
    }
    int bucketStart = 1;
    while (bucketStart <= lastDay) {
      int bucketEnd = bucketStart + 4;
      if (bucketEnd > lastDay) bucketEnd = lastDay;
      final rangeStart = DateTime(year, month, bucketStart);
      final rangeEnd = DateTime(year, month, bucketEnd);
      double bucketTotal = 0;
      for (final entry in datedReceipts) {
        if (!entry.key.isBefore(rangeStart) && !entry.key.isAfter(rangeEnd)) {
          bucketTotal += entry.value;
        }
      }
      result.add(SpendingDataPoint(label: '$bucketStart-$bucketEnd', amount: bucketTotal));
      bucketStart = bucketEnd + 1;
    }
    return result;
  }

  List<SpendingDataPoint> spendingByMonth() {
    final now = DateTime.now();
    final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final result = <SpendingDataPoint>[];
    for (int m = 1; m <= 12; m++) {
      final monthStart = DateTime(now.year, m, 1);
      final monthEnd = (m < 12) ? DateTime(now.year, m + 1, 1) : DateTime(now.year + 1, 1, 1);
      double monthTotal = 0;
      for (final t in trips) {
        if (_tripOverlaps(t, monthStart, monthEnd)) {
          monthTotal += _tripExpenseInRange(t, monthStart, monthEnd);
        }
      }
      result.add(SpendingDataPoint(label: monthNames[m - 1], amount: monthTotal));
    }
    return result;
  }

  List<SpendingDataPoint> spendingByYear() {
    final years = <int>{};
    for (final t in trips) {
      if (t.departureDate != null) years.add(t.departureDate!.year);
      if (t.returnDate != null) years.add(t.returnDate!.year);
    }
    if (years.isEmpty) return [];
    final sortedYears = years.toList()..sort();
    final result = <SpendingDataPoint>[];
    for (final y in sortedYears) {
      final yearStart = DateTime(y, 1, 1);
      final yearEnd = DateTime(y + 1, 1, 1);
      double yearTotal = 0;
      for (final t in trips) {
        if (_tripOverlaps(t, yearStart, yearEnd)) {
          yearTotal += _tripExpenseInRange(t, yearStart, yearEnd);
        }
      }
      result.add(SpendingDataPoint(label: '$y', amount: yearTotal));
    }
    return result;
  }

  List<CategoryTotal> categoryTotalsFromTrips() {
    final categories = {
      'Accommodation Cost': trips.fold(0.0, (s, t) => s + t.accommodationCost),
      'Flight Cost': trips.fold(0.0, (s, t) => s + t.flightCost),
      'Ground Transportation': trips.fold(0.0, (s, t) => s + t.groundTransportation),
      'Registration Cost': trips.fold(0.0, (s, t) => s + t.registrationCost),
      'Meals': trips.fold(0.0, (s, t) => s + t.meals),
      'Other AS Cost': trips.fold(0.0, (s, t) => s + t.otherAsCost),
    };
    final total = categories.values.fold(0.0, (s, v) => s + v);
    if (total == 0) return [];
    return categories.entries
        .where((e) => e.value > 0)
        .map((e) => CategoryTotal(name: e.key, amount: e.value, percentage: (e.value / total) * 100))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
  }

  List<TripExpenseEntry> tripComparison() {
    return trips
        .map((t) => TripExpenseEntry(trip: t, totalExpenses: t.totalExpenses))
        .toList()
      ..sort((a, b) => b.totalExpenses.compareTo(a.totalExpenses));
  }

  double get totalSpent => receipts.fold(0.0, (s, r) => s + r.effectiveTotal);
  int get receiptCount => receipts.length;
  double get totalFromTrips => trips.fold(0.0, (s, t) => s + t.totalExpenses);
}
