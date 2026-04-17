import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'receipt.dart';
import 'models/trip.dart';
import 'api.dart';
import 'auth_service.dart';
import 'departments.dart';
import 'receipt_detail_page.dart';

// ─── Constants ───────────────────────────────────────────

const _kMonths = [
  'January','February','March','April','May','June',
  'July','August','September','October','November','December',
];
const _kMonthsShort = [
  'Jan','Feb','Mar','Apr','May','Jun',
  'Jul','Aug','Sep','Oct','Nov','Dec',
];

// Categories match the backend travel_category values (same as traveler side)
const _kCategories = [
  'All',
  'Meals',
  'Flight Cost',
  'Ground Transportation',
  'Registration Cost',
  'Accommodation Cost',
  'Other AS Cost',
];

const _kCategoryLabels = {
  'All': 'All',
  'Meals': 'Meals',
  'Flight Cost': 'Flight',
  'Ground Transportation': 'Ground Transport',
  'Registration Cost': 'Registration',
  'Accommodation Cost': 'Accommodation',
  'Other AS Cost': 'Other AS Cost',
};

const _kMealTypeLabels = {
  'breakfast': 'Breakfast',
  'lunch': 'Lunch',
  'dinner': 'Dinner',
  'incidentals': 'Incidentals',
  'hospitality': 'Hospitality',
};

const _kMealTypeColors = {
  'breakfast': Color(0xFFF59E0B),
  'lunch': Color(0xFF3B82F6),
  'dinner': Color(0xFF8B5CF6),
  'incidentals': Color(0xFF6B7280),
  'hospitality': Color(0xFFE8A824),
};

const _kPurple = Color(0xFF46166B);
const _kGold = Color(0xFFE8A824);
const _kDarkGold = Color(0xFFB08D3A);

// ─── Payment / Status configs ────────────────────────────

class _BadgeStyle {
  final String label;
  final Color dot;
  final Color text;
  final Color bg;
  const _BadgeStyle({required this.label, required this.dot, required this.text, required this.bg});
}

_BadgeStyle _paymentStyle(String method) {
  if (method == 'corporate') {
    return _BadgeStyle(
      label: 'AS Amex',
      dot: _kPurple,
      text: _kPurple,
      bg: _kPurple.withValues(alpha: 0.10),
    );
  }
  return _BadgeStyle(
    label: 'Personal',
    dot: _kGold,
    text: const Color(0xFFB8860B),
    bg: _kGold.withValues(alpha: 0.10),
  );
}

// ─── Page ────────────────────────────────────────────────

