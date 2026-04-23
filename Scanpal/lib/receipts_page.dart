import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'receipt.dart';
import 'models/trip.dart';
import 'api.dart';
import 'auth_service.dart';
import 'receipt_detail_page.dart';
import 'receipt_detail_view_page.dart';

class ReceiptsPage extends StatefulWidget {
  final List<Receipt> receipts;
  final List<Trip> trips;
  final VoidCallback? onRefresh;

  const ReceiptsPage({
    super.key,
    required this.receipts,
    required this.trips,
    this.onRefresh,
  });

  @override
  State<ReceiptsPage> createState() => _ReceiptsPageState();
}

class _ReceiptsPageState extends State<ReceiptsPage> {
  late int _selectedMonth;
  late int _selectedYear;
  String _activeCategory = 'All';
  Receipt? _selectedReceipt;
  bool _showPicker = false;
  late int _pickerYear;

  static const _categories = [
    'All',
    'Accommodation Cost',
    'Flight Cost',
    'Ground Transportation',
    'Registration Cost',
    'Meals',
    'Other AS Cost',
  ];

  // Short labels for the filter pills
  static const _categoryLabels = {
    'All': 'All',
    'Accommodation Cost': 'Accommodation',
    'Flight Cost': 'Flight',
    'Ground Transportation': 'Ground Transport',
    'Registration Cost': 'Registration',
    'Meals': 'Meals',
    'Other AS Cost': 'Other AS Cost',
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = now.month;
    _selectedYear = now.year;
    _pickerYear = now.year;
  }

