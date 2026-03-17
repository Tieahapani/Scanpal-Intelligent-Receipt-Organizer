import 'package:flutter/material.dart' show DateTimeRange;
import '../receipt.dart';

/// Quick stats for a date range.
class QuickStats {
  final double currentTotal;
  final double? dailyAverage;
  final int receiptsCount;

  const QuickStats({
    required this.currentTotal,
    this.dailyAverage,
    required this.receiptsCount,
  });
}

/// Category breakdown for reports.
class CategoryBreakdown {
  final String categoryName;
  final double total;
  final int receiptCount;
  final double percentage;

  const CategoryBreakdown({
    required this.categoryName,
    required this.total,
    required this.receiptCount,
    required this.percentage,
  });
}

/// Smart expense insight (trend card).
class SmartExpenseInsight {
  final String headline;
  final bool isSaving;
  final List<String> highlights;

  const SmartExpenseInsight({
    required this.headline,
    required this.isSaving,
    this.highlights = const [],
  });
}

/// Top vendor insight.
class TopVendorInsight {
  final String name;
  final double total;
  final double percent;

  const TopVendorInsight({
    required this.name,
    required this.total,
    required this.percent,
  });
}

/// Computes analytics from a list of receipts fetched via API.
class MonthlySummaryService {
  final List<Receipt> _receipts;

  MonthlySummaryService(this._receipts);

  /// Filter receipts within a date range.
  List<Receipt> receiptsInRange(DateTimeRange range) {
    return _receipts.where((r) {
      if (r.date == null) return false;
      return !r.date!.isBefore(range.start) &&
          r.date!.isBefore(range.end.add(const Duration(days: 1)));
    }).toList();
  }

  /// Quick stats for the given date range.
  QuickStats quickStats(DateTimeRange range) {
    final filtered = receiptsInRange(range);
    final total = filtered.fold(0.0, (s, r) => s + r.effectiveTotal);
    final days = range.end.difference(range.start).inDays + 1;
    return QuickStats(
      currentTotal: total,
      dailyAverage: days > 0 ? total / days : null,
      receiptsCount: filtered.length,
    );
  }

  /// Category breakdown for the given date range.
  List<CategoryBreakdown> categoryBreakdown(DateTimeRange range) {
    final filtered = receiptsInRange(range);
    final total = filtered.fold(0.0, (s, r) => s + r.effectiveTotal);
    if (total == 0) return [];

    final Map<String, _Bucket> buckets = {};
    for (final r in filtered) {
      final cat = r.travelCategory ?? r.category ?? 'Uncategorized';
      buckets.putIfAbsent(cat, () => _Bucket());
      buckets[cat]!.total += r.effectiveTotal;
      buckets[cat]!.count += 1;
    }

    final list = buckets.entries.map((e) {
      return CategoryBreakdown(
        categoryName: e.key,
        total: e.value.total,
        receiptCount: e.value.count,
        percentage: (e.value.total / total) * 100,
      );
    }).toList();

    list.sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  /// Vendor breakdown for the given date range.
  List<VendorBreakdown> vendorBreakdown(DateTimeRange range) {
    final filtered = receiptsInRange(range);
    final total = filtered.fold(0.0, (s, r) => s + r.effectiveTotal);
    if (total == 0) return [];

    final Map<String, _Bucket> buckets = {};
    for (final r in filtered) {
      final vendor = r.merchant ?? 'Unknown';
      buckets.putIfAbsent(vendor, () => _Bucket());
      buckets[vendor]!.total += r.effectiveTotal;
      buckets[vendor]!.count += 1;
    }

    final list = buckets.entries.map((e) {
      return VendorBreakdown(
        vendorName: e.key,
        total: e.value.total,
        receiptCount: e.value.count,
        percentage: (e.value.total / total) * 100,
      );
    }).toList();

    list.sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  /// Smart expense insight based on spending patterns.
  SmartExpenseInsight expenseInsight(DateTimeRange range) {
    final stats = quickStats(range);
    final cats = categoryBreakdown(range);

    if (stats.receiptsCount == 0) {
      return const SmartExpenseInsight(
        headline: 'No expenses recorded this period',
        isSaving: true,
      );
    }

    final topCat = cats.isNotEmpty ? cats.first : null;
    final highlights = <String>[];

    if (topCat != null && topCat.percentage > 50) {
      highlights.add(
        '${topCat.categoryName} accounts for ${topCat.percentage.toStringAsFixed(0)}% of spending',
      );
    }
    if (stats.dailyAverage != null) {
      highlights.add(
        'Daily average: \$${stats.dailyAverage!.toStringAsFixed(2)}',
      );
    }
    highlights.add('${stats.receiptsCount} transactions tracked');

    final isSaving = (stats.dailyAverage ?? 0) < 50;
    return SmartExpenseInsight(
      headline: isSaving
          ? 'Spending is well-controlled'
          : 'Higher than average spending',
      isSaving: isSaving,
      highlights: highlights,
    );
  }

  /// Top vendor insight for the period.
  TopVendorInsight? topVendorInsight(DateTimeRange range) {
    final vendors = vendorBreakdown(range);
    if (vendors.isEmpty) return null;
    final top = vendors.first;
    return TopVendorInsight(
      name: top.vendorName,
      total: top.total,
      percent: top.percentage,
    );
  }
}

/// Vendor breakdown data (also used by ExpenseReportPage).
class VendorBreakdown {
  final String vendorName;
  final double total;
  final int receiptCount;
  final double percentage;

  const VendorBreakdown({
    required this.vendorName,
    required this.total,
    required this.receiptCount,
    required this.percentage,
  });
}

class _Bucket {
  double total = 0;
  int count = 0;
}
