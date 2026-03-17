import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/user.dart';
import 'models/trip.dart';
import 'receipt.dart';
import 'api.dart';
import 'auth_service.dart';
import 'login_page.dart';
import 'trip_detail_page.dart';
import 'admin_analytics_page.dart';
import 'admin_receipts_page.dart';

class AdminHomePage extends StatefulWidget {
  final AppUser user;

  const AdminHomePage({super.key, required this.user});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  final _api = APIService();
  List<Trip> _trips = [];
  bool _loading = true;
  Timer? _refreshTimer;

  // Tab state
  int _tabIndex = 0;

  // Department filter
  String? _selectedDepartment;

  // Receipts data (loaded lazily)
  List<Receipt> _receipts = [];
  bool _receiptsLoading = false;
  bool _receiptsLoaded = false;

  // Analytics data (loaded lazily)
  Map<String, dynamic>? _orgAnalytics;
  List<Map<String, dynamic>> _departmentStats = [];
  bool _analyticsLoading = false;
  bool _analyticsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadData(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  List<String> get _departments {
    final depts = _trips
        .where((t) => t.department != null && t.department!.isNotEmpty)
        .map((t) => t.department!)
        .toSet()
        .toList()
      ..sort();
    return depts;
  }

  List<Trip> get _filteredTrips {
    if (_selectedDepartment == null) return _trips;
    return _trips.where((t) => t.department == _selectedDepartment).toList();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final trips = await _api.fetchTrips(sync: true);
      if (mounted) {
        setState(() => _trips = trips);
      }
    } catch (e) {
      debugPrint('Failed to load admin data: $e');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _loadReceipts() async {
    if (_receiptsLoaded) return;
    setState(() => _receiptsLoading = true);
    try {
      final receipts = await _api.fetchReceipts();
      if (mounted) {
        setState(() {
          _receipts = receipts;
          _receiptsLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('Failed to load receipts: $e');
    } finally {
      if (mounted) setState(() => _receiptsLoading = false);
    }
  }

  Future<void> _refreshReceipts() async {
    _receiptsLoaded = false;
    await _loadReceipts();
  }

  Future<void> _loadAnalytics() async {
    if (_analyticsLoaded) return;
    setState(() => _analyticsLoading = true);
    try {
      final results = await Future.wait([
        _api.fetchOrgAnalytics(),
        _api.fetchDepartments(),
      ]);
      if (mounted) {
        setState(() {
          _orgAnalytics = results[0] as Map<String, dynamic>;
          _departmentStats = results[1] as List<Map<String, dynamic>>;
          _analyticsLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('Failed to load analytics: $e');
    } finally {
      if (mounted) setState(() => _analyticsLoading = false);
    }
  }

  Future<void> _refreshAnalytics() async {
    _analyticsLoaded = false;
    await _loadAnalytics();
  }

  Future<void> _logout() async {
    await AuthService.instance.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          ['ScanPal Admin', 'Receipts', 'Analytics'][_tabIndex],
          style: const TextStyle(
            color: Color(0xFF1565C0),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF1565C0)),
            onPressed: _logout,
          ),
        ],
      ),
      body: _buildTabBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) {
          setState(() => _tabIndex = i);
          if (i == 1) _loadReceipts();
          if (i == 2) _loadAnalytics();
        },
        selectedItemColor: const Color(0xFF1565C0),
        unselectedItemColor: const Color(0xFF94A3B8),
        backgroundColor: Colors.white,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.flight), label: 'Trips'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Receipts'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'Analytics'),
        ],
      ),
    );
  }

  Widget _buildTabBody() {
    switch (_tabIndex) {
      case 1:
        return AdminReceiptsPage(
          receipts: _receipts,
          trips: _trips,
          isLoading: _receiptsLoading,
          onRefresh: _refreshReceipts,
        );
      case 2:
        return AdminAnalyticsPage(
          orgAnalytics: _orgAnalytics,
          departments: _departmentStats,
          isLoading: _analyticsLoading,
          onRefresh: _refreshAnalytics,
          onDepartmentTap: (dept) {
            setState(() {
              _selectedDepartment = dept;
              _tabIndex = 0;
            });
          },
        );
      default:
        return _loading
            ? const Center(child: CircularProgressIndicator())
            : _buildTripsView();
    }
  }

  Widget _buildDepartmentFilter() {
    final depts = _departments;
    if (depts.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('All'),
              selected: _selectedDepartment == null,
              onSelected: (_) => setState(() => _selectedDepartment = null),
              selectedColor: const Color(0xFF1565C0),
              backgroundColor: const Color(0xFF0891B2).withValues(alpha: 0.1),
              side: BorderSide(
                color: _selectedDepartment == null
                    ? Colors.transparent
                    : const Color(0xFF0891B2).withValues(alpha: 0.3),
              ),
              labelStyle: TextStyle(
                color: _selectedDepartment == null ? Colors.white : const Color(0xFF0891B2),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          ...depts.map((dept) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(dept),
              selected: _selectedDepartment == dept,
              onSelected: (_) => setState(() => _selectedDepartment = dept),
              selectedColor: const Color(0xFF1565C0),
              backgroundColor: const Color(0xFF0891B2).withValues(alpha: 0.1),
              side: BorderSide(
                color: _selectedDepartment == dept
                    ? Colors.transparent
                    : const Color(0xFF0891B2).withValues(alpha: 0.3),
              ),
              labelStyle: TextStyle(
                color: _selectedDepartment == dept ? Colors.white : const Color(0xFF0891B2),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildTripsView() {
    final filtered = _filteredTrips;
    final active = filtered.where((t) => t.isActive).toList();
    final upcoming = filtered.where((t) => t.isUpcoming).toList();
    final unscheduled = filtered.where((t) => t.isUnscheduled).toList();

    return RefreshIndicator(
      onRefresh: () => _loadData(silent: true),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Welcome, ${widget.user.name}',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Business Office Admin',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedDepartment != null
                ? '$_selectedDepartment: ${filtered.length} trips (${_trips.length} total)'
                : '${_trips.length} total trips across all travelers',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 16),

          _buildDepartmentFilter(),
          if (_departments.isNotEmpty) const SizedBox(height: 16),

          if (active.isNotEmpty) ...[
            _sectionHeader('Active Trips', active.length),
            ...active.map((t) => _tripCard(t, isActive: true)),
            const SizedBox(height: 20),
          ],

          if (upcoming.isNotEmpty) ...[
            _sectionHeader('Upcoming Trips', upcoming.length),
            ...upcoming.map((t) => _tripCard(t)),
            const SizedBox(height: 20),
          ],

          if (unscheduled.isNotEmpty) ...[
            _sectionHeader('Unscheduled Trips', unscheduled.length),
            ...unscheduled.map((t) => _tripCard(t)),
          ],

          if (filtered.isEmpty && _trips.isNotEmpty)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 80),
                  Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No trips in ${_selectedDepartment ?? "this department"}',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

          if (_trips.isEmpty)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 80),
                  Icon(Icons.flight_takeoff, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No trips found',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1565C0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tripCard(Trip trip, {bool isActive = false, bool dimmed = false}) {
    final color = isActive ? const Color(0xFF1565C0) : const Color(0xFF475569);
    final currency = NumberFormat.simpleCurrency();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isActive ? Border.all(color: const Color(0xFF1565C0), width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TripDetailPage(trip: trip)),
          );
          _loadData(silent: true);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Traveler name & department badge
              if (trip.travelerName.isNotEmpty || (trip.department != null && trip.department!.isNotEmpty))
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (trip.travelerName.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person, size: 14, color: Color(0xFF7C3AED)),
                            const SizedBox(width: 4),
                            Text(
                              trip.travelerName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF7C3AED),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (trip.department != null && trip.department!.isNotEmpty)
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
                              trip.department!,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0891B2),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              if (trip.travelerName.isNotEmpty || (trip.department != null && trip.department!.isNotEmpty))
                const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      trip.displayTitle,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: dimmed ? Colors.grey : color,
                      ),
                    ),
                  ),
                  if (trip.status != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF1565C0).withValues(alpha: 0.1)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        trip.status!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isActive ? const Color(0xFF1565C0) : Colors.grey,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (trip.destination != null && trip.destination!.isNotEmpty)
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      trip.destination!,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              if (trip.departureDate != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      _formatDateRange(trip.departureDate, trip.returnDate),
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text(
                currency.format(trip.totalExpenses),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: dimmed ? Colors.grey : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateRange(DateTime? start, DateTime? end) {
    if (start == null) return '';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final s = '${months[start.month - 1]} ${start.day}, ${start.year}';
    if (end == null || end == start) return s;
    final e = '${months[end.month - 1]} ${end.day}, ${end.year}';
    return '$s - $e';
  }
}
