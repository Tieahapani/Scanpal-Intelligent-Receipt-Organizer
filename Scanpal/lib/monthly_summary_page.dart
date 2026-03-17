import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api.dart';
import 'services/monthly_summary_service.dart';
import 'widgets/summary_cards.dart';
import 'expense_report_page.dart';

class MonthlySummaryPage extends StatefulWidget {
  final String? tripId;
  const MonthlySummaryPage({super.key, this.tripId});

  @override
  State<MonthlySummaryPage> createState() => _MonthlySummaryPageState();
}

class _MonthlySummaryPageState extends State<MonthlySummaryPage> {
  final _api = APIService();
  final _currency = NumberFormat.simpleCurrency();

  bool _loading = true;
  late DateTimeRange _range;
  MonthlySummaryService? _service;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: now,
    );
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final receipts = await _api.fetchReceipts(tripId: widget.tripId);
      if (mounted) {
        setState(() {
          _service = MonthlySummaryService(receipts);
        });
      }
    } catch (e) {
      debugPrint('Failed to load receipts: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _range,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1565C0),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _range = picked);
    }
  }

  void _openReport() {
    if (_service == null) return;
    final stats = _service!.quickStats(_range);
    final cats = _service!.categoryBreakdown(_range);
    final vendors = _service!.vendorBreakdown(_range);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseReportPage(
          dateRange: _range,
          stats: stats,
          categoryBreakdown: cats,
          vendorBreakdown: vendors,
          currency: _currency,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d');

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FF),
      appBar: AppBar(
        title: const Text(
          'Spending Analytics',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            tooltip: 'Generate Report',
            onPressed: _service != null ? _openReport : null,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _buildContent(dateFormat),
            ),
    );
  }

  Widget _buildContent(DateFormat dateFormat) {
    if (_service == null) {
      return const Center(child: Text('No data available'));
    }

    final stats = _service!.quickStats(_range);
    final cats = _service!.categoryBreakdown(_range);
    final vendors = _service!.vendorBreakdown(_range);
    final insight = _service!.expenseInsight(_range);
    final topVendor = _service!.topVendorInsight(_range);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Date range selector
        GestureDetector(
          onTap: _pickDateRange,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 18, color: Color(0xFF1565C0)),
                const SizedBox(width: 10),
                Text(
                  '${dateFormat.format(_range.start)} - ${dateFormat.format(_range.end)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
                const Spacer(),
                const Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Quick stats row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              StatCard(
                icon: Icons.account_balance_wallet,
                label: 'Total Spent',
                value: _currency.format(stats.currentTotal),
                color: const Color(0xFF1565C0),
              ),
              const SizedBox(width: 12),
              StatCard(
                icon: Icons.trending_up,
                label: 'Daily Avg',
                value: _currency.format(stats.dailyAverage ?? 0),
                color: const Color(0xFF7C3AED),
              ),
              const SizedBox(width: 12),
              StatCard(
                icon: Icons.receipt_long,
                label: 'Receipts',
                value: '${stats.receiptsCount}',
                color: const Color(0xFF059669),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Expense trend insight
        ExpenseTrendCard(insight: insight),
        const SizedBox(height: 16),

        // Top vendor
        if (topVendor != null) ...[
          TopVendorCard(insight: topVendor, currencyFormatter: _currency),
          const SizedBox(height: 20),
        ],

        // Category breakdown
        if (cats.isNotEmpty) ...[
          const Text(
            'By Category',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 12),
          ...cats.map((cat) => _breakdownRow(
                cat.categoryName,
                cat.total,
                cat.percentage,
                Icons.category_rounded,
              )),
          const SizedBox(height: 20),
        ],

        // Vendor breakdown
        if (vendors.isNotEmpty) ...[
          const Text(
            'By Vendor',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 12),
          ...vendors.map((v) => _breakdownRow(
                v.vendorName,
                v.total,
                v.percentage,
                Icons.store_rounded,
              )),
        ],
      ],
    );
  }

  Widget _breakdownRow(String name, double total, double pct, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF64748B)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct / 100,
                    backgroundColor: const Color(0xFFF1F5F9),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF1565C0)),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _currency.format(total),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              Text(
                '${pct.toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
