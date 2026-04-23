import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'services/analytics_service.dart';
import 'models/trip.dart';

enum TimePeriod { weekly, monthly, yearly }

const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsFull = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const _departmentColors = <String, Color>{
  'Project Rebound': Color(0xFF46166B),
  'Project Connect': Color(0xFF7B3FA0),
  'Productions': Color(0xFFE8A824),
  'Board of Directors': Color(0xFFD49B1F),
  'Marketing': Color(0xFFB08D3A),
  'Student Engagement': Color(0xFF9A7A2E),
};

const _fallbackDeptColors = [
  Color(0xFF46166B),
  Color(0xFFE8A824),
  Color(0xFF7B3FA0),
  Color(0xFFD49B1F),
  Color(0xFFA855F7),
  Color(0xFFB08D3A),
  Color(0xFF6D28D9),
  Color(0xFFC68A19),
];

const _categoryColors = <String, Color>{
  'Meals': Color(0xFFE8A824),
  'Accommodation Cost': Color(0xFF46166B),
  'Ground Transportation': Color(0xFF7B3FA0),
  'Registration Cost': Color(0xFFD49B1F),
  'Flight Cost': Color(0xFF1565C0),
  'Other AS Cost': Color(0xFFB08D3A),
};

const _categoryLabels = <String, String>{
  'Meals': 'Meals',
  'Accommodation Cost': 'Lodging',
  'Ground Transportation': 'Transportation',
  'Registration Cost': 'Registration',
  'Flight Cost': 'Flight',
  'Other AS Cost': 'Other',
};

