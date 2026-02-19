import 'dart:async';
import 'package:isar/isar.dart';
import '../entities.dart';

/// Supported timeline buckets for the spending chart.
enum SummaryGranularity { monthly, weekly, yearly }

/// Simple time bucket + value pair for the chart.
class SummarySeriesPoint {
  const SummarySeriesPoint({required this.period, required this.total});

  final DateTime period;
  final double total;
}

/// Aggregated stats for the currently selected month.
class QuickStats {
  const QuickStats({
    required this.receiptsCount,
    required this.averageSpend,
    required this.currentTotal,
    required this.lastMonthTotal,
    required this.dailyAverage,
  });

  final int receiptsCount;
  final double averageSpend;
  final double currentTotal;
  final double lastMonthTotal;
  final double dailyAverage;
}

/// Insight into the top vendor for the month.
class TopVendorInsight {
  const TopVendorInsight({
    required this.name,
    required this.total,
    required this.percent,
  });

  final String name;
  final double total;
  final double percent;

  bool get hasData => total > 0;
}

/// ✅ NEW: Category breakdown data for pie chart
class CategoryBreakdown {
  const CategoryBreakdown({
    required this.categoryName,
    required this.total,
    required this.receiptCount,
    required this.percentage,
  });

  final String categoryName;
  final double total;
  final int receiptCount;
  final double percentage; // of total spending in that period
}

/// Detailed snapshot for an arbitrary selected period.
class PeriodSummary {
  const PeriodSummary({required this.stats, required this.topVendor});

  final QuickStats stats;
  final TopVendorInsight topVendor;
}

/// Human readable feedback about current spending.
class SmartExpenseInsight {
  const SmartExpenseInsight({
    required this.headline,
    required this.isSaving,
    required this.deltaPercent,
    required this.highlights,
  });

  final String headline;
  final bool isSaving;
  final double? deltaPercent;
  final List<String> highlights;
}

/// Container for all summary data used by the page.
class MonthlySummaryData {
  MonthlySummaryData({
    required this.monthlyPoints,
    required this.weeklyPoints,
    required this.yearlyPoints,
    required this.quickStats,
    required this.topVendor,
    required this.smartInsight,
  });

  final List<SummarySeriesPoint> monthlyPoints;
  final List<SummarySeriesPoint> weeklyPoints;
  final List<SummarySeriesPoint> yearlyPoints;
  final QuickStats quickStats;
  final TopVendorInsight topVendor;
  final SmartExpenseInsight smartInsight;

  List<SummarySeriesPoint> pointsFor(SummaryGranularity granularity) {
    switch (granularity) {
      case SummaryGranularity.monthly:
        return monthlyPoints;
      case SummaryGranularity.weekly:
        return weeklyPoints;
      case SummaryGranularity.yearly:
        return yearlyPoints;
    }
  }

  double maxFor(SummaryGranularity granularity) {
    return pointsFor(
      granularity,
    ).fold<double>(0, (max, point) => point.total > max ? point.total : max);
  }

