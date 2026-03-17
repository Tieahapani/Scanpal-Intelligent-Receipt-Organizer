import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'services/analytics_service.dart';
import 'services/report_service.dart';
import 'receipt.dart';

enum TimePeriod { weekly, monthly, yearly }

const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsFull = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const _categoryColors = <String, Color>{
  'Ground Transportation': Color(0xFF46166B),
  'Meals': Color(0xFFE8A824),
  'Accommodation Cost': Color(0xFF7B3FA0),
  'Registration Cost': Color(0xFFD49B1F),
  'Flight Cost': Color(0xFF1565C0),
  'Other AS Cost': Color(0xFFB08D3A),
};

const _categoryLabels = <String, String>{
  'Ground Transportation': 'Transportation',
  'Meals': 'Meals',
  'Accommodation Cost': 'Accommodation',
  'Registration Cost': 'Registration',
  'Flight Cost': 'Flight',
  'Other AS Cost': 'Other AS Cost',
};

class AnalyticsPage extends StatefulWidget {
  final AnalyticsService? analyticsService;
  final VoidCallback? onTripTap;
  final VoidCallback? onBack;
  const AnalyticsPage({super.key, this.analyticsService, this.onTripTap, this.onBack});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final _currency = NumberFormat.simpleCurrency();
  TimePeriod _activeTab = TimePeriod.monthly;

  // Current selections
  late int _monthlyMonth; // 0-indexed
  late int _monthlyYear;
  late int _yearlyYear;
  late int _weeklyMonth; // 0-indexed
  late int _weeklyYear;
  late int _weeklyWeekIndex;

  // Picker state
  bool _showPicker = false;
  late int _pickerYear;
  int _weeklyPickerStep = 1;
  late int _weeklyPickerMonth;
  late int _weeklyPickerYear;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _monthlyMonth = now.month - 1; // 0-indexed
    _monthlyYear = now.year;
    _yearlyYear = now.year;
    _weeklyMonth = now.month - 1;
    _weeklyYear = now.year;
    _pickerYear = now.year;
    _weeklyPickerMonth = now.month - 1;
    _weeklyPickerYear = now.year;