Color _deptColor(String name, int index) {
  return _departmentColors[name] ?? _fallbackDeptColors[index % _fallbackDeptColors.length];
}

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

  // Department filter
  String? _selectedDepartment; // null = All Departments

  // Expanded department for category drill-down
  String? _expandedDept;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _monthlyMonth = now.month - 1;
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

  // ─── Department helpers ────────────────────────────────

  List<String> get _allDepartments {
    final a = _analytics;
    if (a == null) return [];
    final depts = <String>{};
    for (final t in a.trips) {
      if (t.department != null && t.department!.isNotEmpty) {
        depts.add(t.department!);
      }
    }
    final list = depts.toList()..sort();
    return list;
  }

  /// Check if a trip overlaps with a date range.
  bool _tripOverlapsPeriod(Trip t, DateTime start, DateTime end) {
    if (t.departureDate == null) return false;
    final depDay = DateTime(t.departureDate!.year, t.departureDate!.month, t.departureDate!.day);
    final retDay = t.returnDate != null
        ? DateTime(t.returnDate!.year, t.returnDate!.month, t.returnDate!.day)
        : depDay;
    // Trip overlaps period if it starts before period ends AND ends on/after period start
    return depDay.isBefore(end) && !retDay.isBefore(start);
  }

  /// Primary data source: trips (Notion expenses), not receipts.
  List<_DeptSpend> _departmentBreakdown(PeriodSnapshot data) {
    final a = _analytics;
    if (a == null) return [];

    final (start, end) = _dateRange;

    // Filter trips that overlap with the selected period
    final periodTrips = a.trips.where((t) => _tripOverlapsPeriod(t, start, end)).toList();

    // Count receipts per trip for supplementary info
    final receiptCountPerTrip = <String, int>{};
    for (final r in a.receipts) {
      if (r.tripId != null) {
        receiptCountPerTrip[r.tripId!] = (receiptCountPerTrip[r.tripId!] ?? 0) + 1;
      }
    }

    // Group by department
    final deptTotals = <String, double>{};
    final deptTripCounts = <String, int>{};
    final deptReceiptCounts = <String, int>{};
    final deptCategories = <String, Map<String, double>>{};

    for (final t in periodTrips) {
      final dept = (t.department != null && t.department!.isNotEmpty)
          ? t.department!
          : 'Unknown';

      deptTotals[dept] = (deptTotals[dept] ?? 0) + t.totalExpenses;
      deptTripCounts[dept] = (deptTripCounts[dept] ?? 0) + 1;
      deptReceiptCounts[dept] = (deptReceiptCounts[dept] ?? 0) +
          (receiptCountPerTrip[t.id.toString()] ?? 0);

      // Category breakdown from trip cost fields
      deptCategories.putIfAbsent(dept, () => {});
      final cats = deptCategories[dept]!;
      if (t.accommodationCost > 0) cats['Accommodation Cost'] = (cats['Accommodation Cost'] ?? 0) + t.accommodationCost;
      if (t.flightCost > 0) cats['Flight Cost'] = (cats['Flight Cost'] ?? 0) + t.flightCost;
      if (t.groundTransportation > 0) cats['Ground Transportation'] = (cats['Ground Transportation'] ?? 0) + t.groundTransportation;
      if (t.registrationCost > 0) cats['Registration Cost'] = (cats['Registration Cost'] ?? 0) + t.registrationCost;
      if (t.meals > 0) cats['Meals'] = (cats['Meals'] ?? 0) + t.meals;
      if (t.otherAsCost > 0) cats['Other AS Cost'] = (cats['Other AS Cost'] ?? 0) + t.otherAsCost;
    }

    final total = deptTotals.values.fold(0.0, (s, v) => s + v);
    final result = deptTotals.entries.map((e) => _DeptSpend(
      name: e.key,
      amount: e.value,
      percentage: total > 0 ? (e.value / total * 100) : 0,
      receiptCount: deptReceiptCounts[e.key] ?? 0,
      tripCount: deptTripCounts[e.key] ?? 0,
      categories: deptCategories[e.key] ?? {},
    )).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    return result;
  }

  // ─── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_analytics == null) {
      return const Center(child: Text('No data available'));
    }

    final data = _data;
    final allDepts = _departmentBreakdown(data);

    // Filter departments for the spending card based on dropdown selection
    final displayDepts = _selectedDepartment != null
        ? allDepts.where((d) => d.name == _selectedDepartment).toList()
        : allDepts;

    return Stack(
      children: [
        Column(
          children: [
            _buildHeader(),
            _buildDateNavigator(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (_expandedDept == null) ...[
                    _buildDepartmentDropdown(),
                    _buildTotalSpendingCardFromDepts(displayDepts),
                  ],
                  _buildDepartmentChart(allDepts),
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
                  decoration: const BoxDecoration(
                    color: Color(0xFFF3F4F6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back, size: 16, color: Color(0xFF4B5563)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Analytics',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                    ),
                    Text(
                      'Department Spending Overview',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
                  onTap: () => setState(() {
                    _activeTab = tab;
                    _expandedDept = null;
                  }),
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
          GestureDetector(
            onTap: _canGoBack ? _goBack : null,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: _canGoBack ? const Color(0xFFF3F4F6) : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chevron_left, size: 16,
                color: _canGoBack ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB)),
            ),
          ),
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
          GestureDetector(
            onTap: _canGoForward ? _goForward : null,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: _canGoForward ? const Color(0xFFF3F4F6) : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chevron_right, size: 16,
                color: _canGoForward ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Department Dropdown ──────────────────────────────

  Widget _buildDepartmentDropdown() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: GestureDetector(
        onTap: _showDepartmentPicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
          ),
          child: Row(
            children: [
              const Icon(Icons.business_outlined, size: 14, color: Color(0xFF46166B)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedDepartment ?? 'All Departments',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                ),
              ),
              Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  void _showDepartmentPicker() {
    final departments = _allDepartments;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 30, offset: Offset(0, -8))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(
                child: SizedBox(width: 40, height: 4,
                  child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFFE5E7EB), borderRadius: BorderRadius.all(Radius.circular(2))))),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Select Department',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: 32, height: 32,
                      decoration: const BoxDecoration(color: Color(0xFFF3F4F6), shape: BoxShape.circle),
                      child: const Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF)),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                shrinkWrap: true,
                children: [
                  _buildDeptPickerOption(ctx, null),
                  ...departments.map((d) => _buildDeptPickerOption(ctx, d)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeptPickerOption(BuildContext ctx, String? dept) {
    final isSelected = _selectedDepartment == dept;
    final label = dept ?? 'All Departments';
    final dotColor = dept != null
        ? _deptColor(dept, _allDepartments.indexOf(dept))
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedDepartment = dept;
            _expandedDept = null;
          });
          Navigator.pop(ctx);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF46166B) : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              if (dept != null)
                Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withValues(alpha: 0.5) : dotColor,
                    shape: BoxShape.circle,
                  ),
                )
              else
                Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        isSelected ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF46166B),
                        isSelected ? Colors.white.withValues(alpha: 0.5) : const Color(0xFFE8A824),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? Colors.white : const Color(0xFF374151),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Total Spending Card (trip-based) ───────────────────

  Widget _buildTotalSpendingCardFromDepts(List<_DeptSpend> depts) {
    final totalSpending = depts.fold(0.0, (s, d) => s + d.amount);
    final totalReceipts = depts.fold(0, (s, d) => s + d.receiptCount);
    final totalTrips = depts.fold(0, (s, d) => s + d.tripCount);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: _currency.format(totalSpending),
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF111827), height: 1),
                        ),
                        const TextSpan(
                          text: '.00',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Color(0xFF9CA3AF)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.description_outlined, size: 12, color: Color(0xFFB08D3A)),
                      const SizedBox(width: 4),
                      Text(
                        '$totalReceipts receipt${totalReceipts != 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF9A7A2E)),
                      ),
                      const SizedBox(width: 16),
                      const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFFB08D3A)),
                      const SizedBox(width: 4),
                      Text(
                        '$totalTrips trip${totalTrips != 1 ? 's' : ''}',
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

  // ─── Department Breakdown with Expandable Category ─────

  Widget _buildDepartmentChart(List<_DeptSpend> allDepts) {
    // When a department is selected from the dropdown, show only that one
    // Otherwise show all for donut, top 5 in the list
    final donutDepts = _selectedDepartment != null
        ? allDepts.where((d) => d.name == _selectedDepartment).toList()
        : allDepts;
    final listDepts = _selectedDepartment != null
        ? donutDepts
        : allDepts.take(5).toList();
    final allTotal = allDepts.fold(0.0, (s, d) => s + d.amount);
    final donutTotal = donutDepts.fold(0.0, (s, d) => s + d.amount);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'BY DEPARTMENT',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF), letterSpacing: 1),
              ),
              const Spacer(),
              Text('Tap to expand',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w400, color: Colors.grey.shade300)),
            ],
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
                if (donutDepts.isNotEmpty && donutTotal > 0)
                  SizedBox(
                    height: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            sectionsSpace: 3,
                            centerSpaceRadius: 52,
                            sections: List.generate(donutDepts.length, (i) {
                              final dept = donutDepts[i];
                              if (dept.amount <= 0) return null;
                              final color = _deptColor(dept.name, allDepts.indexOf(dept));
                              final isDimmed = _expandedDept != null && _expandedDept != dept.name;
                              return PieChartSectionData(
                                color: isDimmed ? color.withValues(alpha: 0.3) : color,
                                value: dept.amount,
                                title: '',
                                radius: 24,
                              );
                            }).whereType<PieChartSectionData>().toList(),
                          ),
                        ),
                        // Center label
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_expandedDept != null) ...[
                              SizedBox(
                                width: 90,
                                child: Text(
                                  _expandedDept!,
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Color(0xFF9CA3AF)),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                _currency.format(
                                  allDepts.where((d) => d.name == _expandedDept).firstOrNull?.amount ?? 0,
                                ),
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                              ),
                            ] else ...[
                              const Text('Total', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Color(0xFF9CA3AF))),
                              Text(
                                _currency.format(donutTotal),
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox(
                    height: 160,
                    child: Center(child: Text('No department data', style: TextStyle(color: Color(0xFF9CA3AF)))),
                  ),
                const SizedBox(height: 16),
                // Department rows (top 5 or filtered single)
                ...List.generate(listDepts.length, (i) {
                  final dept = listDepts[i];
                  if (dept.amount <= 0) return const SizedBox.shrink();
                  final globalIdx = allDepts.indexOf(dept);
                  final color = _deptColor(dept.name, globalIdx);
                  final isExpanded = _expandedDept == dept.name;
                  final pct = allTotal > 0 ? (dept.amount / allTotal * 100).round() : 0;

                  return Column(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() {
                          _expandedDept = isExpanded ? null : dept.name;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isExpanded ? const Color(0xFFF9FAFB) : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10, height: 10,
                                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  dept.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isExpanded ? FontWeight.w600 : FontWeight.w500,
                                    color: const Color(0xFF4B5563),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                _currency.format(dept.amount),
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$pct%',
                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Color(0xFF9CA3AF)),
                              ),
                              const SizedBox(width: 4),
                              AnimatedRotation(
                                turns: isExpanded ? 0.25 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(Icons.chevron_right, size: 12, color: Colors.grey.shade300),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isExpanded)
                        _buildCategoryDrillDown(dept),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryDrillDown(_DeptSpend dept) {
    final catEntries = dept.categories.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (catEntries.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 30, right: 12, bottom: 8, top: 4),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Color(0xFFF3F4F6), width: 2)),
        ),
        padding: const EdgeInsets.only(left: 12),
        child: Column(
          children: catEntries.map((entry) {
            final catColor = _categoryColors[entry.key] ?? const Color(0xFFB08D3A);
            final catLabel = _categoryLabels[entry.key] ?? entry.key;
            final catPct = dept.amount > 0 ? (entry.value / dept.amount * 100).round() : 0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(color: catColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(catLabel,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF6B7280))),
                  ),
                  Text(
                    _currency.format(entry.value),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$catPct%',
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w500, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            );
          }).toList(),
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
        GestureDetector(
          onTap: () => setState(() => _showPicker = false),
          child: Container(color: Colors.black.withValues(alpha: 0.4)),
        ),
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
                const Padding(
                  padding: EdgeInsets.only(top: 12, bottom: 4),
                  child: Center(
                    child: SizedBox(width: 40, height: 4, child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFFE5E7EB), borderRadius: BorderRadius.all(Radius.circular(2))))),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_pickerTitle,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _showPicker = false),
                        child: Container(
                          width: 32, height: 32,
                          decoration: const BoxDecoration(color: Color(0xFFF3F4F6), shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF)),
                        ),
                      ),
                    ],
                  ),
                ),
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
          SizedBox(
            width: 64,
            child: Text('$year', textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
          ),
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
                    color: isFuture ? const Color(0xFFFAFAFA) : isSelected ? const Color(0xFF46166B) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(_monthsShort[i], style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isFuture ? const Color(0xFFD1D5DB) : isSelected ? Colors.white : const Color(0xFF4B5563),
                      )),
                      if (isCur && !isSelected)
                        Positioned(bottom: 4,
                          child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF46166B), shape: BoxShape.circle))),
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
              setState(() { _yearlyYear = y; _showPicker = false; });
            },
            child: Container(
              decoration: BoxDecoration(
                color: isFuture ? const Color(0xFFFAFAFA) : isSelected ? const Color(0xFF46166B) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text('$y', style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isFuture ? const Color(0xFFD1D5DB) : isSelected ? Colors.white : const Color(0xFF4B5563),
                  )),
                  if (isCur && !isSelected)
                    Positioned(bottom: 6,
                      child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF46166B), shape: BoxShape.circle))),
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
          child: Text('Choose a month, then pick a week',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey.shade400)),
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
                  setState(() { _weeklyPickerMonth = i; _weeklyPickerStep = 2; });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isFuture ? const Color(0xFFFAFAFA) : isSelectedMonth ? const Color(0xFF46166B).withValues(alpha: 0.1) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                    border: isSelectedMonth ? Border.all(color: const Color(0xFF46166B).withValues(alpha: 0.2)) : null,
                  ),
                  alignment: Alignment.center,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(_monthsShort[i], style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelectedMonth ? FontWeight.w600 : FontWeight.w500,
                        color: isFuture ? const Color(0xFFD1D5DB) : isSelectedMonth ? const Color(0xFF46166B) : const Color(0xFF4B5563),
                      )),
                      if (isCur && !isSelectedMonth)
                        Positioned(bottom: 4,
                          child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF46166B), shape: BoxShape.circle))),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _weeklyPickerStep = 1),
                child: Container(
                  width: 28, height: 28,
                  decoration: const BoxDecoration(color: Color(0xFFF3F4F6), shape: BoxShape.circle),
                  child: const Icon(Icons.chevron_left, size: 14, color: Color(0xFF6B7280)),
                ),
              ),
              const SizedBox(width: 8),
              Text('${_monthsFull[_weeklyPickerMonth]} $_weeklyPickerYear',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4B5563))),
            ],
          ),
        ),
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
                      color: future ? const Color(0xFFFAFAFA) : isSelected ? const Color(0xFF46166B) : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(week['label'] as String, style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: future ? const Color(0xFFD1D5DB) : isSelected ? Colors.white : const Color(0xFF4B5563),
                          )),
                        ),
                        if (isCur)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF46166B).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('CURRENT', style: TextStyle(
                              fontSize: 8, fontWeight: FontWeight.w700,
                              color: isSelected ? Colors.white : const Color(0xFF46166B),
                              letterSpacing: 0.5,
                            )),
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

class _DeptSpend {
  final String name;
  final double amount;
  final double percentage;
  final int receiptCount;
  final int tripCount;
  final Map<String, double> categories;

  const _DeptSpend({
    required this.name,
    required this.amount,
    required this.percentage,
    required this.receiptCount,
    required this.tripCount,
    required this.categories,
  });
}