  static MonthlySummaryData fromReceipts(List<ReceiptEntity> receipts) {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final daysInMonth = now.difference(startOfMonth).inDays + 1;

    final validReceipts = receipts
        .where(
          (r) =>
              r.total != null &&
              r.date.isBefore(now.add(const Duration(days: 1))),
        )
        .toList();

    final monthlyPoints = _buildSeries(
      validReceipts,
      now,
      granularity: SummaryGranularity.monthly,
      bucketCount: 12,
    );
    final weeklyPoints = _buildSeries(
      validReceipts,
      now,
      granularity: SummaryGranularity.weekly,
      bucketCount: 12,
    );
    final yearlyPoints = _buildSeries(
      validReceipts,
      now,
      granularity: SummaryGranularity.yearly,
      bucketCount: 5,
    );

    final monthlyMap = {
      for (final point in monthlyPoints)
        _bucketKey(SummaryGranularity.monthly, point.period): point.total,
    };
    final currentMonthKey = _bucketKey(SummaryGranularity.monthly, now);
    final lastMonthKey = _bucketKey(
      SummaryGranularity.monthly,
      DateTime(now.year, now.month - 1),
    );

    final thisMonthTotal = monthlyMap[currentMonthKey] ?? 0;
    final lastMonthTotal = monthlyMap[lastMonthKey] ?? 0;

    final thisMonthReceipts = validReceipts
        .where((r) => r.date.year == now.year && r.date.month == now.month)
        .toList();
    final currentReceiptTotals = thisMonthReceipts
        .map((r) => r.total ?? 0)
        .toList();
    final currentAverage = currentReceiptTotals.isEmpty
        ? 0
        : currentReceiptTotals.reduce((value, element) => value + element) /
              currentReceiptTotals.length;

    // Calculate daily average
    final dailyAvg = daysInMonth > 0 ? thisMonthTotal / daysInMonth : 0.0;

    final quickStats = QuickStats(
      receiptsCount: thisMonthReceipts.length,
      averageSpend: currentAverage.toDouble(),
      currentTotal: thisMonthTotal,
      lastMonthTotal: lastMonthTotal,
      dailyAverage: dailyAvg,
    );

    final topVendor = _computeTopVendor(thisMonthReceipts, thisMonthTotal);
    final smartInsight = _buildInsight(quickStats, topVendor);

    return MonthlySummaryData(
      monthlyPoints: monthlyPoints,
      weeklyPoints: weeklyPoints,
      yearlyPoints: yearlyPoints,
      quickStats: quickStats,
      topVendor: topVendor,
      smartInsight: smartInsight,
    );
  }

  static List<SummarySeriesPoint> _buildSeries(
    List<ReceiptEntity> receipts,
    DateTime now, {
    required SummaryGranularity granularity,
    required int bucketCount,
  }) {
    final buckets = _generateBuckets(now, granularity, bucketCount);
    final Map<DateTime, double> totals = {
      for (final bucket in buckets) bucket: 0,
    };

    for (final receipt in receipts) {
      final key = _bucketKey(granularity, receipt.date);
      if (!totals.containsKey(key)) {
        // Ignore buckets outside the requested window.
        continue;
      }
      totals[key] = (totals[key] ?? 0) + (receipt.total ?? 0);
    }

    return buckets
        .map(
          (bucket) =>
              SummarySeriesPoint(period: bucket, total: totals[bucket] ?? 0),
        )
        .toList(growable: false);
  }

  static List<DateTime> _generateBuckets(
    DateTime now,
    SummaryGranularity granularity,
    int bucketCount,
  ) {
    switch (granularity) {
      case SummaryGranularity.monthly:
        final start = DateTime(now.year, now.month - (bucketCount - 1));
        return List<DateTime>.generate(bucketCount, (index) {
          final date = DateTime(start.year, start.month + index);
          return DateTime(date.year, date.month);
        });
      case SummaryGranularity.weekly:
        final startOfCurrentWeek = _startOfWeek(now);
        final start = startOfCurrentWeek.subtract(
          Duration(days: 7 * (bucketCount - 1)),
        );
        return List<DateTime>.generate(
          bucketCount,
          (index) => start.add(Duration(days: 7 * index)),
        );
      case SummaryGranularity.yearly:
        final start = DateTime(now.year - (bucketCount - 1));
        return List<DateTime>.generate(
          bucketCount,
          (index) => DateTime(start.year + index),
        );
    }
  }

  static DateTime _bucketKey(SummaryGranularity granularity, DateTime date) {
    switch (granularity) {
      case SummaryGranularity.monthly:
        return DateTime(date.year, date.month);
      case SummaryGranularity.weekly:
        return _startOfWeek(date);
      case SummaryGranularity.yearly:
        return DateTime(date.year);
    }
  }

