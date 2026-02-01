import 'package:finpal/entities.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:intl/intl.dart';
import '/local_db.dart';
import 'services/monthly_summary_service.dart';
import 'expense_report_page.dart'; // Import the report page
import 'custom_date_range_picker.dart'; // Import custom date picker

class MonthlySummaryPage extends StatefulWidget {
  const MonthlySummaryPage({super.key});

  @override
  State<MonthlySummaryPage> createState() => _MonthlySummaryPageState();
}

class _MonthlySummaryPageState extends State<MonthlySummaryPage> {
  late Future<Isar> _isarFuture;
  Isar? _isar;
  MonthlySummaryService? _summaryService;

  SummaryGranularity _selectedGranularity = SummaryGranularity.monthly;
  DateTime? _selectedMonthRoot;
  DateTime? _selectedPeriodStart;
  String? _selectedCategory;

  QuickStats? _selectedQuickStats;
  TopVendorInsight? _selectedTopVendor;
  List<SummarySeriesPoint>? _customWeeklyPoints;
  List<CategoryBreakdown>? _categoryBreakdown;
  List<VendorBreakdown>? _vendorBreakdown; // Add vendor breakdown

  // Date range filter state
  DateTimeRange? _customDateRange;
  bool _isDateRangeMode = false;
  
  // Cache last summary data to avoid loading screen
  MonthlySummaryData? _lastSummaryData;

  late NumberFormat _currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  String _currencySymbol = '\$';

  static const int _daysPerBucket = 5;

  // ---------------- DATE RANGE PICKER ----------------

  Future<void> _selectDateRange() async {
    final picked = await showCustomDateRangePicker(
      context: context,
      initialDateRange: _customDateRange,
    );

    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _isDateRangeMode = true;
        _selectedCategory = null;
        _categoryBreakdown = null;
      });
      await _loadDateRangeData();
    }
  }

  Future<void> _loadDateRangeData() async {
    if (_customDateRange == null || _isar == null) return;

    final start = _customDateRange!.start;
    final end = _customDateRange!.end.add(const Duration(days: 1)); // Make end inclusive

    final allReceipts = await _isar!.receiptEntitys.where().findAll();

    // Filter receipts by date range
    final receipts = allReceipts.where((receipt) {
      return _isDateInRange(receipt.date, start, end);
    }).toList();

    // Calculate stats
    final total = receipts.fold<double>(0, (sum, r) => sum + r.total);
    final avg = receipts.isEmpty ? 0.0 : total / receipts.length;
    final daysDiff = end.difference(start).inDays;
    final numDays = daysDiff > 0 ? daysDiff : 1;
    final dailyPace = total / numDays;

    // Calculate top vendor
    final vendorTotals = <String, double>{};
    for (final receipt in receipts) {
      final vendor = receipt.merchant?.trim() ?? '';
      if (vendor.isNotEmpty) {
        vendorTotals[vendor] = (vendorTotals[vendor] ?? 0) + receipt.total;
      }
    }

    String topVendorName = '';
    double topVendorTotal = 0;
    double topVendorPercent = 0;

    if (vendorTotals.isNotEmpty && total > 0) {
      final topEntry = vendorTotals.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );
      topVendorName = topEntry.key;
      topVendorTotal = topEntry.value;
      topVendorPercent = (topVendorTotal / total) * 100;
    }

    // Calculate category breakdown
    final categoryTotals = <String, double>{};
    final categoryCounts = <String, int>{};

    for (final receipt in receipts) {
      final category = receipt.category?.trim() ?? 'Uncategorized';
      categoryTotals[category] = (categoryTotals[category] ?? 0) + receipt.total;
      categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
    }

    final totalSpending = categoryTotals.values.fold<double>(0, (sum, val) => sum + val);
    final breakdown = categoryTotals.entries.map((entry) {
      final percentage = totalSpending > 0 ? (entry.value / totalSpending) * 100 : 0.0;
      return CategoryBreakdown(
        categoryName: entry.key,
        total: entry.value,
        receiptCount: categoryCounts[entry.key] ?? 0,
        percentage: percentage,
      );
    }).toList();

    breakdown.sort((a, b) => b.total.compareTo(a.total));

    // Calculate vendor breakdown
    final vendorBreakdown = vendorTotals.entries.map((entry) {
      final percentage = totalSpending > 0 ? (entry.value / totalSpending) * 100 : 0.0;
      return VendorBreakdown(
        vendorName: entry.key,
        total: entry.value,
        receiptCount: receipts.where((r) => r.merchant?.trim() == entry.key).length,
        percentage: percentage,
      );
    }).toList();

    vendorBreakdown.sort((a, b) => b.total.compareTo(a.total));

    if (!mounted) return;
    setState(() {
      _selectedQuickStats = QuickStats(
        currentTotal: total,
        receiptsCount: receipts.length,
        averageSpend: avg,
        lastMonthTotal: 0,
        dailyAverage: dailyPace,
      );
      _selectedTopVendor = TopVendorInsight(
        name: topVendorName,
        total: topVendorTotal,
        percent: topVendorPercent,
      );
      _categoryBreakdown = breakdown;
      _vendorBreakdown = vendorBreakdown;
    });
  }

  void _clearDateRange() {
    setState(() {
      _customDateRange = null;
      _isDateRangeMode = false;
      _selectedQuickStats = null;
      _selectedTopVendor = null;
      _categoryBreakdown = null;
      _vendorBreakdown = null; // Clear vendor breakdown
      _selectedCategory = null;
      _selectedPeriodStart = null;
      _customWeeklyPoints = null;
      
      // Reset to current month
      final now = DateTime.now();
      _selectedMonthRoot = DateTime(now.year, now.month);
    });
  }

  // ---------------- DATE HELPER ----------------

  bool _isDateInRange(DateTime receiptDate, DateTime start, DateTime end) {
    final isAfterStart = receiptDate.year > start.year ||
        (receiptDate.year == start.year && receiptDate.month > start.month) ||
        (receiptDate.year == start.year &&
            receiptDate.month == start.month &&
            receiptDate.day >= start.day);

    final isBeforeEnd = receiptDate.year < end.year ||
        (receiptDate.year == end.year && receiptDate.month < end.month) ||
        (receiptDate.year == end.year &&
            receiptDate.month == end.month &&
            receiptDate.day < end.day);

    return isAfterStart && isBeforeEnd;
  } 

  // ---------------- CURRENCY HELPERS ----------------

