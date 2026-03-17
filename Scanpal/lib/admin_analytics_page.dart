import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class AdminAnalyticsPage extends StatefulWidget {
  final Map<String, dynamic>? orgAnalytics;
  final List<Map<String, dynamic>> departments;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  final void Function(String department) onDepartmentTap;

  const AdminAnalyticsPage({
    super.key,
    required this.orgAnalytics,
    required this.departments,
    required this.isLoading,
    required this.onRefresh,
    required this.onDepartmentTap,
  });

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage> {
  final _currency = NumberFormat.simpleCurrency();

  // Selected department index for drill-down (-1 = none selected)
  int _selectedDeptIndex = -1;

  static const _deptColors = [
    Color(0xFF1565C0),
    Color(0xFF7C3AED),
    Color(0xFF059669),
    Color(0xFFF97316),
    Color(0xFFEC4899),
    Color(0xFF0891B2),
    Color(0xFFDC2626),
    Color(0xFF4F46E5),
  ];

  static const _categoryColors = [
    Color(0xFF1565C0), // Accommodation
    Color(0xFF7C3AED), // Flight
    Color(0xFF059669), // Ground Transport
    Color(0xFFF97316), // Registration
    Color(0xFFEC4899), // Other
  ];

  @override
  void didUpdateWidget(AdminAnalyticsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.departments != widget.departments) {
      _selectedDeptIndex = -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading && widget.orgAnalytics == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.orgAnalytics == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_rounded, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Failed to load analytics',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: widget.onRefresh, child: const Text('Retry')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildOrgSummary(),
          const SizedBox(height: 24),
          _buildSectionTitle('Department Breakdown'),
          const SizedBox(height: 4),
          Text(
            'Tap a slice to see category details',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 12),
          _buildDepartmentPieChart(),
          const SizedBox(height: 24),
          // Category drill-down (shown when a department is selected)
          if (_selectedDeptIndex >= 0 && _selectedDeptIndex < widget.departments.length) ...[
            _buildCategoryDrillDown(widget.departments[_selectedDeptIndex]),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Color(0xFF0F172A),
      ),
    );
  }

  // ─── Section 1: Org-Wide Summary Cards ───────────────

  Widget _buildOrgSummary() {
    final totalExpenses = (widget.orgAnalytics!['total_expenses'] as num?)?.toDouble() ?? 0.0;
    final tripCount = (widget.orgAnalytics!['trip_count'] as num?)?.toInt() ?? 0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _statCard(Icons.account_balance_wallet, 'Total Expenses',
              _currency.format(totalExpenses), const Color(0xFF1565C0)),
          const SizedBox(width: 12),
          _statCard(Icons.flight, 'Total Trips', '$tripCount',
              const Color(0xFF7C3AED)),
        ],
      ),
    );
  }

  Widget _statCard(IconData icon, String label, String value, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Section 2: Department Pie Chart ─────────────────

  Widget _buildDepartmentPieChart() {
    if (widget.departments.isEmpty) {
      return _emptyCard('No department data');
    }

    final total = widget.departments.fold(0.0, (sum, d) =>
        sum + ((d['total_expenses'] as num?)?.toDouble() ?? 0.0));
    if (total == 0) return _emptyCard('No expense data yet');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 220,
            child: PieChart(
              PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    if (event is! FlTapUpEvent ||
                        response == null ||
                        response.touchedSection == null) {
                      return;
                    }
                    final index = response.touchedSection!.touchedSectionIndex;
                    if (index >= 0 && index < widget.departments.length) {
                      setState(() {
                        _selectedDeptIndex = _selectedDeptIndex == index ? -1 : index;
                      });
                    }
                  },
                ),
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: List.generate(widget.departments.length, (i) {
                  final dept = widget.departments[i];
                  final amount = (dept['total_expenses'] as num?)?.toDouble() ?? 0.0;
                  if (amount == 0) {
                    return PieChartSectionData(
                      color: _deptColors[i % _deptColors.length],
                      value: 0,
                      showTitle: false,
                      radius: 55,
                    );
                  }
                  final pct = (amount / total * 100);
                  final isSelected = _selectedDeptIndex == i;
                  return PieChartSectionData(
                    color: _deptColors[i % _deptColors.length],
                    value: amount,
                    title: pct > 0 && pct < 1 ? '<1%' : '${pct.toStringAsFixed(0)}%',
                    titleStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    radius: isSelected ? 65 : 55,
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: List.generate(widget.departments.length, (i) {
              final dept = widget.departments[i];
              final name = dept['department'] as String? ?? 'Unknown';
              final amount = (dept['total_expenses'] as num?)?.toDouble() ?? 0.0;
              if (amount == 0) return const SizedBox.shrink();
              final isSelected = _selectedDeptIndex == i;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedDeptIndex = _selectedDeptIndex == i ? -1 : i;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _deptColors[i % _deptColors.length].withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _deptColors[i % _deptColors.length],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 12,
                          color: const Color(0xFF4B5563),
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ─── Category Drill-Down for Selected Department ─────

  Widget _buildCategoryDrillDown(Map<String, dynamic> dept) {
    final deptName = dept['department'] as String? ?? 'Unknown';
    final totalExpenses = (dept['total_expenses'] as num?)?.toDouble() ?? 0.0;

    final categoryKeys = [
      'accommodation_cost',
      'flight_cost',
      'ground_transportation',
      'registration_cost',
      'other_as_cost',
    ];
    final categoryLabels = [
      'Accommodation',
      'Flight',
      'Ground Transport',
      'Registration',
      'Other',
    ];

    final amounts = categoryKeys
        .map((k) => (dept[k] as num?)?.toDouble() ?? 0.0)
        .toList();
    final hasData = amounts.any((a) => a > 0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0891B2).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.business, size: 14, color: Color(0xFF0891B2)),
                    const SizedBox(width: 4),
                    Text(
                      deptName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0891B2),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                _currency.format(totalExpenses),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasData)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No expenses recorded',
                    style: TextStyle(color: Color(0xFF94A3B8))),
              ),
            )
          else
            ...List.generate(categoryKeys.length, (i) {
              final amount = amounts[i];
              if (amount == 0) return const SizedBox.shrink();
              final fraction = totalExpenses > 0 ? amount / totalExpenses : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _categoryColors[i],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            categoryLabels[i],
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ),
                        Text(
                          _currency.format(amount),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: fraction),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        builder: (_, value, __) => LinearProgressIndicator(
                          value: value,
                          backgroundColor: const Color(0xFFF1F5F9),
                          valueColor: AlwaysStoppedAnimation(_categoryColors[i]),
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
    );
  }

  // ─── Helpers ─────────────────────────────────────────

  Widget _emptyCard(String message) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(message, style: const TextStyle(color: Color(0xFF94A3B8))),
      ),
    );
  }
}