  static DateTime _startOfWeek(DateTime date) {
    final weekday = date.weekday; // Monday = 1
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: weekday - 1));
  }

  static TopVendorInsight _computeTopVendor(
    List<ReceiptEntity> receipts,
    double monthTotal,
  ) {
    if (receipts.isEmpty || monthTotal == 0) {
      return const TopVendorInsight(name: 'No data', total: 0, percent: 0);
    }

    final Map<String, double> totals = {};
    for (final receipt in receipts) {
      final merchant = receipt.merchant?.trim();
      final key = (merchant == null || merchant.isEmpty)
          ? 'Unknown vendor'
          : merchant;
      totals[key] = (totals[key] ?? 0) + (receipt.total ?? 0);
    }

    totals.removeWhere((_, value) => value == 0);
    if (totals.isEmpty) {
      return const TopVendorInsight(name: 'No data', total: 0, percent: 0);
    }

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topEntry = sorted.first;
    final percent = (topEntry.value / monthTotal) * 100;

    return TopVendorInsight(
      name: topEntry.key,
      total: topEntry.value,
      percent: percent,
    );
  }

  static SmartExpenseInsight _buildInsight(
    QuickStats stats,
    TopVendorInsight topVendor,
  ) {
    final current = stats.currentTotal;
    final previous = stats.lastMonthTotal;
    final hasHistorical = previous > 0;
    final rawDelta = hasHistorical ? current - previous : null;
    final deltaPercent = rawDelta != null ? (rawDelta / previous) * 100 : null;

    String headline;
    bool isSaving = false;

    if (current == 0 && previous == 0) {
      headline = 'No spending yet. Start by capturing your first receipt.';
    } else if (!hasHistorical) {
      headline = 'Great start! This is your first tracked month.';
    } else if (deltaPercent != null && deltaPercent > 0) {
      headline =
          'Spending up ${deltaPercent.toStringAsFixed(1)}% vs last month—review discretionary costs.';
    } else if (deltaPercent != null && deltaPercent < 0) {
      headline =
          'Nice work! Spending down ${deltaPercent.abs().toStringAsFixed(1)}% compared to last month.';
      isSaving = true;
    } else {
      headline = 'Spending held steady compared to last month.';
    }

    final List<String> highlights = [];
    if (topVendor.percent >= 40) {
      highlights.add(
        'Most spending concentrated on ${topVendor.name} (${topVendor.percent.toStringAsFixed(1)}%).',
      );
    }
    if (deltaPercent != null && deltaPercent > 15) {
      highlights.add(
        'Large month-over-month increase detected—consider tightening budgets.',
      );
    } else if (deltaPercent != null && deltaPercent < -20) {
      highlights.add(
        'Deep savings this month—consider setting aside the difference for goals.',
      );
      isSaving = true;
    }
    if (stats.receiptsCount >= 20) {
      highlights.add(
        'High receipt volume (${stats.receiptsCount})—automate categorisation to save time.',
      );
    }

    return SmartExpenseInsight(
      headline: headline,
      isSaving: isSaving,
      deltaPercent: deltaPercent,
      highlights: highlights,
    );
  }

  static SmartExpenseInsight buildInsight(QuickStats quickStats, TopVendorInsight topVendorInsight) {
    return _buildInsight(quickStats, topVendorInsight);
  }
}

/// Coordinates Isar watchers and publishes aggregated summary data.
class MonthlySummaryService {
  MonthlySummaryService(this._isar) {
    _subscription = _isar.receiptEntitys
        .watchLazy(fireImmediately: true)
        .listen((_) => _emit());
  }

  final Isar _isar;
  final StreamController<MonthlySummaryData> _controller =
      StreamController<MonthlySummaryData>.broadcast();
  late final StreamSubscription<void> _subscription;
  bool _isDisposed = false;
  Future<void>? _pending;

  Stream<MonthlySummaryData> get stream => _controller.stream;

  Future<void> _emit() async {
    if (_isDisposed) return;
    // Collapse bursts of events into a single emission.
    if (_pending != null) {
      return;
    }
    _pending = _loadAndAdd().whenComplete(() {
      _pending = null;
    });
    await _pending;
  }

  Future<void> _loadAndAdd() async {
    final receipts = await _isar.receiptEntitys.where().findAll();
    if (_isDisposed) return;
    final data = MonthlySummaryData.fromReceipts(receipts);
    if (!_controller.isClosed) {
      _controller.add(data);
    }
  } 