Future<String> _detectPrimaryCurrency() async {
  final isar = _isar;
  if (isar == null) return '\$';
  
  final receipts = await isar.receiptEntitys.where().findAll();
  if (receipts.isEmpty) return '\$';
  
  // Count currency occurrences
  final currencyCounts = <String, int>{};
  for (final receipt in receipts) {
    final currency = receipt.currency ?? '\$';
    currencyCounts[currency] = (currencyCounts[currency] ?? 0) + 1;
  }
  
  // Find most common currency
  String mostCommon = '\$';
  int maxCount = 0;
  currencyCounts.forEach((currency, count) {
    if (count > maxCount) {
      maxCount = count;
      mostCommon = currency;
    }
  });
  
  return mostCommon;
}

NumberFormat _getCurrencyFormat(String symbol) {
  switch (symbol) {
    case '₹':
      return NumberFormat.currency(symbol: '₹', decimalDigits: 2);
    case '€':
      return NumberFormat.currency(symbol: '€', decimalDigits: 2);
    case '£':
      return NumberFormat.currency(symbol: '£', decimalDigits: 2);
    case '\$':
    default:
      return NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  }
}



  // ---------------- WEEKLY LOGIC ----------------

  Future<List<SummarySeriesPoint>> _generateFiveDayWeeklyPoints(
    DateTime monthRoot,
  ) async {
    final isar = _isar;
    if (isar == null) return [];

    final mStart = DateTime(monthRoot.year, monthRoot.month, 1);
    final mEndExclusive = DateTime(monthRoot.year, monthRoot.month + 1, 1);

    // Generate start dates: 1, 6, 11, 16, 21, 26
    final starts = <DateTime>[];
    for (int day = 1; day < 32; day += _daysPerBucket) {
      final start = DateTime(mStart.year, mStart.month, day);
      if (start.isBefore(mEndExclusive)) {
        starts.add(start);
      } else {
        break;
      }
    }

    // Fetch all receipts once
    final allReceipts = await isar.receiptEntitys.where().findAll();
    final points = <SummarySeriesPoint>[];

    for (final s in starts) {
      final e = _weeklyWindowEnd(s);

      final receipts = allReceipts.where((receipt) {
        final inRange = _isDateInRange(receipt.date, s, e);

        // Apply category filter if selected
        final categoryMatch = _selectedCategory == null ||
            receipt.category == _selectedCategory;

        return inRange && categoryMatch;
      }).toList();

      final total = receipts.fold<double>(0, (sum, r) => sum + r.total);
      points.add(SummarySeriesPoint(period: s, total: total));
    }

    return points;
  }

  DateTime _weeklyWindowEnd(DateTime start) {
    final bucketEndExclusive = DateTime(
      start.year,
      start.month,
      start.day + _daysPerBucket,
    );
    final monthEndExclusive = DateTime(start.year, start.month + 1, 1);
    return bucketEndExclusive.isBefore(monthEndExclusive)
        ? bucketEndExclusive
        : monthEndExclusive;
  }

  String _weeklyRangeLabel(DateTime start, {bool multiline = false}) {
    final endExclusive = _weeklyWindowEnd(start);
    final endInclusive = endExclusive.subtract(const Duration(days: 1));

    final monthStart = DateFormat.MMM().format(start);
    final monthEnd = DateFormat.MMM().format(endInclusive);

    if (!multiline) {
      if (start.month == endInclusive.month) {
        return '$monthStart\n${start.day}-${endInclusive.day}';
      }
      return '${monthStart.substring(0, 1)}${start.day}-${monthEnd.substring(0, 1)}${endInclusive.day}';
    }

    final sep = '\n';
    if (start.month == endInclusive.month) {
      return '$monthStart ${start.day}$sep${endInclusive.day}';
    }
    return '$monthStart ${start.day}$sep$monthEnd ${endInclusive.day}';
  }

  // -----------------------------------------------------

  void _onGranularityChange(SummaryGranularity granularity) {
    setState(() {
      _selectedGranularity = granularity;
      _customWeeklyPoints = null;
      _selectedQuickStats = null;
      _selectedTopVendor = null;
      _selectedPeriodStart = null;
      _selectedCategory = null;
      _categoryBreakdown = null;

      final now = DateTime.now();
      _selectedMonthRoot = DateTime(now.year, now.month);
    });
  } 

