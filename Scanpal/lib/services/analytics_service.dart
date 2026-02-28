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
  const TripExpenseEntry({required this.trip, required this.totalExpenses});
}

/// Category total for pie chart.
class CategoryTotal {
  final String name;
  final double amount;
  final double percentage;
  const CategoryTotal({required this.name, required this.amount, required this.percentage});
}

class AnalyticsService {
  final List<Receipt> receipts;
  final List<Trip> trips;

  AnalyticsService({required this.receipts, required this.trips});

  /// Check if a trip overlaps with a date range [rangeStart, rangeEnd).
  /// A trip spans from departureDate to returnDate (inclusive).
  /// If only departureDate exists, it's treated as a single-day trip.
  bool _tripOverlaps(Trip t, DateTime rangeStart, DateTime rangeEnd) {
    if (t.departureDate == null) return false;
    final tripStart = DateTime(t.departureDate!.year, t.departureDate!.month, t.departureDate!.day);
    final tripEnd = t.returnDate != null
        ? DateTime(t.returnDate!.year, t.returnDate!.month, t.returnDate!.day)
        : tripStart;
    // Trip overlaps range if tripStart < rangeEnd AND tripEnd >= rangeStart
    return tripStart.isBefore(rangeEnd) && !tripEnd.isBefore(rangeStart);
  }

  /// Calculate how much of a trip's expenses fall within [rangeStart, rangeEnd).
  /// Distributes expenses evenly across trip days, returns the portion in range.
  double _tripExpenseInRange(Trip t, DateTime rangeStart, DateTime rangeEnd) {
    if (t.departureDate == null) return 0;
    final tripStart = DateTime(t.departureDate!.year, t.departureDate!.month, t.departureDate!.day);
    final tripEnd = t.returnDate != null
        ? DateTime(t.returnDate!.year, t.returnDate!.month, t.returnDate!.day)
        : tripStart;

    final totalDays = tripEnd.difference(tripStart).inDays + 1;
    final dailyRate = t.totalExpenses / totalDays;

    // Find overlap between [tripStart, tripEnd] and [rangeStart, rangeEnd)
    final overlapStart = tripStart.isBefore(rangeStart) ? rangeStart : tripStart;
    final rangeEndInclusive = rangeEnd.subtract(const Duration(days: 1));
    final overlapEnd = tripEnd.isAfter(rangeEndInclusive) ? rangeEndInclusive : tripEnd;

    final overlapDays = overlapEnd.difference(overlapStart).inDays + 1;
    if (overlapDays <= 0) return 0;

    return dailyRate * overlapDays;
  }

  /// Spending bucketed into 5-day intervals for a specific month.
  /// e.g. Feb 2026 → 1-5, 6-10, 11-15, 16-20, 21-25, 26-28
  /// Each bucket stays strictly within the month.
  List<SpendingDataPoint> spendingByDayBucket(int year, int month) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final result = <SpendingDataPoint>[];

    // Resolve effective dates for all receipts once
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

      final label = '$bucketStart-$bucketEnd';
      result.add(SpendingDataPoint(label: label, amount: bucketTotal));

      bucketStart = bucketEnd + 1;
    }
    return result;
  }

  /// Weekly spending for the current month (Week 1–4/5).
  List<SpendingDataPoint> spendingByWeek() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final result = <SpendingDataPoint>[];

    for (int w = 0; w < 5; w++) {
      final weekStart = monthStart.add(Duration(days: w * 7));
      final weekEnd = monthStart.add(Duration(days: (w + 1) * 7));
      if (weekStart.month != now.month) break;

      double weekTotal = 0;
      for (final t in trips) {
        if (_tripOverlaps(t, weekStart, weekEnd)) {
          weekTotal += _tripExpenseInRange(t, weekStart, weekEnd);
        }
      }

      result.add(SpendingDataPoint(
        label: 'W${w + 1}',
        amount: weekTotal,
      ));
    }
    return result;
  }

  /// Monthly spending for the current year (Jan–Dec).
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

      result.add(SpendingDataPoint(
        label: monthNames[m - 1],
        amount: monthTotal,
      ));
    }
    return result;
  }

  /// Yearly spending across all years that have trip data.
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

      result.add(SpendingDataPoint(
        label: '$y',
        amount: yearTotal,
      ));
    }
    return result;
  }

  /// Category totals from trip-level data (the 5 travel expense categories).
  List<CategoryTotal> categoryTotalsFromTrips() {
    final categories = {
      'Accommodation': trips.fold(0.0, (s, t) => s + t.accommodationCost),
      'Flight': trips.fold(0.0, (s, t) => s + t.flightCost),
      'Ground Transport': trips.fold(0.0, (s, t) => s + t.groundTransportation),
      'Registration': trips.fold(0.0, (s, t) => s + t.registrationCost),
      'Other': trips.fold(0.0, (s, t) => s + t.otherAsCost),
    };

    final total = categories.values.fold(0.0, (s, v) => s + v);
    if (total == 0) return [];

    return categories.entries
        .where((e) => e.value > 0)
        .map((e) => CategoryTotal(
              name: e.key,
              amount: e.value,
              percentage: (e.value / total) * 100,
            ))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
  }

  /// Trip comparison sorted by total expenses (descending).
  List<TripExpenseEntry> tripComparison() {
    final entries = trips
        .map((t) => TripExpenseEntry(trip: t, totalExpenses: t.totalExpenses))
        .toList()
      ..sort((a, b) => b.totalExpenses.compareTo(a.totalExpenses));
    return entries;
  }

  /// Total spent across all receipts.
  double get totalSpent => receipts.fold(0.0, (s, r) => s + r.effectiveTotal);

  /// Receipt count.
  int get receiptCount => receipts.length;

  /// Total from trips.
  double get totalFromTrips => trips.fold(0.0, (s, t) => s + t.totalExpenses);
}