  Future<PeriodSummary> summaryForPeriod(
    DateTime? period,
    SummaryGranularity granularity,
  ) async {
    DateTime normalize(DateTime value) {
      switch (granularity) {
        case SummaryGranularity.monthly:
          return DateTime(value.year, value.month);
        case SummaryGranularity.weekly:
          return MonthlySummaryData._startOfWeek(value);
        case SummaryGranularity.yearly:
          return DateTime(value.year);
      }
    }

    DateTime previous(DateTime start) {
      switch (granularity) {
        case SummaryGranularity.monthly:
          return DateTime(start.year, start.month - 1);
        case SummaryGranularity.weekly:
          return start.subtract(const Duration(days: 7));
        case SummaryGranularity.yearly:
          return DateTime(start.year - 1);
      }
    }

    DateTime endExclusive(DateTime start) {
      switch (granularity) {
        case SummaryGranularity.monthly:
          return DateTime(start.year, start.month + 1);
        case SummaryGranularity.weekly:
          return start.add(const Duration(days: 7));
        case SummaryGranularity.yearly:
          return DateTime(start.year + 1);
      }
    }

    bool within(DateTime candidate, DateTime start) {
      final end = endExclusive(start);
      return !candidate.isBefore(start) && candidate.isBefore(end);
    }

    final now = DateTime.now();
    final target = normalize(period ?? now);
    final prev = previous(target);
    final receipts = await _isar.receiptEntitys.where().findAll();

    final currentReceipts = receipts
        .where((r) => r.total != null && within(r.date, target))
        .toList();
    final previousReceipts = receipts
        .where((r) => r.total != null && within(r.date, prev))
        .toList();

    double sum(List<ReceiptEntity> source) =>
        source.fold<double>(0, (acc, r) => acc + (r.total ?? 0));

    final currentTotal = sum(currentReceipts);
    final previousTotal = sum(previousReceipts);
    final avg =
        currentReceipts.isEmpty ? 0.0 : currentTotal / currentReceipts.length;

    // Calculate daily average for the selected period
    final periodStart = target;
    final periodEnd = endExclusive(target);
    final daysInPeriod = periodEnd.difference(periodStart).inDays;
    final dailyAvg = daysInPeriod > 0 ? currentTotal / daysInPeriod : 0.0;

    final quickStats = QuickStats(
      receiptsCount: currentReceipts.length,
      averageSpend: avg,
      currentTotal: currentTotal,
      lastMonthTotal: previousTotal,
      dailyAverage: dailyAvg,
    );

    final topVendor =
        MonthlySummaryData._computeTopVendor(currentReceipts, currentTotal);

    return PeriodSummary(stats: quickStats, topVendor: topVendor);
  }

  /// ✅ NEW: Get category breakdown for a specific period
  Future<List<CategoryBreakdown>> getCategoryBreakdown(
    DateTime period,
    SummaryGranularity granularity,
  ) async {
    // Normalize period start
    DateTime normalize(DateTime value) {
      switch (granularity) {
        case SummaryGranularity.monthly:
          return DateTime(value.year, value.month);
        case SummaryGranularity.weekly:
          return MonthlySummaryData._startOfWeek(value);
        case SummaryGranularity.yearly:
          return DateTime(value.year);
      }
    }

    // Get period end
    DateTime endExclusive(DateTime start) {
      switch (granularity) {
        case SummaryGranularity.monthly:
          return DateTime(start.year, start.month + 1);
        case SummaryGranularity.weekly:
          return start.add(const Duration(days: 7));
        case SummaryGranularity.yearly:
          return DateTime(start.year + 1);
      }
    }

    // Check if receipt is within period
    bool within(DateTime candidate, DateTime start) {
      final end = endExclusive(start);
      return !candidate.isBefore(start) && candidate.isBefore(end);
    }

    final target = normalize(period);
    final receipts = await _isar.receiptEntitys.where().findAll();

    // Filter receipts for this period
    final periodReceipts = receipts
        .where((r) => r.total != null && within(r.date, target))
        .toList();

    if (periodReceipts.isEmpty) return [];

    // Group by category
    final Map<String, double> categoryTotals = {};
    final Map<String, int> categoryReceipts = {};

    for (final receipt in periodReceipts) {
      final category = receipt.category?.trim();
      if (category == null || category.isEmpty) continue;

      categoryTotals[category] = (categoryTotals[category] ?? 0) + (receipt.total ?? 0);
      categoryReceipts[category] = (categoryReceipts[category] ?? 0) + 1;
    }

    // Calculate total spending in period
    final totalSpending = categoryTotals.values.fold<double>(0, (sum, val) => sum + val);

    if (totalSpending == 0) return [];

    // Build breakdown list
    final breakdown = categoryTotals.entries.map((entry) {
      final categoryName = entry.key;
      final total = entry.value;
      final receiptCount = categoryReceipts[categoryName] ?? 0;
      final percentage = (total / totalSpending) * 100;

      return CategoryBreakdown(
        categoryName: categoryName,
        total: total,
        receiptCount: receiptCount,
        percentage: percentage,
      );
    }).toList();

    // Sort by total (descending)
    breakdown.sort((a, b) => b.total.compareTo(a.total));

    return breakdown;
  }