class AdminReceiptsPage extends StatefulWidget {
  final List<Receipt> receipts;
  final List<Trip> trips;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const AdminReceiptsPage({
    super.key,
    required this.receipts,
    required this.trips,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  State<AdminReceiptsPage> createState() => _AdminReceiptsPageState();
}

class _AdminReceiptsPageState extends State<AdminReceiptsPage> {
  final _currency = NumberFormat.simpleCurrency();
  final _api = APIService();

  late int _selectedMonth;
  late int _selectedYear;
  String _activeCategory = 'All';
  String _activeDept = 'All Departments';

  // Dynamic departments from Notion (with codes)
  List<Department> _departments = [];

  // For the detail view
  Receipt? _selectedReceipt;
  final _commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = now.month - 1; // 0-indexed
    _selectedYear = now.year;
    _fetchDepartments();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchDepartments() async {
    try {
      final depts = await _api.fetchDepartmentObjects();
      if (mounted) setState(() => _departments = depts);
    } catch (_) {}
  }

  // ─── iOS-style top toast ──────────────────────

  void _showToast(String message, {bool isError = false}) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TopToast(
        message: message,
        isError: isError,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  // ─── Receipt Approve / Comment ──────────────────────

  Future<void> _approveReceipt(Receipt receipt) async {
    try {
      await _api.approveReceipt(receipt.id);
      if (mounted) _showToast('Receipt approved');
    } catch (e) {
      if (mounted) _showToast('Failed to approve: $e', isError: true);
    }
  }

  Future<void> _sendReceiptComment(Receipt receipt) async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      await _api.addReceiptComment(receipt.id, text);
      _commentCtrl.clear();
      if (mounted) _showToast('Comment sent to traveler');
    } catch (e) {
      if (mounted) _showToast('Failed to send comment: $e', isError: true);
    }
  }

  void _showReceiptCommentSheet(Receipt receipt) {
    _commentCtrl.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Add Comment',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.close, size: 18, color: Colors.grey.shade500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add a comment about this receipt. The traveler will be notified.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _commentCtrl,
                    maxLines: 4,
                    minLines: 3,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'e.g. Please provide a clearer receipt image...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                      filled: true,
                      fillColor: const Color(0xFFFAFAFA),
                      contentPadding: const EdgeInsets.all(14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            _sendReceiptComment(receipt);
                          },
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFF46166B),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.chat_bubble_outline, size: 16, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'Send',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdminReceiptActions(Receipt receipt) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _approveReceipt(receipt),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDF6E3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE8A824).withValues(alpha: 0.3)),
                    ),
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check, size: 18, color: Color(0xFF9A7A2E)),
                        SizedBox(width: 8),
                        Text('Approve', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF9A7A2E))),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => _showReceiptCommentSheet(receipt),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF46166B).withValues(alpha: 0.3)),
                    ),
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 16, color: Color(0xFF46166B)),
                        SizedBox(width: 8),
                        Text('Add Comment', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF46166B))),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────

  Map<String, Trip> get _tripMap =>
      {for (final t in widget.trips) t.id: t};

  String? _departmentFor(Receipt r) {
    if (r.tripId == null) return null;
    return _tripMap[r.tripId]?.department;
  }

  /// Returns "Name (Code)" for display, or just name if no code found.
  String _deptDisplay(String deptName) {
    final match = _departments.where((d) => d.name == deptName);
    if (match.isNotEmpty && match.first.code.isNotEmpty) {
      return '${match.first.name} (${match.first.code})';
    }
    return deptName;
  }

  String? _travelerFor(Receipt r) {
    if (r.tripId == null) return null;
    return _tripMap[r.tripId]?.travelerName;
  }

  /// Returns the raw travel category for a receipt (matching backend values)
  String _categoryFor(Receipt r) {
    return r.travelCategory ?? r.category ?? 'Other AS Cost';
  }

  /// Short display label for a category
  String _categoryLabel(Receipt r) {
    final cat = _categoryFor(r);
    return _kCategoryLabels[cat] ?? cat;
  }

  List<Receipt> get _filtered {
    return widget.receipts.where((r) {
      // Month/year match
      if (r.date == null) return false;
      if (r.date!.month - 1 != _selectedMonth || r.date!.year != _selectedYear) return false;

      // Category match
      if (_activeCategory != 'All' && _categoryFor(r) != _activeCategory) return false;

      // Department match
      if (_activeDept != 'All Departments') {
        final dept = _departmentFor(r);
        if (dept == null || dept != _activeDept) return false;
      }

      return true;
    }).toList()
      ..sort((a, b) => (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)));
  }

  bool get _isAtCurrentMonth {
    final now = DateTime.now();
    return _selectedYear == now.year && _selectedMonth >= now.month - 1;
  }

  void _goToPrevMonth() {
    setState(() {
      if (_selectedMonth == 0) {
        _selectedMonth = 11;
        _selectedYear--;
      } else {
        _selectedMonth--;
      }
    });
  }

  void _goToNextMonth() {
    if (_isAtCurrentMonth) return;
    setState(() {
      if (_selectedMonth == 11) {
        _selectedMonth = 0;
        _selectedYear++;
      } else {
        _selectedMonth++;
      }
    });
  }

  int get _activeFilterCount =>
      (_activeCategory != 'All' ? 1 : 0) +
      (_activeDept != 'All Departments' ? 1 : 0);

  // ─── Build ───────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_selectedReceipt != null) {
      return _buildDetailView(_selectedReceipt!);
    }
    return _buildListView();
  }

  // ═══════════════════════════════════════════════════════
  //  LIST VIEW
  // ═══════════════════════════════════════════════════════

  Widget _buildListView() {
    if (widget.isLoading && widget.receipts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filtered;
    final monthTotal = filtered.fold<double>(0, (s, r) => s + r.effectiveTotal);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, size: 16, color: Color(0xFF6B7280)),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'All Receipts',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            Text(
              '${widget.receipts.length} total across all departments',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
        titleSpacing: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade100),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Month/Year Picker Card
            _buildMonthCard(filtered, monthTotal),

            // Filter button + active chips
            _buildFilterSection(),

            // Receipt List
            if (filtered.isEmpty)
              _buildEmptyState()
            else
              ...filtered.map((r) => _buildReceiptCard(r)),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ─── Month Card ──────────────────────────────────────

  Widget _buildMonthCard(List<Receipt> filtered, double monthTotal) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFDF6E3), Color(0xFFFBF0D1)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kGold.withValues(alpha: 0.20)),
        ),
        child: Column(
          children: [
            // Top accent line
            Container(
              height: 3,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_kPurple, _kGold, _kPurple],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  // Month navigation
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _circleButton(
                        icon: Icons.chevron_left,
                        onTap: _goToPrevMonth,
                      ),
                      GestureDetector(
                        onTap: () => _showMonthYearPicker(),
                        child: Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.calendar_today, size: 14, color: _kGold),
                                const SizedBox(width: 8),
                                Text(
                                  _kMonths[_selectedMonth],
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$_selectedYear',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w400,
                                    color: _kDarkGold,
                                  ),
                                ),
                                Icon(Icons.chevron_right, size: 12,
                                    color: _kDarkGold.withValues(alpha: 0.5)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _circleButton(
                        icon: Icons.chevron_right,
                        onTap: _isAtCurrentMonth ? null : _goToNextMonth,
                        disabled: _isAtCurrentMonth,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Divider
                  Container(height: 1, color: _kGold.withValues(alpha: 0.15)),
                  const SizedBox(height: 12),
                  // Stats row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: _kGold,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${filtered.length} receipt${filtered.length != 1 ? 's' : ''}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF9A7A2E),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _currency.format(monthTotal),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
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

  Widget _circleButton({
    required IconData icon,
    VoidCallback? onTap,
    bool disabled = false,
  }) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: disabled
              ? Colors.white.withValues(alpha: 0.30)
              : Colors.white.withValues(alpha: 0.60),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 16,
          color: disabled
              ? _kDarkGold.withValues(alpha: 0.30)
              : const Color(0xFF6B7280),
        ),
      ),
    );
  }

  // ─── Filter Section ──────────────────────────────────

  Widget _buildFilterSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _showFilterSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _activeFilterCount > 0 ? _kPurple : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: _activeFilterCount > 0
                    ? null
                    : Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.filter_list,
                    size: 14,
                    color: _activeFilterCount > 0 ? Colors.white : const Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Filter',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _activeFilterCount > 0 ? Colors.white : const Color(0xFF6B7280),
                    ),
                  ),
                  if (_activeFilterCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$_activeFilterCount',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_activeFilterCount > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (_activeDept != 'All Departments')
                  _activeChip(
                    icon: Icons.business,
                    label: _deptDisplay(_activeDept),
                    color: _kPurple,
                    onRemove: () => setState(() => _activeDept = 'All Departments'),
                  ),
                if (_activeCategory != 'All')
                  _activeChip(
                    icon: Icons.label_outline,
                    label: _kCategoryLabels[_activeCategory] ?? _activeCategory,
                    color: const Color(0xFFB8860B),
                    bgColor: _kGold.withValues(alpha: 0.10),
                    onRemove: () => setState(() => _activeCategory = 'All'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeptChip(String value, String label, String code, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _kPurple : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(20),
          border: selected ? null : Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Text(
          code.isNotEmpty ? '$label ($code)' : label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }

  Widget _activeChip({
    required IconData icon,
    required String label,
    required Color color,
    Color? bgColor,
    required VoidCallback onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor ?? color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close, size: 12, color: color),
          ),
        ],
      ),
    );
  }

  // ─── Receipt Card ────────────────────────────────────

  Widget _mealTypeTag(String mealType) {
    final color = _kMealTypeColors[mealType] ?? const Color(0xFF6B7280);
    final label = _kMealTypeLabels[mealType] ?? mealType;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildReceiptCard(Receipt receipt) {
    final ps = _paymentStyle(receipt.paymentMethod);
    final categoryDisplay = _categoryLabel(receipt);
    final traveler = _travelerFor(receipt);
    final department = _departmentFor(receipt);
    final dateStr = receipt.date != null
        ? DateFormat('MMM d, y').format(receipt.date!)
        : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: GestureDetector(
        onTap: () => setState(() => _selectedReceipt = receipt),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              // Thumbnail
              _receiptThumbnail(receipt, 44),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      receipt.merchant ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _pillBadge(categoryDisplay, Colors.grey.shade100, const Color(0xFF6B7280)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: ps.bg,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            ps.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: ps.text,
                            ),
                          ),
                        ),
                        if (receipt.mealType != null)
                          _mealTypeTag(receipt.mealType!),
                      ],
                    ),
                    if (traveler != null || department != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (traveler != null && traveler.isNotEmpty)
                            Flexible(
                              child: Text(
                                traveler,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFFD1D5DB),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (traveler != null && traveler.isNotEmpty &&
                              department != null && department.isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Text('•',
                                  style: TextStyle(fontSize: 8, color: Color(0xFFE5E7EB))),
                            ),
                          if (department != null && department.isNotEmpty)
                            Flexible(
                              child: Text(
                                department,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFFD1D5DB),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Amount
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _currency.format(receipt.effectiveTotal),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                  if (dateStr.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _receiptThumbnail(Receipt receipt, double size) {
    if (receipt.imageUrl != null) {
      return FutureBuilder<String?>(
        future: AuthService.instance.getToken(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return _thumbnailPlaceholder(size);
          }
          final url = APIService().receiptImageUrl(receipt.id);
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: size,
              height: size,
              child: Image.network(
                url,
                headers: {'Authorization': 'Bearer ${snap.data}'},
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _thumbnailPlaceholder(size),
              ),
            ),
          );
        },
      );
    }
    return _thumbnailPlaceholder(size);
  }

  Widget _thumbnailPlaceholder(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.receipt, size: size * 0.45, color: Colors.grey.shade300),
    );
  }

  Widget _pillBadge(String label, Color bg, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: text),
      ),
    );
  }

  // ─── Empty State ─────────────────────────────────────

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.filter_list, size: 24, color: Colors.grey.shade300),
          ),
          const SizedBox(height: 12),
          const Text(
            'No receipts found',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Try a different month, category, or department',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: Color(0xFFD1D5DB),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  DETAIL VIEW
  // ═══════════════════════════════════════════════════════

  Widget _buildDetailView(Receipt receipt) {
    final ps = _paymentStyle(receipt.paymentMethod);
    final categoryDisplay = _categoryLabel(receipt);
    final traveler = _travelerFor(receipt);
    final department = _departmentFor(receipt);
    final dateStr = receipt.date != null
        ? DateFormat('MMM d, y').format(receipt.date!)
        : 'No date';

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, size: 16, color: Color(0xFF6B7280)),
          ),
          onPressed: () => setState(() => _selectedReceipt = null),
        ),
        title: const Text(
          'Receipt Details',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFEF4444)),
            ),
            onPressed: () => _showDiscardConfirm(receipt),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade100),
        ),
      ),
      bottomNavigationBar: _buildAdminReceiptActions(receipt),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          // Receipt Image
          GestureDetector(
            onTap: receipt.imageUrl != null
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReceiptDetailPage(receipt: receipt),
                      ),
                    )
                : null,
            child: Container(
              height: 192,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: receipt.imageUrl != null
                  ? FutureBuilder<String?>(
                      future: AuthService.instance.getToken(),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final url = APIService().receiptImageUrl(receipt.id);
                        return Image.network(
                          url,
                          headers: {'Authorization': 'Bearer ${snap.data}'},
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => Center(
                            child: Icon(Icons.receipt_long, size: 48, color: Colors.grey.shade300),
                        ),
                      );
                    },
                  )
                : Center(
                    child: Icon(Icons.receipt_long, size: 48, color: Colors.grey.shade300),
                  ),
            ),
          ),

          const SizedBox(height: 16),

          // Title + Amount Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            receipt.merchant ?? 'Unknown Merchant',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          ),
                          if (receipt.address != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              receipt.address!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      _currency.format(receipt.effectiveTotal),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _detailBadge(ps.label, ps.dot, ps.text, ps.bg),
                    _pillBadge(categoryDisplay, Colors.grey.shade100, const Color(0xFF6B7280)),
                    if (receipt.mealType != null)
                      _mealTypeTag(receipt.mealType!),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Info Cards
          if (department != null && department.isNotEmpty)
            _infoCard(
              icon: Icons.business,
              iconBg: _kPurple,
              label: 'DEPARTMENT',
              value: department,
            ),
          _infoCard(
            icon: Icons.calendar_today,
            iconBg: const Color(0xFF111827),
            label: 'DATE',
            value: dateStr,
          ),
          if (traveler != null && traveler.isNotEmpty)
            _infoCard(
              icon: Icons.person,
              iconBg: _kGold,
              label: 'TRAVELER',
              value: traveler,
            ),
        ],
      ),
    );
  }

  Widget _detailBadge(String label, Color dot, Color text, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: text),
          ),
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color iconBg,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF9CA3AF),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  BOTTOM SHEETS
  // ═══════════════════════════════════════════════════════

  void _showFilterSheet() {
    String tempDept = _activeDept;
    String tempCat = _activeCategory;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.80,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Filter Receipts',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                      IconButton(
                        icon: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF)),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Department
                        const Text(
                          'DEPARTMENT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF9CA3AF),
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildDeptChip('All Departments', 'All', '', tempDept == 'All Departments', () => setSheetState(() => tempDept = 'All Departments')),
                            ..._departments.map((dept) {
                              final selected = tempDept == dept.name;
                              return _buildDeptChip(dept.name, dept.name, dept.code, selected, () => setSheetState(() => tempDept = dept.name));
                            }),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Category
                        const Text(
                          'RECEIPT TYPE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF9CA3AF),
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _kCategories.map((cat) {
                            final selected = tempCat == cat;
                            return GestureDetector(
                              onTap: () => setSheetState(() => tempCat = cat),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: selected ? _kGold : const Color(0xFFF9FAFB),
                                  borderRadius: BorderRadius.circular(20),
                                  border: selected
                                      ? null
                                      : Border.all(color: const Color(0xFFE5E7EB)),
                                ),
                                child: Text(
                                  _kCategoryLabels[cat] ?? cat,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                    color: selected ? Colors.white : const Color(0xFF6B7280),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                        // Actions
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setSheetState(() {
                                  tempDept = 'All Departments';
                                  tempCat = 'All';
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Text(
                                    'Reset',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _activeDept = tempDept;
                                    _activeCategory = tempCat;
                                  });
                                  Navigator.pop(ctx);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    color: _kPurple,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Text(
                                    'Apply Filters',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showMonthYearPicker() {
    int pickerYear = _selectedYear;
    final now = DateTime.now();
    final minYear = 2024;
    final maxYear = now.year;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select Month & Year',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                      IconButton(
                        icon: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF)),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                // Year selector
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: pickerYear > minYear
                            ? () => setSheetState(() => pickerYear--)
                            : null,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: pickerYear > minYear
                                ? Colors.grey.shade100
                                : const Color(0xFFF9FAFB),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.chevron_left,
                            size: 16,
                            color: pickerYear > minYear
                                ? const Color(0xFF6B7280)
                                : const Color(0xFFE5E7EB),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Text(
                          '$pickerYear',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: pickerYear < maxYear
                            ? () => setSheetState(() => pickerYear++)
                            : null,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: pickerYear < maxYear
                                ? Colors.grey.shade100
                                : const Color(0xFFF9FAFB),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: pickerYear < maxYear
                                ? const Color(0xFF6B7280)
                                : const Color(0xFFE5E7EB),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Month grid
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 2.2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: 12,
                    itemBuilder: (_, i) {
                      final isFuture = pickerYear == now.year && i > now.month - 1;
                      final isSelected = i == _selectedMonth && pickerYear == _selectedYear;
                      return GestureDetector(
                        onTap: isFuture
                            ? null
                            : () {
                                setState(() {
                                  _selectedMonth = i;
                                  _selectedYear = pickerYear;
                                });
                                Navigator.pop(ctx);
                              },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isFuture
                                ? Colors.transparent
                                : isSelected
                                    ? _kPurple
                                    : const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _kMonthsShort[i],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isFuture
                                  ? const Color(0xFFE5E7EB)
                                  : isSelected
                                      ? Colors.white
                                      : const Color(0xFF374151),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDiscardConfirm(Receipt receipt) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.delete_outline, size: 24, color: Color(0xFFEF4444)),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Discard Receipt?',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This will permanently remove "${receipt.merchant ?? 'this receipt'}" and cannot be undone.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              Navigator.pop(ctx);
                              try {
                                await APIService().deleteReceipt(receipt.id);
                                if (mounted) {
                                  setState(() => _selectedReceipt = null);
                                  widget.onRefresh();
                                }
                              } catch (e) {
                                if (mounted) _showToast('Failed to delete: $e', isError: true);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'Discard',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopToast extends StatefulWidget {
  final String message;
  final bool isError;
  final VoidCallback onDismiss;

  const _TopToast({
    required this.message,
    required this.isError,
    required this.onDismiss,
  });

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 3), _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    _ctrl.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Positioned(
      top: top + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: GestureDetector(
            onVerticalDragUpdate: (d) {
              if (d.primaryDelta != null && d.primaryDelta! < -4) _dismiss();
            },
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: widget.isError ? const Color(0xFFFEE2E2) : const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: widget.isError ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: widget.isError
                            ? const Color(0xFFDC2626).withValues(alpha: 0.1)
                            : const Color(0xFF059669).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        widget.isError ? Icons.error_outline : Icons.check_circle_outline,
                        size: 18,
                        color: widget.isError ? const Color(0xFFDC2626) : const Color(0xFF059669),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: widget.isError ? const Color(0xFF991B1B) : const Color(0xFF065F46),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _dismiss,
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: widget.isError
                            ? const Color(0xFF991B1B).withValues(alpha: 0.5)
                            : const Color(0xFF065F46).withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
