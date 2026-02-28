import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'services/analytics_service.dart';
import 'trip_detail_page.dart';

enum TimePeriod { week, month, year }

class AnalyticsPage extends StatefulWidget {
  final AnalyticsService? analyticsService;
  final VoidCallback? onTripTap;
  const AnalyticsPage({super.key, this.analyticsService, this.onTripTap});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final _currency = NumberFormat.simpleCurrency();
  TimePeriod _period = TimePeriod.month;

  // Month navigation for the Week (5-day bucket) view
  late int _weekViewYear;
  late int _weekViewMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekViewYear = now.year;
    _weekViewMonth = now.month;
  }

  AnalyticsService? get _analytics => widget.analyticsService;

  @override
  Widget build(BuildContext context) {
    if (_analytics == null) {
      return const Center(child: Text('No data available'));
    }

    return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Time period toggle
          _buildPeriodToggle(),
          const SizedBox(height: 20),

          // Quick stats
          _buildQuickStats(),
          const SizedBox(height: 24),

          // Spending trend bar chart
          _buildSectionTitle('Spending Trend'),
          if (_period == TimePeriod.week) ...[
            const SizedBox(height: 8),
            _buildMonthNavigator(),
          ],
          const SizedBox(height: 12),
          _buildBarChart(),
          const SizedBox(height: 28),

          // Category breakdown pie chart
          _buildSectionTitle('Category Breakdown'),
          const SizedBox(height: 12),
          _buildPieChart(),
          const SizedBox(height: 28),

          // Trip comparison
          _buildSectionTitle('Expenses by Trip'),
          const SizedBox(height: 12),
          _buildTripComparison(),
          const SizedBox(height: 80),
        ],
      );
  }

  Widget _buildPeriodToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: TimePeriod.values.map((p) {
          final selected = _period == p;
          final label = switch (p) {
            TimePeriod.week => 'Week',
            TimePeriod.month => 'Month',
            TimePeriod.year => 'Year',
          };
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _period = p),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF1565C0) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildQuickStats() {
    final a = _analytics!;
    final totalSpent = a.totalFromTrips;
    final tripCount = a.trips.length;
    final avgPerTrip = tripCount > 0 ? totalSpent / tripCount : 0.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _statCard(Icons.account_balance_wallet, 'Total Spent',
              _currency.format(totalSpent), const Color(0xFF1565C0)),
          const SizedBox(width: 12),
          _statCard(Icons.flight, 'Trips', '$tripCount',
              const Color(0xFF7C3AED)),
          const SizedBox(width: 12),
          _statCard(Icons.trending_up, 'Avg / Trip',
              _currency.format(avgPerTrip), const Color(0xFF059669)),
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
            color: Colors.black.withOpacity(0.04),
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
              color: color.withOpacity(0.12),
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

  List<SpendingDataPoint> _getBarData() {
    final a = _analytics!;
    return switch (_period) {
      TimePeriod.week => a.spendingByDayBucket(_weekViewYear, _weekViewMonth),
      TimePeriod.month => a.spendingByMonth(),
      TimePeriod.year => a.spendingByYear(),
    };
  }

  Widget _buildMonthNavigator() {
    final monthNames = ['January', 'February', 'March', 'April', 'May', 'June',
                        'July', 'August', 'September', 'October', 'November', 'December'];
    final now = DateTime.now();
    final isCurrentMonth = _weekViewYear == now.year && _weekViewMonth == now.month;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: _prevMonth,
          icon: const Icon(Icons.chevron_left, color: Color(0xFF1565C0)),
        ),
        Text(
          '${monthNames[_weekViewMonth - 1]} $_weekViewYear',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1F2937),
          ),
        ),
        IconButton(
          onPressed: isCurrentMonth ? null : _nextMonth,
          icon: Icon(
            Icons.chevron_right,
            color: isCurrentMonth ? const Color(0xFFD1D5DB) : const Color(0xFF1565C0),
          ),
        ),
      ],
    );
  }

  void _prevMonth() {
    setState(() {
      _weekViewMonth--;
      if (_weekViewMonth < 1) {
        _weekViewMonth = 12;
        _weekViewYear--;
      }
    });
  }

  void _nextMonth() {
    final now = DateTime.now();
    // Don't go past the current month
    if (_weekViewYear == now.year && _weekViewMonth >= now.month) return;
    setState(() {
      _weekViewMonth++;
      if (_weekViewMonth > 12) {
        _weekViewMonth = 1;
        _weekViewYear++;
      }
    });
  }

  Widget _buildBarChart() {
    final data = _getBarData();
    final maxY = data.fold(0.0, (m, d) => d.amount > m ? d.amount : m);
    final effectiveMaxY = maxY == 0 ? 100.0 : maxY * 1.2;

    // Month view needs more width for 12 bars
    final needsScroll = _period == TimePeriod.month;
    final chartWidth = needsScroll ? data.length * 50.0 : null;

    final chart = Container(
      height: 220,
      width: chartWidth,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: chartWidth != null ? null : BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: effectiveMaxY,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  _currency.format(rod.toY),
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                getTitlesWidget: (value, meta) {
                  if (value == 0) return const SizedBox.shrink();
                  String text;
                  if (value >= 1000) {
                    text = '\$${(value / 1000).toStringAsFixed(1)}k';
                  } else {
                    text = '\$${value.toInt()}';
                  }
                  return Text(
                    text,
                    style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      data[idx].label,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: effectiveMaxY / 4,
            getDrawingHorizontalLine: (value) => FlLine(
              color: const Color(0xFFE2E8F0),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: data.asMap().entries.map((entry) {
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: entry.value.amount,
                  width: switch (_period) {
                    TimePeriod.week => 28,
                    TimePeriod.month => 20,
                    TimePeriod.year => 40,
                  },
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );

    if (!needsScroll) return chart;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        child: chart,
      ),
    );
  }

  Widget _buildPieChart() {
    final categories = _analytics!.categoryTotalsFromTrips();

    if (categories.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text('No expense data yet', style: TextStyle(color: Color(0xFF94A3B8))),
        ),
      );
    }

    final colors = [
      const Color(0xFF1565C0), // Accommodation
      const Color(0xFF7C3AED), // Flight
      const Color(0xFF059669), // Ground Transport
      const Color(0xFFF97316), // Registration
      const Color(0xFFEC4899), // Other
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: categories.asMap().entries.map((entry) {
                  final i = entry.key;
                  final cat = entry.value;
                  return PieChartSectionData(
                    color: colors[i % colors.length],
                    value: cat.amount,
                    title: '${cat.percentage.toStringAsFixed(0)}%',
                    titleStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    radius: 55,
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Legend
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: categories.asMap().entries.map((entry) {
              final i = entry.key;
              final cat = entry.value;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors[i % colors.length],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${cat.name} (${_currency.format(cat.amount)})',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTripComparison() {
    final tripEntries = _analytics!.tripComparison();

    if (tripEntries.isEmpty) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text('No trips yet', style: TextStyle(color: Color(0xFF94A3B8))),
        ),
      );
    }

    final maxExpense = tripEntries.first.totalExpenses;
    final effectiveMax = maxExpense == 0 ? 1.0 : maxExpense;

    return Column(
      children: tripEntries.map((entry) {
        final fraction = entry.totalExpenses / effectiveMax;
        return GestureDetector(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TripDetailPage(trip: entry.trip)),
            );
            widget.onTripTap?.call();
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.trip.displayTitle,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _currency.format(entry.totalExpenses),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                if (entry.trip.destination != null && entry.trip.destination!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.trip.destination!,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                ],
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: fraction),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (_, value, __) => LinearProgressIndicator(
                      value: value,
                      backgroundColor: const Color(0xFFF1F5F9),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF1565C0)),
                      minHeight: 6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