  /// ✅ NEW: Get stats for a specific category in a period
  Future<QuickStats> getStatsForCategory(
    DateTime period,
    SummaryGranularity granularity,
    String category,
  ) async {
    // Reuse normalization logic
    DateTime normalize(DateTime value) {
      switch (granularity) {
        case SummaryGranularity.monthly:
          return DateTime(value.year, value.month);
        case SummaryGranularity.weekly:
          return MonthlySummaryData._startOfWeek(value);
        case SummaryGranularity.yearly:
          return DateTime(value.year);
      }
    }

    DateTime endExclusive(DateTime start) {
      switch (granularity) {
        case SummaryGranularity.monthly:
          return DateTime(start.year, start.month + 1);
        case SummaryGranularity.weekly:
          return start.add(const Duration(days: 7));
        case SummaryGranularity.yearly:
          return DateTime(start.year + 1);
      }
    }

    bool within(DateTime candidate, DateTime start) {
      final end = endExclusive(start);
      return !candidate.isBefore(start) && candidate.isBefore(end);
    }

    final target = normalize(period);
    final receipts = await _isar.receiptEntitys.where().findAll();

    // Filter by period AND category
    final filteredReceipts = receipts.where((r) {
      return r.total != null &&
          within(r.date, target) &&
          r.category?.trim() == category;
    }).toList();

    final total = filteredReceipts.fold<double>(0, (sum, r) => sum + (r.total ?? 0));
    final avg = filteredReceipts.isEmpty ? 0.0 : total / filteredReceipts.length;

    // Calculate daily pace
    final periodStart = target;
    final periodEnd = endExclusive(target);
    final daysInPeriod = periodEnd.difference(periodStart).inDays;
    final dailyAvg = daysInPeriod > 0 ? total / daysInPeriod : 0.0;

    return QuickStats(
      receiptsCount: filteredReceipts.length,
      averageSpend: avg,
      currentTotal: total,
      lastMonthTotal: 0, // Not used for category filtering
      dailyAverage: dailyAvg,
    );
  }

  /// ✅ NEW: Get top vendor for a specific category in a period
  Future<TopVendorInsight> getTopVendorForCategory(
    DateTime period,
    SummaryGranularity granularity,
    String category,
  ) async {
    DateTime normalize(DateTime value) {
      switch (granularity) {
        case SummaryGranularity.monthly:
          return DateTime(value.year, value.month);
        case SummaryGranularity.weekly:
          return MonthlySummaryData._startOfWeek(value);
        case SummaryGranularity.yearly:
          return DateTime(value.year);
      }
    }

    DateTime endExclusive(DateTime start) {
      switch (granularity) {
        case SummaryGranularity.monthly:
          return DateTime(start.year, start.month + 1);
        case SummaryGranularity.weekly:
          return start.add(const Duration(days: 7));
        case SummaryGranularity.yearly:
          return DateTime(start.year + 1);
      }
    }

    bool within(DateTime candidate, DateTime start) {
      final end = endExclusive(start);
      return !candidate.isBefore(start) && candidate.isBefore(end);
    }

    final target = normalize(period);
    final receipts = await _isar.receiptEntitys.where().findAll();

    // Filter by period AND category
    final filteredReceipts = receipts.where((r) {
      return r.total != null &&
          within(r.date, target) &&
          r.category?.trim() == category;
    }).toList();

    final total = filteredReceipts.fold<double>(0, (sum, r) => sum + (r.total ?? 0));

    return MonthlySummaryData._computeTopVendor(filteredReceipts, total);
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _pending = null;
    unawaited(_subscription.cancel());
    _controller.close();
  }
}