@override
void initState() {
  super.initState();
  _isarFuture = LocalDb.instance();
  final now = DateTime.now();
  _selectedMonthRoot = DateTime(now.year, now.month);
  _selectedPeriodStart = null;
  _selectedCategory = null;
  
  // Detect currency after Isar is ready
  _isarFuture.then((isar) async {
    _isar = isar;
    final symbol = await _detectPrimaryCurrency();
    if (mounted) {
      setState(() {
        _currencySymbol = symbol;
        _currency = _getCurrencyFormat(symbol);
      });
    }
  });
}



  @override
  void dispose() {
    _summaryService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Spending Analytics',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: FutureBuilder<Isar>(
        future: _isarFuture,
        builder: (context, isarSnap) {
          if (isarSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!isarSnap.hasData) {
            return const Center(child: Text('Unable to load data'));
          }

          _isar ??= isarSnap.data!;
          _summaryService ??= MonthlySummaryService(_isar!);

          // If in date range mode, show custom UI
          if (_isDateRangeMode) {
            return _buildDateRangeView();
          }

          return StreamBuilder<MonthlySummaryData>(
            stream: _summaryService!.stream,
            builder: (context, summarySnap) {
              // Cache the data when available
              if (summarySnap.hasData) {
                _lastSummaryData = summarySnap.data;
              }
              
              // Use cached data if no new data available
              final summary = summarySnap.hasData ? summarySnap.data! : _lastSummaryData;
              
              if (summary == null) {
                return const Center(child: CircularProgressIndicator());
              }

              final now = DateTime.now();
              final root = _selectedMonthRoot ?? DateTime(now.year, now.month);

              List<SummarySeriesPoint> points = [];
              QuickStats statsToShow;
              TopVendorInsight topToShow;

              if (_selectedGranularity == SummaryGranularity.weekly) {
                points = _customWeeklyPoints ?? [];
                if (points.isEmpty) {
                  return FutureBuilder<List<SummarySeriesPoint>>(
                    future: _generateFiveDayWeeklyPoints(root),
                    builder: (context, weekSnap) {
                      if (weekSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final data = weekSnap.data ?? [];
                      if (data.isEmpty) {
                        return const Center(child: Text('No receipts yet'));
                      }
                      _customWeeklyPoints = data;
                      points = data;

                      statsToShow = _selectedQuickStats ?? summary.quickStats;
                      topToShow = _selectedTopVendor ?? summary.topVendor;

                      return _buildMain(points, statsToShow, topToShow);
                    },
                  );
                }
                statsToShow = _selectedQuickStats ?? summary.quickStats;
                topToShow = _selectedTopVendor ?? summary.topVendor;
              } else {
                points = summary.pointsFor(_selectedGranularity);
                if (_selectedGranularity == SummaryGranularity.monthly &&
                    points.length > 6) {
                  points = points.sublist(points.length - 6);
                }
                statsToShow = _selectedQuickStats ?? summary.quickStats;
                topToShow = _selectedTopVendor ?? summary.topVendor;
              }

              final hasSpending = points.any((p) => p.total > 0);
              if (!hasSpending) {
                return const Center(child: Text('No receipts yet'));
              }

              return _buildMain(points, statsToShow, topToShow);
            },
          );
        },
      ),
    );
  }

  // ---------------- DATE RANGE VIEW ----------------

  Widget _buildDateRangeView() {
    if (_selectedQuickStats == null || 
        _categoryBreakdown == null || 
        _vendorBreakdown == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateRangeHeader(),
          const SizedBox(height: 16),
          _buildOverviewHero(_selectedQuickStats!, null),
          const SizedBox(height: 16),
          _buildCategoryBreakdownSection(),
          const SizedBox(height: 16),
          _buildQuickStats(_selectedQuickStats!),
          const SizedBox(height: 16),
          _buildTopVendorCard(_selectedTopVendor!),
          const SizedBox(height: 16),
          _buildGetReportButton(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDateRangeHeader() {
    final start = _customDateRange!.start;
    final end = _customDateRange!.end;
    final formatter = DateFormat('MMM d, y');

    return _AnalyticsSectionCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today, color: Color(0xFF2563EB), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Custom Date Range',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: _clearDateRange,
                color: const Color(0xFF94A3B8),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBAE6FD)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'From',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatter.format(start),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward, color: Color(0xFF2563EB)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'To',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatter.format(end),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _selectDateRange,
              icon: const Icon(Icons.edit_calendar),
              label: const Text('Change Date Range'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF2563EB),
                elevation: 0,
                side: const BorderSide(color: Color(0xFF2563EB)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGetReportButton() {
    return _AnalyticsSectionCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Generate Report',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Get a detailed expense report with AI-powered insights about your spending habits.',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                if (_customDateRange != null && 
                    _selectedQuickStats != null && 
                    _categoryBreakdown != null &&
                    _vendorBreakdown != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ExpenseReportPage(
                        dateRange: _customDateRange!,
                        stats: _selectedQuickStats!,
                        categoryBreakdown: _categoryBreakdown!,
                        vendorBreakdown: _vendorBreakdown!,
                        currency: _currency,
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.analytics),
              label: const Text('Get Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- MAIN BODY ----------------

  Widget _buildOverviewHero(
    QuickStats stats,
    DateTime? heroPeriodStart,
  ) {
    String headlineLabel;

    if (_isDateRangeMode && _customDateRange != null) {
      final start = DateFormat('MMM d').format(_customDateRange!.start);
      final end = DateFormat('MMM d, y').format(_customDateRange!.end);
      headlineLabel = '$start - $end';
    } else if (heroPeriodStart != null) {
      headlineLabel = _heroLabelFor(heroPeriodStart, _selectedGranularity);
    } else {
      final root = _selectedMonthRoot ?? DateTime.now();
      if (_selectedGranularity == SummaryGranularity.weekly) {
        headlineLabel = DateFormat.yMMMM().format(root);
      } else {
        headlineLabel = _heroLabelFor(
          DateTime(root.year, root.month, 1),
          _selectedGranularity,
        );
      }
    }

    // Add category suffix if a category is selected
    if (_selectedCategory != null) {
      headlineLabel = '$headlineLabel - $_selectedCategory';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(28)),
        gradient: LinearGradient(
          colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x330256EB),
            blurRadius: 30,
            offset: Offset(0, 18),
            spreadRadius: -10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headlineLabel,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Total spend',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _currency.format(stats.currentTotal),
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMain(
    List<SummarySeriesPoint> points,
    QuickStats stats,
    TopVendorInsight topVendor,
  ) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverviewHero(stats, _selectedPeriodStart),
          const SizedBox(height: 16),
          _buildDateRangeButton(),
          const SizedBox(height: 16),
          _buildGranularityToggle(),
          const SizedBox(height: 16),
          _buildChartSection(points),
          const SizedBox(height: 16),
          _buildCategoryBreakdownSection(),
          const SizedBox(height: 16),
          _buildQuickStats(stats),
          const SizedBox(height: 16),
          _buildTopVendorCard(topVendor),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDateRangeButton() {
    return _AnalyticsSectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Custom Analysis',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x330256D4),
                  offset: Offset(0, 6),
                  blurRadius: 16,
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _selectDateRange,
              icon: const Icon(Icons.date_range),
              label: const Text('Select Date Range'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- GRANULARITY TOGGLE ----------------

  Widget _buildGranularityToggle() {
    Widget seg(String label, SummaryGranularity g) {
      final selected = _selectedGranularity == g;
      return Expanded(
        child: GestureDetector(
          onTap: () => _onGranularityChange(g),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: selected ? null : const Color(0xFFF3F4F6),
              gradient: selected
                  ? const LinearGradient(
                      colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x330256D4),
                        offset: Offset(0, 6),
                        blurRadius: 16,
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : const Color(0xFF475569),
              ),
            ),
          ),
        ),
      );
    }

    return _AnalyticsSectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Timeline',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              seg('Monthly', SummaryGranularity.monthly),
              const SizedBox(width: 10),
              seg('Weekly', SummaryGranularity.weekly),
              const SizedBox(width: 10),
              seg('Yearly', SummaryGranularity.yearly),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- CHART SECTION ----------------

  Widget _buildChartSection(List<SummarySeriesPoint> points) {
    String hint;
    switch (_selectedGranularity) {
      case SummaryGranularity.weekly:
        hint = 'Tap a bar to inspect that 5-day window.';
        break;
      case SummaryGranularity.yearly:
        hint = 'Tap a bar to break down that year.';
        break;
      case SummaryGranularity.monthly:
        hint = 'Tap a bar to jump into that month.';
        break;
    }

    return _AnalyticsSectionCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Spending Trend',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              Icon(
                Icons.bar_chart_rounded,
                color: const Color(0xFF2563EB).withOpacity(0.8),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_selectedGranularity == SummaryGranularity.weekly)
            _buildWeeklyMonthNavigator(),
          const SizedBox(height: 8),
          _buildChart(points),
          const SizedBox(height: 12),
          Text(
            hint,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(List<SummarySeriesPoint> points) {
    final maxValue = points.fold<double>(
      0,
      (m, p) => p.total > m ? p.total : m,
    );
    final chartMax = (maxValue == 0 ? 1 : maxValue * 1.2).toDouble();

    return SizedBox(
      height: 240,
      child: BarChart(
        BarChartData(
          maxY: chartMax,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 8,
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final label = _tooltipLabelFor(points[groupIndex].period);
                final amount = _currency.format(rod.toY);
                return BarTooltipItem(
                  '$label\n$amount',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                );
              },
            ),
            touchCallback: (event, response) {
              if (event is! FlTapUpEvent) return;
              final spot = response?.spot;
              if (spot == null) return;
              final index = spot.touchedBarGroupIndex;
              if (index < 0 || index >= points.length) return;
              _selectPeriod(points[index].period);
            },
          ),
          gridData: FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _chartLabelFor(points[index].period),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: List.generate(points.length, (i) {
            final selected = _selectedPeriodStart != null &&
                points[i].period == _selectedPeriodStart;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: points[i].total,
                  width: 22,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                  gradient: LinearGradient(
                    colors: selected
                        ? const [Color(0xFF1D4ED8), Color(0xFF60A5FA)]
                        : const [Color(0xFF93C5FD), Color(0xFFBFDBFE)],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Future<void> _selectPeriod(DateTime period) async {
    final granularity = _selectedGranularity;
    final service = _summaryService;
    if (service == null) return;

    setState(() {
      _selectedPeriodStart = period;
      _selectedCategory = null;
      _categoryBreakdown = null;

      if (granularity == SummaryGranularity.monthly) {
        _selectedMonthRoot = DateTime(period.year, period.month);
        _customWeeklyPoints = null;
      }
    });

    // Load category breakdown for the selected period
    await _loadCategoryBreakdown(period, granularity);

    // For weekly granularity, manually calculate stats
    if (granularity == SummaryGranularity.weekly) {
      final isar = _isar;
      if (isar == null) return;

      final windowEnd = _weeklyWindowEnd(period);
      final allReceipts = await isar.receiptEntitys.where().findAll();

      final receipts = allReceipts.where((receipt) {
        return _isDateInRange(receipt.date, period, windowEnd);
      }).toList();

      final total = receipts.fold<double>(0, (sum, r) => sum + r.total);
      final avg = receipts.isEmpty ? 0.0 : total / receipts.length;

      final daysDiff = windowEnd.difference(period).inDays;
      final numDays = daysDiff > 0 ? daysDiff : 1;
      final dailyPace = total / numDays;

      final vendorTotals = <String, double>{};
      for (final receipt in receipts) {
        final vendor = receipt.merchant?.trim() ?? '';
        if (vendor.isNotEmpty) {
          vendorTotals[vendor] = (vendorTotals[vendor] ?? 0) + receipt.total;
        }
      }

      String topVendorName = '';
      double topVendorTotal = 0;
      double topVendorPercent = 0;

      if (vendorTotals.isNotEmpty && total > 0) {
        final topEntry = vendorTotals.entries.reduce(
          (a, b) => a.value > b.value ? a : b,
        );
        topVendorName = topEntry.key;
        topVendorTotal = topEntry.value;
        topVendorPercent = (topVendorTotal / total) * 100;
      }

      if (!mounted) return;
      setState(() {
        _selectedQuickStats = QuickStats(
          currentTotal: total,
          receiptsCount: receipts.length,
          averageSpend: avg,
          lastMonthTotal: 0,
          dailyAverage: dailyPace,
        );
        _selectedTopVendor = TopVendorInsight(
          name: topVendorName,
          total: topVendorTotal,
          percent: topVendorPercent,
        );
      });
      return;
    }

    // For monthly/yearly, use the service
    try {
      final summary = await service.summaryForPeriod(period, granularity);
      if (!mounted) return;

      final selectionStillActive =
          _selectedPeriodStart == period && _selectedGranularity == granularity;
      if (!selectionStillActive) return;

      setState(() {
        _selectedQuickStats = summary.stats;
        _selectedTopVendor = summary.topVendor;
      });
    } catch (e) {
      print('Error fetching period summary: $e');
    }
  }

  Future<void> _loadCategoryBreakdown(
    DateTime period,
    SummaryGranularity granularity,
  ) async {
    final service = _summaryService;
    if (service == null) return;

    try {
      // For weekly granularity, calculate category breakdown manually
      if (granularity == SummaryGranularity.weekly) {
        final breakdown = await _calculateWeeklyCategoryBreakdown(period);
        if (!mounted) return;
        setState(() {
          _categoryBreakdown = breakdown;
        });
        return;
      }

      // For monthly/yearly, use the service
      final breakdown = await service.getCategoryBreakdown(period, granularity);
      if (!mounted) return;

      setState(() {
        _categoryBreakdown = breakdown;
      });
    } catch (e) {
      print('Error loading category breakdown: $e');
    }
  }

  Future<List<CategoryBreakdown>> _calculateWeeklyCategoryBreakdown(
    DateTime period,
  ) async {
    final isar = _isar;
    if (isar == null) return [];

    final windowEnd = _weeklyWindowEnd(period);
    final allReceipts = await isar.receiptEntitys.where().findAll();

    // Filter receipts for this 5-day window
    final receipts = allReceipts.where((receipt) {
      return _isDateInRange(receipt.date, period, windowEnd);
    }).toList();

    if (receipts.isEmpty) return [];

    // Group by category
    final categoryTotals = <String, double>{};
    final categoryCounts = <String, int>{};

    for (final receipt in receipts) {
      final category = receipt.category?.trim() ?? 'Uncategorized';
      categoryTotals[category] = (categoryTotals[category] ?? 0) + receipt.total;
      categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
    }

    // Calculate total for percentages
    final totalSpending =
        categoryTotals.values.fold<double>(0, (sum, val) => sum + val);

    // Convert to CategoryBreakdown list
    final breakdown = categoryTotals.entries.map((entry) {
      final percentage =
          totalSpending > 0 ? (entry.value / totalSpending) * 100 : 0.0;
      return CategoryBreakdown(
        categoryName: entry.key,
        total: entry.value,
        receiptCount: categoryCounts[entry.key] ?? 0,
        percentage: percentage,
      );
    }).toList();

    // Sort by total (highest first)
    breakdown.sort((a, b) => b.total.compareTo(a.total));

    return breakdown;
  }

  Future<void> _selectCategory(String? category) async {
    final service = _summaryService;
    final periodStart = _selectedPeriodStart;
    if (service == null) return;

    setState(() {
      _selectedCategory = category;
    });

    // If no period selected, use current month/year based on granularity
    final DateTime period;
    if (periodStart != null) {
      period = periodStart;
    } else {
      final root = _selectedMonthRoot ?? DateTime.now();
      if (_selectedGranularity == SummaryGranularity.yearly) {
        period = DateTime(root.year);
      } else {
        period = DateTime(root.year, root.month);
      }
    }

    // Reload weekly points with category filter if in weekly mode
    if (_selectedGranularity == SummaryGranularity.weekly) {
      final newPoints =
          await _generateFiveDayWeeklyPoints(_selectedMonthRoot ?? DateTime.now());
      if (!mounted) return;
      setState(() {
        _customWeeklyPoints = newPoints;
      });
    }

    if (category == null) {
      // Reset to default stats
      if (_selectedGranularity == SummaryGranularity.weekly &&
          periodStart != null) {
        await _recalculateWeeklyStats(periodStart, null);
      } else {
        final summary =
            await service.summaryForPeriod(period, _selectedGranularity);
        if (!mounted) return;
        setState(() {
          _selectedQuickStats = summary.stats;
          _selectedTopVendor = summary.topVendor;
        });
      }
      return;
    }

    // Load stats filtered by category
    try {
      // For weekly granularity, calculate manually
      if (_selectedGranularity == SummaryGranularity.weekly &&
          periodStart != null) {
        await _recalculateWeeklyStats(periodStart, category);
        return;
      }

      // For monthly/yearly, use the service
      final stats =
          await service.getStatsForCategory(period, _selectedGranularity, category);
      final topVendor =
          await service.getTopVendorForCategory(period, _selectedGranularity, category);

      if (!mounted) return;
      setState(() {
        _selectedQuickStats = stats;
        _selectedTopVendor = topVendor;
      });
    } catch (e) {
      print('Error loading category stats: $e');
    }
  }

  Future<void> _recalculateWeeklyStats(DateTime period, String? category) async {
    final isar = _isar;
    if (isar == null) return;

    final windowEnd = _weeklyWindowEnd(period);
    final allReceipts = await isar.receiptEntitys.where().findAll();

    final receipts = allReceipts.where((receipt) {
      final inRange = _isDateInRange(receipt.date, period, windowEnd);

      // Apply category filter if provided
      final categoryMatch = category == null || receipt.category == category;

      return inRange && categoryMatch;
    }).toList();

    final total = receipts.fold<double>(0, (sum, r) => sum + r.total);
    final avg = receipts.isEmpty ? 0.0 : total / receipts.length;

    final daysDiff = windowEnd.difference(period).inDays;
    final numDays = daysDiff > 0 ? daysDiff : 1;
    final dailyPace = total / numDays;

    // Calculate top vendor (filtered by category if applicable)
    final vendorTotals = <String, double>{};
    for (final receipt in receipts) {
      final vendor = receipt.merchant?.trim() ?? '';
      if (vendor.isNotEmpty) {
        vendorTotals[vendor] = (vendorTotals[vendor] ?? 0) + receipt.total;
      }
    }

    String topVendorName = '';
    double topVendorTotal = 0;
    double topVendorPercent = 0;

    if (vendorTotals.isNotEmpty && total > 0) {
      final topEntry = vendorTotals.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );
      topVendorName = topEntry.key;
      topVendorTotal = topEntry.value;
      topVendorPercent = (topVendorTotal / total) * 100;
    }

    if (!mounted) return;
    setState(() {
      _selectedQuickStats = QuickStats(
        currentTotal: total,
        receiptsCount: receipts.length,
        averageSpend: avg,
        lastMonthTotal: 0,
        dailyAverage: dailyPace,
      );
      _selectedTopVendor = TopVendorInsight(
        name: topVendorName,
        total: topVendorTotal,
        percent: topVendorPercent,
      );
    });
  }

  String _chartLabelFor(DateTime period) {
    switch (_selectedGranularity) {
      case SummaryGranularity.monthly:
        return DateFormat.MMM().format(period);
      case SummaryGranularity.yearly:
        return DateFormat.y().format(period);
      case SummaryGranularity.weekly:
        return _weeklyRangeLabel(period);
    }
  }

  String _tooltipLabelFor(DateTime period) {
    switch (_selectedGranularity) {
      case SummaryGranularity.monthly:
        return DateFormat.yMMMM().format(period);
      case SummaryGranularity.yearly:
        return DateFormat.y().format(period);
      case SummaryGranularity.weekly:
        return _weeklyRangeLabel(period, multiline: true);
    }
  }

  Widget _buildWeeklyMonthNavigator() {
    final month = DateFormat.yMMMM().format(_selectedMonthRoot!);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedMonthRoot = DateTime(
                  _selectedMonthRoot!.year,
                  _selectedMonthRoot!.month - 1,
                );
                _selectedPeriodStart = null;
                _selectedQuickStats = null;
                _selectedTopVendor = null;
                _selectedCategory = null;
                _categoryBreakdown = null;
                _customWeeklyPoints = null;
              });
            },
            child: const Icon(Icons.arrow_left, size: 32),
          ),
          const SizedBox(width: 12),
          Text(
            month,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () {
              final now = DateTime.now();
              final thisMonth = DateTime(now.year, now.month);

              final nextMonth = DateTime(
                _selectedMonthRoot!.year,
                _selectedMonthRoot!.month + 1,
              );

              if (nextMonth.isAfter(thisMonth)) return;

              setState(() {
                _selectedMonthRoot = nextMonth;
                _selectedPeriodStart = null;
                _selectedQuickStats = null;
                _selectedTopVendor = null;
                _selectedCategory = null;
                _categoryBreakdown = null;
                _customWeeklyPoints = null;
              });
            },
            child: Icon(
              Icons.arrow_right,
              size: 32,
              color: Colors.black.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- CATEGORY BREAKDOWN SECTION ----------------

  Widget _buildCategoryBreakdownSection() {
    final breakdown = _categoryBreakdown;

    if (breakdown == null || breakdown.isEmpty) {
      return const SizedBox.shrink();
    }

    return _AnalyticsSectionCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Category Breakdown',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              Icon(
                Icons.pie_chart_rounded,
                color: const Color(0xFF2563EB).withOpacity(0.8),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildCategoryPieChart(breakdown),
          const SizedBox(height: 12),
          const Text(
            'Tap a slice to filter by category',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPieChart(List<CategoryBreakdown> breakdown) {
    final colors = [
      const Color(0xFF0EA5E9),
      const Color(0xFF2563EB),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFFF59E0B),
      const Color(0xFF10B981),
      const Color(0xFFEF4444),
      const Color(0xFF6366F1),
    ];

    final sections = breakdown.asMap().entries.map((entry) {
      final index = entry.key;
      final cat = entry.value;
      final isSelected = _selectedCategory == cat.categoryName;

      return PieChartSectionData(
        value: cat.total,
        radius: isSelected ? 75 : 65,
        title: '${cat.percentage.toStringAsFixed(0)}%',
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        color: colors[index % colors.length],
        borderSide: BorderSide(
          color: Colors.white,
          width: isSelected ? 3 : 2,
        ),
      );
    }).toList();

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              sectionsSpace: 4,
              centerSpaceRadius: 0,
              startDegreeOffset: -90,
              borderData: FlBorderData(show: false),
              pieTouchData: PieTouchData(
                enabled: true,
                touchCallback: (FlTouchEvent event, pieTouchResponse) {
                  if (event is! FlTapUpEvent) return;
                  final section = pieTouchResponse?.touchedSection;
                  if (section == null) return;
                  final index = section.touchedSectionIndex;
                  if (index < 0 || index >= breakdown.length) return;

                  final selectedCat = breakdown[index].categoryName;
                  // Toggle: tap same category to deselect
                  if (_selectedCategory == selectedCat) {
                    _selectCategory(null);
                  } else {
                    _selectCategory(selectedCat);
                  }
                },
              ),
              sections: sections,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: breakdown.asMap().entries.map((entry) {
            final index = entry.key;
            final cat = entry.value;
            final color = colors[index % colors.length];
            final isSelected = _selectedCategory == cat.categoryName;

            return GestureDetector(
              onTap: () {
                if (_selectedCategory == cat.categoryName) {
                  _selectCategory(null);
                } else {
                  _selectCategory(cat.categoryName);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? color : color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: color,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      cat.categoryName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : color,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _currency.format(cat.total),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? Colors.white70 : color.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ---------------- QUICK STATS ----------------

  Widget _buildQuickStats(QuickStats stats) {
    return _AnalyticsSectionCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _selectedCategory == null
                ? 'Quick Stats'
                : 'Quick Stats - $_selectedCategory',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          _MetricsDonut(stats: stats, currency: _currency),
        ],
      ),
    );
  }

  String _heroLabelFor(
    DateTime periodStart,
    SummaryGranularity granularity,
  ) {
    switch (granularity) {
      case SummaryGranularity.monthly:
        return DateFormat.yMMMM().format(periodStart);
      case SummaryGranularity.weekly:
        return _weeklyRangeLabel(periodStart);
      case SummaryGranularity.yearly:
        return DateFormat.y().format(periodStart);
    }
  }

  // ---------------- TOP VENDOR ----------------

  Widget _buildTopVendorCard(TopVendorInsight top) {
    final percentValue = top.percent.isNaN ? 0 : top.percent.clamp(0, 100);
    final bool hasData = top.name.isNotEmpty && top.total > 0;
    final trimmed = top.name.trim();
    final String initials =
        hasData && trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';

    return _AnalyticsSectionCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _selectedCategory == null
                    ? 'Top Vendor'
                    : 'Top Vendor - $_selectedCategory',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              Text(
                hasData ? _currency.format(top.total) : '—',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFE0F2FE),
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0369A1),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasData ? top.name : 'We need more data',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasData ? 'Share of spend' : 'Log a few more receipts',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _GradientProgressBar(value: percentValue / 100),
          const SizedBox(height: 6),
          Text(
            hasData
                ? '${percentValue.toStringAsFixed(0)}% of this period'
                : 'Waiting for merchant activity',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- SMALL WIDGETS ----------------

class _MetricsDonut extends StatelessWidget {
  const _MetricsDonut({required this.stats, required this.currency});

  final QuickStats stats;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final slices = <_MetricSlice>[
      _MetricSlice(
        label: 'Daily pace',
        valueLabel: '${currency.format(stats.dailyAverage ?? 0)}/day',
        rawValue: stats.dailyAverage ?? 0,
        colors: const [
          Color.fromARGB(255, 16, 128, 202),
          Color.fromARGB(255, 50, 126, 227)
        ],
        radius: 64,
      ),
      _MetricSlice(
        label: 'Receipts logged',
        valueLabel: '${stats.receiptsCount}',
        rawValue: stats.receiptsCount.toDouble(),
        colors: const [Color(0xFF2563EB), Color(0xFF38BDF8)],
        radius: 56,
      ),
      _MetricSlice(
        label: 'Average spend',
        valueLabel: currency.format(stats.averageSpend),
        rawValue: stats.averageSpend,
        colors: const [Color(0xFF0EA5E9), Color(0xFF60A5FA)],
        radius: 50,
      ),
    ];

    final hasData = slices.any((s) => s.rawValue > 0);
    final sections = hasData
        ? slices
            .map(
              (slice) => PieChartSectionData(
                value: slice.rawValue <= 0 ? 0.01 : slice.rawValue,
                radius: slice.radius,
                showTitle: false,
                gradient: LinearGradient(
                  colors: slice.colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderSide: const BorderSide(color: Colors.white, width: 2),
              ),
            )
            .toList(growable: false)
        : [
            PieChartSectionData(
              value: 1,
              color: const Color(0xFFE2E8F0),
              showTitle: false,
              radius: 58,
            ),
          ];

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 6,
                  centerSpaceRadius: 58,
                  startDegreeOffset: -90,
                  borderData: FlBorderData(show: false),
                  sections: sections,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasData ? 'Metric split' : 'No spend yet',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF475569),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (hasData) ...[
                    const SizedBox(height: 4),
                    Text(
                      currency.format(stats.currentTotal),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Column(
          children: slices
              .map((slice) => _MetricLegendEntry(slice: slice))
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _MetricSlice {
  const _MetricSlice({
    required this.label,
    required this.valueLabel,
    required this.rawValue,
    required this.colors,
    required this.radius,
  });

  final String label;
  final String valueLabel;
  final double rawValue;
  final List<Color> colors;
  final double radius;
}

class _MetricLegendEntry extends StatelessWidget {
  const _MetricLegendEntry({required this.slice});

  final _MetricSlice slice;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: slice.colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x220256EB),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slice.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  slice.valueLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientProgressBar extends StatelessWidget {
  final double value;
  const _GradientProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final fill = (w * value).clamp(0.0, w);
        return SizedBox(
          height: 8,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Container(
                width: fill,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1D4ED8), Color(0xFF60A5FA)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AnalyticsSectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color background;
  const _AnalyticsSectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.background = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 25,
            offset: Offset(0, 12),
            spreadRadius: -8,
          ),
        ],
      ),
      child: child,
    );
  }
}