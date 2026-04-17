import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/trip.dart';
import 'trip_detail_page.dart';
import 'add_trip_page.dart';
import 'analytics_page.dart';
import 'services/analytics_service.dart';
import 'api.dart';
import 'departments.dart';

class TripsPage extends StatefulWidget {
  final List<Trip> trips;
  final VoidCallback? onRefresh;
  final AnalyticsService? analyticsService;
  final bool showDepartmentFilter;

  const TripsPage({
    super.key,
    required this.trips,
    this.onRefresh,
    this.analyticsService,
    this.showDepartmentFilter = false,
  });

  @override
  State<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends State<TripsPage> {
  late int _selectedMonth;
  late int _selectedYear;
  String _activeFilter = 'All';
  bool _showPicker = false;
  int _pickerYear = 2026;
  String? _selectedDepartment;
  List<Department> _departments = [];

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const _monthsShort = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _statusFilters = ['All', 'Active', 'Upcoming', 'Completed'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = now.month - 1;
    _selectedYear = now.year;
    _pickerYear = now.year;
    _fetchDepartments();
  }

  Future<void> _fetchDepartments() async {
    try {
      final depts = await APIService().fetchDepartmentObjects();
      if (mounted) setState(() => _departments = depts);
    } catch (_) {}
  }

  String _tripStatus(Trip trip) {
    if (trip.isActive) return 'active';
    if (trip.isUpcoming) return 'upcoming';
    if (trip.isPast) return 'completed';
    return 'active';
  }

  List<String> get _availableDepartments {
    if (_departments.isNotEmpty) return _departments.map((d) => d.name).toList();
    // Fallback: derive from trips if API hasn't responded yet
    return widget.trips
        .map((t) => t.department)
        .whereType<String>()
        .where((d) => d.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  List<Trip> get _filteredTrips {
    return widget.trips.where((t) {
      if (t.departureDate != null) {
        if (t.departureDate!.month - 1 != _selectedMonth ||
            t.departureDate!.year != _selectedYear) {
          return false;
        }
      } else {
        return false;
      }
      if (_activeFilter != 'All') {
        final status = _tripStatus(t);
        if (status != _activeFilter.toLowerCase()) return false;
      }
      if (_selectedDepartment != null && t.department != _selectedDepartment) {
        return false;
      }
      return true;
    }).toList();
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
    if (_selectedYear == 2030 && _selectedMonth == 11) return;
    setState(() {
      if (_selectedMonth == 11) {
        _selectedMonth = 0;
        _selectedYear++;
      } else {
        _selectedMonth++;
      }
    });
  }

  bool get _isAtLastMonth {
    return _selectedYear == 2030 && _selectedMonth == 11;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTrips;
    final currency = NumberFormat.simpleCurrency();

    double monthSpent = 0;
    for (final t in filtered) {
      monthSpent += t.totalExpenses;
    }

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
                    _buildMonthCard(filtered, currency, monthSpent),
                    _buildFilterButton(),
                    if (filtered.isEmpty)
                      _buildEmptyState()
                    else
                      ...filtered.map((trip) => _buildTripCard(trip, currency)),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ],
          ),
          // Add New Trip floating pill
          Positioned(
            right: 20,
            bottom: 24,
            child: GestureDetector(
              onTap: () async {
                final trip = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddTripPage()),
                );
                if (trip != null) widget.onRefresh?.call();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF46166B),
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF46166B).withOpacity(0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add, size: 14, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'Add New Trip',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Month/year picker overlay
          if (_showPicker) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showPicker = false),
                child: Container(color: Colors.black.withOpacity(0.3)),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              top: MediaQuery.of(context).padding.top + 120,
              child: _buildMonthYearPicker(),
            ),
          ],
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ─── Header ──────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Color(0xFF4B5563)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'My Trips',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    Text(
                      '${widget.trips.length} total trips',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.grey.shade500,
                      ),
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

  // ─── Month Card (picker + summary) ──────────────────

  Widget _buildMonthCard(List<Trip> filtered, NumberFormat currency, double monthSpent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFDF6E3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8A824).withOpacity(0.2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Gradient top bar
            Container(
              height: 3,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF46166B), Color(0xFFE8A824), Color(0xFF46166B)],
                ),
              ),
            ),
            // Month picker row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: _goToPrevMonth,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.chevron_left, size: 20, color: Color(0xFF4B5563)),
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
                            Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Text(
                              _months[_selectedMonth],
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () => setState(() {
                                _selectedYear--;
                                _pickerYear = _selectedYear;
                              }),
                              behavior: HitTestBehavior.opaque,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                child: Icon(Icons.chevron_left, size: 18, color: Color(0xFFD49B1F)),
                              ),
                            ),
                            Text(
                              '$_selectedYear',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFD49B1F),
                              ),
                            ),
                            GestureDetector(
                              onTap: _selectedYear >= 2030
                                  ? null
                                  : () => setState(() {
                                        _selectedYear++;
                                        _pickerYear = _selectedYear;
                                      }),
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                child: Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: _selectedYear >= 2030 ? Colors.grey.shade300 : const Color(0xFFD49B1F),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _isAtLastMonth ? null : _goToNextMonth,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(_isAtLastMonth ? 0.3 : 0.7),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: _isAtLastMonth ? Colors.grey.shade300 : const Color(0xFF4B5563),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Summary row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFFD49B1F),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${filtered.length} trip${filtered.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFB8860B),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    currency.format(monthSpent),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
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

  // ─── Month/Year Picker Overlay ──────────────────────

  Widget _buildMonthYearPicker() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _pickerYear--),
                  child: Icon(Icons.chevron_left, size: 22, color: Colors.grey.shade600),
                ),
                Text(
                  '$_pickerYear',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
                GestureDetector(
                  onTap: _pickerYear >= 2030
                      ? null
                      : () => setState(() => _pickerYear++),
                  child: Icon(
                    Icons.chevron_right,
                    size: 22,
                    color: _pickerYear >= 2030 ? Colors.grey.shade300 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
              itemBuilder: (_, i) {
                final isSelected = i == _selectedMonth && _pickerYear == _selectedYear;
                final isFuture = _pickerYear == 2030 && i > 11; // all months available up to 2030
                return GestureDetector(
                  onTap: isFuture
                      ? null
                      : () => setState(() {
                            _selectedMonth = i;
                            _selectedYear = _pickerYear;
                            _showPicker = false;
                          }),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF46166B)
                          : isFuture
                              ? Colors.grey.shade50
                              : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _monthsShort[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : isFuture
                                ? Colors.grey.shade300
                                : Colors.grey.shade700,
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
  }

  // ─── Filter Button + Sheet ──────────────────────────

  int get _activeFilterCount {
    int count = 0;
    if (_activeFilter != 'All') count++;
    if (_selectedDepartment != null) count++;
    return count;
  }

  Widget _buildFilterButton() {
    final count = _activeFilterCount;
    final hasFilter = count > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: GestureDetector(
        onTap: _showFilterSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: hasFilter ? const Color(0xFF46166B) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: hasFilter ? null : Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.filter_list,
                size: 14,
                color: hasFilter ? Colors.white : const Color(0xFF6B7280),
              ),
              const SizedBox(width: 8),
              Text(
                'Filter',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: hasFilter ? Colors.white : const Color(0xFF6B7280),
                ),
              ),
              if (hasFilter) ...[
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
                    '$count',
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
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF46166B) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(20),
          border: selected ? null : Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }

  void _showFilterSheet() {
    String tempDept = _selectedDepartment ?? 'All Departments';
    String tempStatus = _activeFilter;
    final allDepts = _availableDepartments;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.70,
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
                        'Filter Trips',
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
                // Filter content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Department section (only if showDepartmentFilter)
                        if (widget.showDepartmentFilter) ...[
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
                              _filterChip('All', tempDept == 'All Departments', () => setSheetState(() => tempDept = 'All Departments')),
                              ..._departments.map((dept) {
                                final selected = tempDept == dept.name;
                                return _filterChip(dept.name, selected, () => setSheetState(() => tempDept = dept.name));
                              }),
                              ...allDepts.where((d) => !_departments.any((dept) => dept.name == d)).map((d) {
                                final selected = tempDept == d;
                                return _filterChip(d, selected, () => setSheetState(() => tempDept = d));
                              }),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                        // Trip Status section
                        const Text(
                          'TRIP STATUS',
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
                          children: _statusFilters.map((filter) {
                            final selected = tempStatus == filter;
                            return _filterChip(filter, selected, () => setSheetState(() => tempStatus = filter));
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
                                  tempStatus = 'All';
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
                                    _selectedDepartment = tempDept == 'All Departments' ? null : tempDept;
                                    _activeFilter = tempStatus;
                                  });
                                  Navigator.pop(ctx);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF46166B),
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

  // ─── Empty State ────────────────────────────────────

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
            child: Icon(Icons.flight_outlined, size: 28, color: Colors.grey.shade300),
          ),
          const SizedBox(height: 12),
          Text(
            'No trips this month',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try selecting a different month',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Trip Card ──────────────────────────────────────

  static const _thumbGradients = [
    [Color(0xFF1E3A5F), Color(0xFF4A7FB5)],
    [Color(0xFF0D7377), Color(0xFF14A3A8)],
    [Color(0xFF46166B), Color(0xFF7B3FA0)],
    [Color(0xFFB8860B), Color(0xFFDAA520)],
    [Color(0xFF8B2252), Color(0xFFCD6889)],
    [Color(0xFF2E8B57), Color(0xFF66CDAA)],
    [Color(0xFF4A3728), Color(0xFF8B6914)],
    [Color(0xFF5B2C6F), Color(0xFFA569BD)],
  ];

  Widget _buildTripCard(Trip trip, NumberFormat currency) {
    final status = _tripStatus(trip);
    final dateFormat = DateFormat('MMM d, yyyy');
    String dateRange = '';
    if (trip.departureDate != null && trip.returnDate != null) {
      dateRange = '${dateFormat.format(trip.departureDate!)} — ${dateFormat.format(trip.returnDate!)}';
    } else if (trip.departureDate != null) {
      dateRange = dateFormat.format(trip.departureDate!);
    }

    // Status config
    Color statusDotColor;
    Color statusTextColor;
    Color statusBgColor;
    String statusLabel;
    switch (status) {
      case 'active':
        statusDotColor = const Color(0xFF34D399);
        statusTextColor = const Color(0xFF059669);
        statusBgColor = const Color(0xFFECFDF5);
        statusLabel = 'Active';
        break;
      case 'upcoming':
        statusDotColor = const Color(0xFF60A5FA);
        statusTextColor = const Color(0xFF2563EB);
        statusBgColor = const Color(0xFFEFF6FF);
        statusLabel = 'Upcoming';
        break;
      default:
        statusDotColor = const Color(0xFF9CA3AF);
        statusTextColor = const Color(0xFF6B7280);
        statusBgColor = const Color(0xFFF3F4F6);
        statusLabel = 'Completed';
    }

    // Thumbnail
    final dest = trip.destination ?? trip.tripPurpose ?? '';
    final hash = dest.toLowerCase().hashCode.abs();
    final colors = _thumbGradients[hash % _thumbGradients.length];
    final initial = dest.isNotEmpty ? dest[0].toUpperCase() : '✈';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TripDetailPage(trip: trip)),
          );
          widget.onRefresh?.call();
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
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Trip image
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: colors[0].withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: trip.coverImageUrl != null
                    ? Image.network(
                        trip.coverImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _thumbFallback(colors, initial),
                      )
                    : _thumbFallback(colors, initial),
              ),
              const SizedBox(width: 14),
              // Trip info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title + amount
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            trip.displayTitle,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2937),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          currency.format(trip.totalExpenses),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    // Status badge + destination
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusBgColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: statusDotColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                statusLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: statusTextColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (trip.destination != null) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.location_on_outlined, size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              trip.destination!,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (dateRange.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            dateRange,
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                          ),
                          Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade300),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbFallback(List<Color> colors, String initial) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }

  // ─── Bottom Nav ─────────────────────────────────────

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
              GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 56,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.home_outlined, size: 22, color: Colors.grey.shade300),
                      const SizedBox(height: 2),
                      Text(
                        'Home',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Scan FAB
              GestureDetector(
                onTap: () => Navigator.pop(context, 'scan'),
                behavior: HitTestBehavior.opaque,
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
              ),
              // Analytics
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AnalyticsPage(
                        analyticsService: widget.analyticsService,
                      ),
                    ),
                  );
                },
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 56,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bar_chart_rounded, size: 22, color: Colors.grey.shade300),
                      const SizedBox(height: 2),
                      Text(
                        'Analytics',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