    final weeks = _getWeeksInMonth(_weeklyMonth, _weeklyYear);
    _weeklyWeekIndex = 0;
    for (int i = 0; i < weeks.length; i++) {
      if (_isCurrentWeek(weeks[i]['start'] as DateTime)) {
        _weeklyWeekIndex = i;
        break;
      }
    }
  }

  AnalyticsService? get _analytics => widget.analyticsService;
  bool _downloading = false;

  /// Compute the date range for the currently selected period.
  (DateTime, DateTime) get _dateRange {
    switch (_activeTab) {
      case TimePeriod.monthly:
        final start = DateTime(_monthlyYear, _monthlyMonth + 1, 1);
        final end = DateTime(_monthlyYear, _monthlyMonth + 2, 1);
        return (start, end);
      case TimePeriod.yearly:
        return (DateTime(_yearlyYear, 1, 1), DateTime(_yearlyYear + 1, 1, 1));
      case TimePeriod.weekly:
        final w = _weeks;
        if (w.isEmpty) return (DateTime.now(), DateTime.now());
        final ws = w[_safeWeekIndex]['start'] as DateTime;
        final start = DateTime(ws.year, ws.month, ws.day);
        return (start, start.add(const Duration(days: 7)));
    }
  }

  Future<void> _downloadReport() async {
    if (_downloading || _analytics == null) return;
    setState(() => _downloading = true);
    try {
      final data = _data;
      final periodType = switch (_activeTab) {
        TimePeriod.monthly => 'Monthly',
        TimePeriod.weekly => 'Weekly',
        TimePeriod.yearly => 'Yearly',
      };
      final (start, end) = _dateRange;
      // Filter receipts to the selected period
      final periodReceipts = _analytics!.receipts.where((r) {
        if (r.date == null) return false;
        final d = DateTime(r.date!.year, r.date!.month, r.date!.day);
        return !d.isBefore(start) && d.isBefore(end);
      }).toList();
      // Filter trips that overlap with the period
      final periodTrips = _analytics!.trips.where((t) {
        if (t.departureDate == null) return false;
        final depDay = DateTime(t.departureDate!.year, t.departureDate!.month, t.departureDate!.day);
        final retDay = t.returnDate != null
            ? DateTime(t.returnDate!.year, t.returnDate!.month, t.returnDate!.day)
            : depDay;
        return depDay.isBefore(end) && !retDay.isBefore(start);
      }).toList();

      await ReportService.generateAndShare(
        data: data,
        receipts: periodReceipts,
        trips: periodTrips,
        periodLabel: _label,
        periodType: periodType,
      );
    } catch (e) {
      debugPrint('Report error: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  // ─── Week helpers ──────────────────────────────────────

  List<Map<String, dynamic>> _getWeeksInMonth(int month, int year) {
    final weeks = <Map<String, dynamic>>[];
    final firstDay = DateTime(year, month + 1, 1);
    var weekStart = firstDay.subtract(Duration(days: firstDay.weekday % 7));
    final lastDay = DateTime(year, month + 2, 0);

    while (!weekStart.isAfter(lastDay)) {
      final weekEnd = weekStart.add(const Duration(days: 6));
      final sm = _monthsShort[weekStart.month - 1];
      final em = _monthsShort[weekEnd.month - 1];
      final label = sm == em
          ? '$sm ${weekStart.day} - ${weekEnd.day}'
          : '$sm ${weekStart.day} - $em ${weekEnd.day}';
      weeks.add({'start': weekStart, 'end': weekEnd, 'label': label});
      weekStart = weekStart.add(const Duration(days: 7));
    }
    return weeks;
  }

  bool _isCurrentWeek(DateTime weekStart) {
    final now = DateTime.now();
    final thisSunday = now.subtract(Duration(days: now.weekday % 7));
    final s = DateTime(thisSunday.year, thisSunday.month, thisSunday.day);
    final ws = DateTime(weekStart.year, weekStart.month, weekStart.day);
    return s == ws;
  }

  bool _isFutureWeek(DateTime weekStart) {
    final now = DateTime.now();
    final thisSunday = now.subtract(Duration(days: now.weekday % 7));
    final s = DateTime(thisSunday.year, thisSunday.month, thisSunday.day);
    final ws = DateTime(weekStart.year, weekStart.month, weekStart.day);
    return ws.isAfter(s);
  }

  // ─── Derived data ──────────────────────────────────────

  List<Map<String, dynamic>> get _weeks => _getWeeksInMonth(_weeklyMonth, _weeklyYear);

  int get _safeWeekIndex {
    final w = _weeks;
    return _weeklyWeekIndex.clamp(0, w.isEmpty ? 0 : w.length - 1);
  }

  PeriodSnapshot get _data {
    final a = _analytics;
    if (a == null) return PeriodSnapshot.empty;
    switch (_activeTab) {
      case TimePeriod.monthly:
        return a.monthlySnapshot(_monthlyMonth, _monthlyYear);
      case TimePeriod.yearly:
        return a.yearlySnapshot(_yearlyYear);
      case TimePeriod.weekly:
        final w = _weeks;
        if (w.isEmpty) return PeriodSnapshot.empty;
        return a.weeklySnapshot(w[_safeWeekIndex]['start'] as DateTime);
    }
  }

  String get _label {
    switch (_activeTab) {
      case TimePeriod.monthly:
        return '${_monthsFull[_monthlyMonth]} $_monthlyYear';
      case TimePeriod.yearly:
        return '$_yearlyYear';
      case TimePeriod.weekly:
        final w = _weeks;
        if (w.isEmpty) return '';
        final week = w[_safeWeekIndex];
        return '${week['label']}, ${(week['start'] as DateTime).year}';
    }
  }

  bool get _isCurrent {
    final now = DateTime.now();
    switch (_activeTab) {
      case TimePeriod.monthly:
        return _monthlyMonth == now.month - 1 && _monthlyYear == now.year;
      case TimePeriod.yearly:
        return _yearlyYear == now.year;
      case TimePeriod.weekly:
        final w = _weeks;
        if (w.isEmpty) return false;
        return _isCurrentWeek(w[_safeWeekIndex]['start'] as DateTime);
    }
  }

  bool get _canGoBack {
    switch (_activeTab) {
      case TimePeriod.monthly:
        return !(_monthlyMonth == 0 && _monthlyYear == 2024);
      case TimePeriod.yearly:
        return _yearlyYear > 2024;
      case TimePeriod.weekly:
        return !(_weeklyMonth == 0 && _weeklyYear == 2024 && _safeWeekIndex == 0);
    }
  }

  bool get _canGoForward {
    final now = DateTime.now();
    switch (_activeTab) {
      case TimePeriod.monthly:
        return !(_monthlyMonth == now.month - 1 && _monthlyYear == now.year);
      case TimePeriod.yearly:
        return _yearlyYear < now.year;
      case TimePeriod.weekly:
        final w = _weeks;
        if (w.isEmpty) return false;
        final ws = w[_safeWeekIndex]['start'] as DateTime;
        return !_isCurrentWeek(ws) && !_isFutureWeek(ws);
    }
  }

  void _goBack() {
    setState(() {
      switch (_activeTab) {
        case TimePeriod.monthly:
          if (_monthlyMonth == 0) {
            _monthlyMonth = 11;
            _monthlyYear--;
          } else {
            _monthlyMonth--;
          }
        case TimePeriod.yearly:
          _yearlyYear--;
        case TimePeriod.weekly:
          if (_weeklyWeekIndex > 0) {
            _weeklyWeekIndex--;
          } else {
            final newMonth = _weeklyMonth == 0 ? 11 : _weeklyMonth - 1;
            final newYear = _weeklyMonth == 0 ? _weeklyYear - 1 : _weeklyYear;
            final prevWeeks = _getWeeksInMonth(newMonth, newYear);
            _weeklyMonth = newMonth;
            _weeklyYear = newYear;
            _weeklyWeekIndex = prevWeeks.length - 1;
          }
      }
    });
  }

  void _goForward() {
    setState(() {
      switch (_activeTab) {
        case TimePeriod.monthly:
          if (_monthlyMonth == 11) {
            _monthlyMonth = 0;
            _monthlyYear++;
          } else {
            _monthlyMonth++;
          }
        case TimePeriod.yearly:
          _yearlyYear++;
        case TimePeriod.weekly:
          final ws = _getWeeksInMonth(_weeklyMonth, _weeklyYear);
          if (_weeklyWeekIndex < ws.length - 1) {
            _weeklyWeekIndex++;
          } else {
            final newMonth = _weeklyMonth == 11 ? 0 : _weeklyMonth + 1;
            final newYear = _weeklyMonth == 11 ? _weeklyYear + 1 : _weeklyYear;
            _weeklyMonth = newMonth;
            _weeklyYear = newYear;
            _weeklyWeekIndex = 0;
          }
      }
    });
  }

  // ─── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_analytics == null) {
      return const Center(child: Text('No data available'));
    }

    final data = _data;

    return Stack(
      children: [
        Column(
          children: [
            // Header
            _buildHeader(),
            // Date navigator
            _buildDateNavigator(),
            // Scrollable content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _buildTotalSpendingCard(data),
                  _buildPaymentMethodSplit(data),
                  _buildCategoryBreakdown(data),
                  _buildDownloadReport(),
                ],
              ),
            ),
          ],
        ),
        if (_showPicker) _buildPickerOverlay(),
      ],
    );
  }

  // ─── Header ────────────────────────────────────────────

  Widget _buildHeader() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(20, topPadding + 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back, size: 16, color: Color(0xFF4B5563)),
                ),
              ),
              const Expanded(
                child: Column(
                  children: [
                    Text(
                      'Analytics',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                    ),
                    Text(
                      'Spending Overview',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
            ],
          ),
          const SizedBox(height: 14),
          // Period tabs
          Row(
            children: TimePeriod.values.map((tab) {
              final selected = _activeTab == tab;
              final label = switch (tab) {
                TimePeriod.weekly => 'Weekly',
                TimePeriod.monthly => 'Monthly',
                TimePeriod.yearly => 'Yearly',
              };
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _activeTab = tab),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF46166B) : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: selected
                          ? [BoxShadow(color: const Color(0xFF46166B).withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 2))]
                          : null,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ─── Date Navigator ────────────────────────────────────

  Widget _buildDateNavigator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          // Back arrow
          GestureDetector(
            onTap: _canGoBack ? _goBack : null,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _canGoBack ? const Color(0xFFF3F4F6) : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chevron_left,
                size: 16,
                color: _canGoBack ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB),
              ),
            ),
          ),
          // Center label
          Expanded(
            child: GestureDetector(
              onTap: _openPicker,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today, size: 14, color: Color(0xFF46166B)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _label,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_isCurrent) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF46166B).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'NOW',
                            style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Color(0xFF46166B), letterSpacing: 0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to select ${_activeTab == TimePeriod.weekly ? 'week' : _activeTab == TimePeriod.monthly ? 'month' : 'year'}',
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Color(0xFF46166B)),
                  ),
                ],
              ),
            ),
          ),
          // Forward arrow
          GestureDetector(
            onTap: _canGoForward ? _goForward : null,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _canGoForward ? const Color(0xFFF3F4F6) : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chevron_right,
                size: 16,
                color: _canGoForward ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Total Spending Card ───────────────────────────────

  Widget _buildTotalSpendingCard(PeriodSnapshot data) {
    final isPositive = data.change > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFDF6E3), Color(0xFFFBF0D1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8A824).withValues(alpha: 0.2)),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            // Top gradient line
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                height: 3,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF46166B), Color(0xFFE8A824), Color(0xFF46166B)]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TOTAL SPENDING',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF9A7A2E), letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _currency.format(data.total),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF111827), height: 1.2),
                  ),
                  const SizedBox(height: 8),
                  if (data.changeLabel.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isPositive
                              ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                              : const Color(0xFF10B981).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPositive ? Icons.trending_up : Icons.trending_down,
                              size: 10,
                              color: isPositive ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              data.changeLabel,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: isPositive ? const Color(0xFFDC2626) : const Color(0xFF059669),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      const Icon(Icons.description_outlined, size: 12, color: Color(0xFFB08D3A)),
                      const SizedBox(width: 4),
                      Text(
                        '${data.receipts} receipts',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF9A7A2E)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Payment Method Split ──────────────────────────────

  Widget _buildPaymentMethodSplit(PeriodSnapshot data) {
    final totalPayment = data.personalTotal + data.amexTotal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: _paymentCard(
              'Personal',
              data.personalTotal,
              totalPayment,
              const Color(0xFFE8A824),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _paymentCard(
              'AS Amex',
              data.amexTotal,
              totalPayment,
              const Color(0xFF46166B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentCard(String label, double amount, double total, Color color) {
    final pct = total > 0 ? (amount / total * 100).round() : 0;
    final fraction = total > 0 ? amount / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF9CA3AF))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _currency.format(amount),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111827), height: 1),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fraction),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (_, value, __) => LinearProgressIndicator(
                value: value,
                backgroundColor: const Color(0xFFF3F4F6),
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('$pct% of total', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }

  // ─── Category Breakdown ────────────────────────────────

  Widget _buildCategoryBreakdown(PeriodSnapshot data) {
    final categories = data.categories;
    final maxCatValue = categories.isEmpty ? 0.0 : categories.map((c) => c.amount).reduce((a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BY CATEGORY',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF), letterSpacing: 1),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF3F4F6)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
            ),
            child: Column(
              children: [
                // Donut chart
                if (categories.isNotEmpty)
                  SizedBox(
                    height: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            sectionsSpace: 3,
                            centerSpaceRadius: 44,
                            sections: categories.map((cat) {
                              final color = _categoryColors[cat.name] ?? const Color(0xFFB08D3A);
                              return PieChartSectionData(
                                color: color,
                                value: cat.amount,
                                title: '',
                                radius: 24,
                              );
                            }).toList(),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Total', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Color(0xFF9CA3AF))),
                            Text(
                              _currency.format(data.total),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox(
                    height: 160,
                    child: Center(child: Text('No expenses', style: TextStyle(color: Color(0xFF9CA3AF)))),
                  ),
                const SizedBox(height: 16),
                // Category bars
                ...categories.map((cat) {
                  final color = _categoryColors[cat.name] ?? const Color(0xFFB08D3A);
                  final label = _categoryLabels[cat.name] ?? cat.name;
                  final fraction = maxCatValue > 0 ? cat.amount / maxCatValue : 0.0;
                  final pct = data.total > 0 ? (cat.amount / data.total * 100).round() : 0;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10, height: 10,
                              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF4B5563))),
                            ),
                            Text(
                              _currency.format(cat.amount),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$pct%',
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Color(0xFF9CA3AF)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: fraction),
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutCubic,
                            builder: (_, value, __) => LinearProgressIndicator(
                              value: value,
                              backgroundColor: const Color(0xFFF3F4F6),
                              valueColor: AlwaysStoppedAnimation(color),
                              minHeight: 6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Download Report ───────────────────────────────────

  Widget _buildDownloadReport() {
    final periodLabel = switch (_activeTab) {
      TimePeriod.monthly => 'Monthly',
      TimePeriod.weekly => 'Weekly',
      TimePeriod.yearly => 'Yearly',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GestureDetector(
        onTap: _downloadReport,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFDF6E3), Color(0xFFFBF0D1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8A824).withValues(alpha: 0.2)),
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  height: 2,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFF46166B), Color(0xFFE8A824), Color(0xFF46166B)]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _downloading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF9A7A2E)))
                        : const Icon(Icons.download_rounded, size: 16, color: Color(0xFF9A7A2E)),
                    const SizedBox(width: 8),
                    Text(
                      _downloading ? 'Generating...' : 'Download $periodLabel Report',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF9A7A2E)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Picker ────────────────────────────────────────────

  void _openPicker() {
    setState(() {
      if (_activeTab == TimePeriod.monthly) {
        _pickerYear = _monthlyYear;
      } else if (_activeTab == TimePeriod.weekly) {
        _weeklyPickerStep = 1;
        _weeklyPickerYear = _weeklyYear;
        _weeklyPickerMonth = _weeklyMonth;
      }
      _showPicker = true;
    });
  }

  Widget _buildPickerOverlay() {
    return Stack(
      children: [
        // Backdrop
        GestureDetector(
          onTap: () => setState(() => _showPicker = false),
          child: Container(color: Colors.black.withValues(alpha: 0.4)),
        ),
        // Sheet
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 30, offset: Offset(0, -8))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                const Padding(
                  padding: EdgeInsets.only(top: 12, bottom: 4),
                  child: Center(
                    child: SizedBox(width: 40, height: 4, child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFFE5E7EB), borderRadius: BorderRadius.all(Radius.circular(2))))),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _pickerTitle,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _showPicker = false),
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(color: const Color(0xFFF3F4F6), shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF)),
                        ),
                      ),
                    ],
                  ),
                ),
                // Content
                _buildPickerContent(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String get _pickerTitle {
    switch (_activeTab) {
      case TimePeriod.monthly:
        return 'Select Month & Year';
      case TimePeriod.yearly:
        return 'Select Year';
      case TimePeriod.weekly:
        return _weeklyPickerStep == 1 ? 'Select Month & Year' : 'Select Week';
    }
  }

  Widget _buildPickerContent() {
    switch (_activeTab) {
      case TimePeriod.monthly:
        return _buildMonthlyPicker();
      case TimePeriod.yearly:
        return _buildYearlyPicker();
      case TimePeriod.weekly:
        return _weeklyPickerStep == 1 ? _buildWeeklyStep1() : _buildWeeklyStep2();
    }
  }

  Widget _buildYearSelector(int year, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: year > 2024 ? () => onChanged(year - 1) : null,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: year > 2024 ? const Color(0xFFF3F4F6) : const Color(0xFFFAFAFA),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chevron_left, size: 16, color: year > 2024 ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB)),
            ),
          ),
          const SizedBox(width: 16),
          Text('$year', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: year < DateTime.now().year ? () => onChanged(year + 1) : null,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: year < DateTime.now().year ? const Color(0xFFF3F4F6) : const Color(0xFFFAFAFA),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chevron_right, size: 16, color: year < DateTime.now().year ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyPicker() {
    final now = DateTime.now();
    return Column(
      children: [
        _buildYearSelector(_pickerYear, (y) => setState(() => _pickerYear = y)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.2,
            children: List.generate(12, (i) {
              final isFuture = _pickerYear == now.year && i > now.month - 1;
              final isSelected = i == _monthlyMonth && _pickerYear == _monthlyYear;
              final isCur = i == now.month - 1 && _pickerYear == now.year;
              return GestureDetector(
                onTap: isFuture ? null : () {
                  setState(() {
                    _monthlyMonth = i;
                    _monthlyYear = _pickerYear;
                    _showPicker = false;
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isFuture
                        ? const Color(0xFFFAFAFA)
                        : isSelected
                            ? const Color(0xFF46166B)
                            : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        _monthsShort[i],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isFuture
                              ? const Color(0xFFD1D5DB)
                              : isSelected
                                  ? Colors.white
                                  : const Color(0xFF4B5563),
                        ),
                      ),
                      if (isCur && !isSelected)
                        Positioned(
                          bottom: 4,
                          child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF46166B), shape: BoxShape.circle)),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildYearlyPicker() {
    final now = DateTime.now();
    final years = [2024, 2025, 2026];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.5,
        children: years.map((y) {
          final isFuture = y > now.year;
          final isSelected = y == _yearlyYear;
          final isCur = y == now.year;
          return GestureDetector(
            onTap: isFuture ? null : () {
              setState(() {
                _yearlyYear = y;
                _showPicker = false;
              });
            },
            child: Container(
              decoration: BoxDecoration(
                color: isFuture
                    ? const Color(0xFFFAFAFA)
                    : isSelected
                        ? const Color(0xFF46166B)
                        : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    '$y',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isFuture
                          ? const Color(0xFFD1D5DB)
                          : isSelected ? Colors.white : const Color(0xFF4B5563),
                    ),
                  ),
                  if (isCur && !isSelected)
                    Positioned(
                      bottom: 6,
                      child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF46166B), shape: BoxShape.circle)),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildWeeklyStep1() {
    final now = DateTime.now();
    return Column(
      children: [
        _buildYearSelector(_weeklyPickerYear, (y) => setState(() => _weeklyPickerYear = y)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'Choose a month, then pick a week',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey.shade400),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.2,
            children: List.generate(12, (i) {
              final isFuture = _weeklyPickerYear == now.year && i > now.month - 1;
              final isSelectedMonth = i == _weeklyMonth && _weeklyPickerYear == _weeklyYear;
              final isCur = i == now.month - 1 && _weeklyPickerYear == now.year;
              return GestureDetector(
                onTap: isFuture ? null : () {
                  setState(() {
                    _weeklyPickerMonth = i;
                    _weeklyPickerStep = 2;
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isFuture
                        ? const Color(0xFFFAFAFA)
                        : isSelectedMonth
                            ? const Color(0xFF46166B).withValues(alpha: 0.1)
                            : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                    border: isSelectedMonth ? Border.all(color: const Color(0xFF46166B).withValues(alpha: 0.2)) : null,
                  ),
                  alignment: Alignment.center,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        _monthsShort[i],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelectedMonth ? FontWeight.w600 : FontWeight.w500,
                          color: isFuture
                              ? const Color(0xFFD1D5DB)
                              : isSelectedMonth
                                  ? const Color(0xFF46166B)
                                  : const Color(0xFF4B5563),
                        ),
                      ),
                      if (isCur && !isSelectedMonth)
                        Positioned(
                          bottom: 4,
                          child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF46166B), shape: BoxShape.circle)),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyStep2() {
    final pickerWeeks = _getWeeksInMonth(_weeklyPickerMonth, _weeklyPickerYear);
    return Column(
      children: [
        // Back + month label
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _weeklyPickerStep = 1),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(color: const Color(0xFFF3F4F6), shape: BoxShape.circle),
                  child: const Icon(Icons.chevron_left, size: 14, color: Color(0xFF6B7280)),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_monthsFull[_weeklyPickerMonth]} $_weeklyPickerYear',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4B5563)),
              ),
            ],
          ),
        ),
        // Week list
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            children: List.generate(pickerWeeks.length, (idx) {
              final week = pickerWeeks[idx];
              final ws = week['start'] as DateTime;
              final future = _isFutureWeek(ws);
              final isCur = _isCurrentWeek(ws);
              final isSelected = _weeklyMonth == _weeklyPickerMonth &&
                  _weeklyYear == _weeklyPickerYear &&
                  _safeWeekIndex == idx;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: future ? null : () {
                    setState(() {
                      _weeklyMonth = _weeklyPickerMonth;
                      _weeklyYear = _weeklyPickerYear;
                      _weeklyWeekIndex = idx;
                      _showPicker = false;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: future
                          ? const Color(0xFFFAFAFA)
                          : isSelected
                              ? const Color(0xFF46166B)
                              : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            week['label'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              color: future
                                  ? const Color(0xFFD1D5DB)
                                  : isSelected ? Colors.white : const Color(0xFF4B5563),
                            ),
                          ),
                        ),
                        if (isCur)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : const Color(0xFF46166B).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'CURRENT',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? Colors.white : const Color(0xFF46166B),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