  List<Receipt> get _filtered {
    return widget.receipts.where((r) {
      final d = r.date;
      if (d == null) return false;
      final matchesMonth = d.month == _selectedMonth && d.year == _selectedYear;
      final matchesCategory = _activeCategory == 'All' ||
          (r.travelCategory ?? r.category ?? 'Other AS Cost') == _activeCategory;
      return matchesMonth && matchesCategory;
    }).toList()
      ..sort((a, b) => (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)));
  }

  /// Returns the display label for a receipt's travel category
  String _categoryLabel(Receipt r) {
    final cat = r.travelCategory ?? r.category ?? 'Other AS Cost';
    return _categoryLabels[cat] ?? cat;
  }

  double get _monthTotal {
    return _filtered.fold(0.0, (sum, r) => sum + r.total);
  }

  String _tripNameForReceipt(Receipt r) {
    if (r.tripId == null) return 'General';
    final trip = widget.trips.where((t) => t.id == r.tripId).firstOrNull;
    return trip?.displayTitle ?? 'General';
  }

  void _goToPrevMonth() {
    setState(() {
      if (_selectedMonth == 1) {
        _selectedMonth = 12;
        _selectedYear--;
      } else {
        _selectedMonth--;
      }
    });
  }

  void _goToNextMonth() {
    final now = DateTime.now();
    if (_selectedYear == now.year && _selectedMonth >= now.month) return;
    setState(() {
      if (_selectedMonth == 12) {
        _selectedMonth = 1;
        _selectedYear++;
      } else {
        _selectedMonth++;
      }
    });
  }

  bool get _isAtCurrentMonth {
    final now = DateTime.now();
    return _selectedYear == now.year && _selectedMonth >= now.month;
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedReceipt != null) {
      return _buildDetailView();
    }
    return _buildListView();
  }

  // ─── List View ──────────────────────────────────────

  Widget _buildListView() {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _buildMonthRoller(),
                    _buildCategoryFilters(),
                    if (filtered.isEmpty)
                      _buildEmptyState()
                    else
                      ..._buildReceiptList(filtered),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
          if (_showPicker) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showPicker = false),
                child: Container(color: Colors.black.withOpacity(0.4)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildMonthYearPicker(),
            ),
          ],
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.arrow_back, size: 16, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'My Receipts',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  Text(
                    '${widget.receipts.length} total receipts',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthRoller() {
    final filtered = _filtered;
    final monthName = DateFormat('MMMM').format(DateTime(_selectedYear, _selectedMonth));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFDF6E3), Color(0xFFFBF0D1)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8A824).withOpacity(0.2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Top accent line
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 3,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF46166B), Color(0xFFE8A824), Color(0xFF46166B)],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: _goToPrevMonth,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.chevron_left, size: 16, color: Colors.grey.shade600),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() {
                          _pickerYear = _selectedYear;
                          _showPicker = true;
                        }),
                        child: Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.calendar_today, size: 14, color: const Color(0xFFE8A824)),
                                const SizedBox(width: 8),
                                Text(
                                  monthName,
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
                                    color: Color(0xFFB08D3A),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(Icons.chevron_right, size: 12, color: const Color(0xFFB08D3A).withOpacity(0.5)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: _isAtCurrentMonth ? null : _goToNextMonth,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(_isAtCurrentMonth ? 0.3 : 0.6),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: _isAtCurrentMonth
                                ? const Color(0xFFB08D3A).withOpacity(0.3)
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: const Color(0xFFE8A824).withOpacity(0.15)),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE8A824),
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
                          '\$${_monthTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _categories.map((cat) {
            final isActive = _activeCategory == cat;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _activeCategory = cat),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFF111827) : Colors.white,
                    borderRadius: BorderRadius.circular(100),
                    border: isActive ? null : Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    _categoryLabels[cat] ?? cat,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive ? Colors.white : Colors.grey.shade500,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.filter_list, size: 24, color: Colors.grey.shade300),
          ),
          const SizedBox(height: 12),
          Text(
            'No receipts for this month',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try selecting a different month or category',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: Colors.grey.shade300,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildReceiptList(List<Receipt> receipts) {
    return receipts.map((receipt) => _receiptCard(receipt)).toList();
  }

  static const _mealTypeColors = {
    'breakfast': Color(0xFFF59E0B),
    'lunch': Color(0xFF3B82F6),
    'dinner': Color(0xFF8B5CF6),
    'incidentals': Color(0xFF6B7280),
    'hospitality': Color(0xFFE8A824),
  };

  static const _mealTypeLabels = {
    'breakfast': 'Breakfast',
    'lunch': 'Lunch',
    'dinner': 'Dinner',
    'incidentals': 'Incidentals',
    'hospitality': 'Hospitality',
  };

  Widget _mealTypeTag(String mealType) {
    final color = _mealTypeColors[mealType] ?? const Color(0xFF6B7280);
    final label = _mealTypeLabels[mealType] ?? mealType;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
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

  Widget _receiptCard(Receipt receipt) {
    final category = _categoryLabel(receipt);
    final dateStr = receipt.date != null
        ? DateFormat('MMM d, y').format(receipt.date!)
        : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: GestureDetector(
        onTap: () async {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ReceiptDetailViewPage(
                receipt: receipt,
                trips: widget.trips,
              )),
            );
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              // Thumbnail
              _buildReceiptThumbnail(receipt, 44),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      receipt.merchant ?? 'Receipt',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: receipt.paymentMethod == 'corporate'
                                ? const Color(0xFF46166B).withOpacity(0.1)
                                : const Color(0xFFE8A824).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            receipt.paymentMethod == 'corporate' ? 'AS Amex' : 'Personal',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: receipt.paymentMethod == 'corporate'
                                  ? const Color(0xFF46166B)
                                  : const Color(0xFFB08D3A),
                            ),
                          ),
                        ),
                      if (receipt.mealType != null) ...[
                        const SizedBox(width: 6),
                        _mealTypeTag(receipt.mealType!),
                      ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFFD1D5DB),
                      ),
                    ),
                  ],
                ),
              ),
              // Amount + chevron
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$${receipt.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade200),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptThumbnail(Receipt receipt, double size) {
    if (receipt.imageUrl != null) {
      return FutureBuilder<String?>(
        future: AuthService.instance.getToken(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return _placeholderThumbnail(size);
          }
          final url = APIService().receiptImageUrl(receipt.id);
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: CachedNetworkImage(
              imageUrl: url,
              httpHeaders: {'Authorization': 'Bearer ${snap.data}'},
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _placeholderIcon(size),
            ),
          );
        },
      );
    }
    return _placeholderThumbnail(size);
  }

  Widget _placeholderThumbnail(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.receipt_long, size: size * 0.45, color: Colors.grey.shade400),
    );
  }

  Widget _placeholderIcon(double size) {
    return Container(
      width: size,
      height: size,
      color: Colors.grey.shade100,
      alignment: Alignment.center,
      child: Icon(Icons.receipt_long, size: size * 0.45, color: Colors.grey.shade400),
    );
  }

  // ─── Month/Year Picker ──────────────────────────────

  Widget _buildMonthYearPicker() {
    final now = DateTime.now();
    const monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 30,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
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
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                  GestureDetector(
                    onTap: () => setState(() => _showPicker = false),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                    ),
                  ),
                ],
              ),
            ),
            // Year selector
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _pickerYear > 2024
                        ? () => setState(() => _pickerYear--)
                        : null,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _pickerYear > 2024 ? Colors.grey.shade100 : Colors.grey.shade50,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.chevron_left,
                        size: 16,
                        color: _pickerYear > 2024 ? Colors.grey.shade600 : Colors.grey.shade200,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 64,
                    child: Text(
                      '$_pickerYear',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: _pickerYear < now.year
                        ? () => setState(() => _pickerYear++)
                        : null,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _pickerYear < now.year ? Colors.grey.shade100 : Colors.grey.shade50,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: _pickerYear < now.year ? Colors.grey.shade600 : Colors.grey.shade200,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Month grid
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.2,
                ),
                itemCount: 12,
                itemBuilder: (context, i) {
                  final monthNum = i + 1;
                  final isFuture = _pickerYear == now.year && monthNum > now.month;
                  final isSelected = monthNum == _selectedMonth && _pickerYear == _selectedYear;

                  return GestureDetector(
                    onTap: isFuture
                        ? null
                        : () => setState(() {
                              _selectedMonth = monthNum;
                              _selectedYear = _pickerYear;
                              _showPicker = false;
                            }),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isFuture
                            ? Colors.grey.shade50
                            : isSelected
                                ? const Color(0xFF111827)
                                : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        monthsShort[i],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isFuture
                              ? Colors.grey.shade200
                              : isSelected
                                  ? Colors.white
                                  : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Detail View ────────────────────────────────────

  Widget _buildDetailView() {
    final receipt = _selectedReceipt!;
    final category = _categoryLabel(receipt);
    final dateStr = receipt.date != null
        ? DateFormat('MMM d, y').format(receipt.date!)
        : 'Unknown';
    final tripName = _tripNameForReceipt(receipt);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Column(
        children: [
          // Header
          Container(
            color: Colors.white,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _selectedReceipt = null),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.arrow_back, size: 16, color: Colors.grey.shade600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Receipt Details',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(height: 1, color: Colors.grey.shade100),

          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                // Receipt Image
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReceiptDetailPage(receipt: receipt),
                      ),
                    );
                  },
                  child: Container(
                    height: 192,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        _buildDetailImage(receipt),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.fullscreen, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
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
                        color: Colors.black.withOpacity(0.04),
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
                                  receipt.merchant ?? 'Receipt',
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
                            '\$${receipt.total.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              category,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Date Card
                _infoCard(
                  icon: Icons.calendar_today,
                  iconBgColor: const Color(0xFF111827),
                  label: 'DATE SCANNED',
                  value: dateStr,
                ),

                const SizedBox(height: 10),

                // Trip Card
                _infoCard(
                  icon: Icons.local_offer,
                  iconBgColor: const Color(0xFFE8A824),
                  label: 'TRIP',
                  value: tripName,
                ),

                // Line items if available
                if (receipt.items.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildLineItems(receipt),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailImage(Receipt receipt) {
    if (receipt.imageUrl == null) {
      return Container(
        color: Colors.grey.shade100,
        alignment: Alignment.center,
        child: Icon(Icons.receipt_long, size: 48, color: Colors.grey.shade300),
      );
    }

    return FutureBuilder<String?>(
      future: AuthService.instance.getToken(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(
            color: Colors.grey.shade100,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF46166B)),
            ),
          );
        }
        final url = APIService().receiptImageUrl(receipt.id);
        return CachedNetworkImage(
          imageUrl: url,
          httpHeaders: {'Authorization': 'Bearer ${snap.data}'},
          fit: BoxFit.cover,
          width: double.infinity,
          errorWidget: (_, __, ___) => Container(
            color: Colors.grey.shade100,
            alignment: Alignment.center,
            child: Icon(Icons.receipt_long, size: 48, color: Colors.grey.shade300),
          ),
        );
      },
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color iconBgColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
              color: iconBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
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
    );
  }

  // ─── Bottom Nav ───────────────────────────────────────

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Home
              _navItem(
                icon: Icons.home_outlined,
                label: 'Home',
                onTap: () => Navigator.pop(context),
              ),
              // Center Scan FAB
              _buildScanFab(),
              // Analytics
              _navItem(
                icon: Icons.bar_chart_rounded,
                label: 'Analytics',
                onTap: () => Navigator.pop(context, 'analytics'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: const Color(0xFFD1D5DB)),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanFab() {
    return GestureDetector(
      onTap: () => Navigator.pop(context, 'scan'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            offset: const Offset(0, -12),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF46166B), Color(0xFF7B3FA0)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF46166B).withOpacity(0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.document_scanner_outlined, size: 22, color: Colors.white),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -8),
            child: Text(
              'Scan',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineItems(Receipt receipt) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ITEMS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Color(0xFF9CA3AF),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          ...receipt.items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF6B7280),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '\$${item.computedTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ],
                ),
              )),
          if (receipt.hasTax) ...[
            Divider(color: Colors.grey.shade100),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Tax',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF6B7280),
                  ),
                ),
                Text(
                  '\$${receipt.effectiveTax.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ],
          Divider(color: Colors.grey.shade100),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              Text(
                '\$${receipt.total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
