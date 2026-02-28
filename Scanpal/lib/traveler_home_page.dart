import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/user.dart';
import 'models/trip.dart';
import 'receipt.dart';
import 'api.dart';
import 'services/analytics_service.dart';
import 'auth_service.dart';
import 'login_page.dart';
import 'trip_detail_page.dart';
import 'analytics_page.dart';

class TravelerHomePage extends StatefulWidget {
  final AppUser user;

  const TravelerHomePage({super.key, required this.user});

  @override
  State<TravelerHomePage> createState() => _TravelerHomePageState();
}

class _TravelerHomePageState extends State<TravelerHomePage> {
  final _api = APIService();
  List<Trip> _trips = [];
  AnalyticsService? _analyticsService;
  bool _loading = true;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.fetchTrips(sync: true),
        _api.fetchReceipts(),
      ]);
      if (mounted) {
        final trips = results[0] as List<Trip>;
        final receipts = results[1] as List<Receipt>;
        setState(() {
          _trips = trips;
          _analyticsService = AnalyticsService(receipts: receipts, trips: trips);
        });
      }
    } catch (e) {
      debugPrint('Failed to load data: $e');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _showCreateTripDialog() async {
    final purposeCtrl = TextEditingController();
    final destinationCtrl = TextEditingController();
    DateTime? departureDate;
    DateTime? returnDate;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('New Trip'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: purposeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Trip Name *',
                    hintText: 'e.g., Conference in NYC',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: destinationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Destination *',
                    hintText: 'e.g., New York, USA',
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    departureDate != null
                        ? 'Departure: ${DateFormat('MMM d, y').format(departureDate!)}'
                        : 'Departure Date (optional)',
                    style: TextStyle(
                      fontSize: 14,
                      color: departureDate != null ? Colors.black87 : Colors.grey,
                    ),
                  ),
                  trailing: const Icon(Icons.calendar_today, size: 20),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setDialogState(() => departureDate = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    returnDate != null
                        ? 'Return: ${DateFormat('MMM d, y').format(returnDate!)}'
                        : 'Return Date (optional)',
                    style: TextStyle(
                      fontSize: 14,
                      color: returnDate != null ? Colors.black87 : Colors.grey,
                    ),
                  ),
                  trailing: const Icon(Icons.calendar_today, size: 20),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: departureDate ?? DateTime.now(),
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setDialogState(() => returnDate = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    final purpose = purposeCtrl.text.trim();
    final dest = destinationCtrl.text.trim();

    if (purpose.isEmpty || dest.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip name and destination are required')),
      );
      return;
    }

    try {
      setState(() => _loading = true);
      final trip = await _api.createTrip(
        tripPurpose: purpose,
        destination: dest,
        departureDate: departureDate,
        returnDate: returnDate,
      );
      if (!mounted) return;
      setState(() {
        _trips.insert(0, trip);
        _loading = false;
      });
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TripDetailPage(trip: trip)),
      );
      _loadData(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create trip: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
      floatingActionButton: _tabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _showCreateTripDialog,
              backgroundColor: const Color(0xFF1565C0),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('New Trip', style: TextStyle(color: Colors.white)),
            )
          : null,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          _tabIndex == 0 ? 'ScanPal' : 'Analytics',
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
      body: _tabIndex == 0
          ? _buildTripsTab()
          : AnalyticsPage(
              analyticsService: _analyticsService,
              onTripTap: () => _loadData(silent: true),
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
        selectedItemColor: const Color(0xFF1565C0),
        unselectedItemColor: const Color(0xFF94A3B8),
        backgroundColor: Colors.white,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.flight),
            label: 'Trips',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_rounded),
            label: 'Analytics',
          ),
        ],
      ),
    );
  }

  Widget _buildTripsTab() {
    final active = _trips.where((t) => t.isActive).toList();
    final upcoming = _trips.where((t) => t.isUpcoming).toList();
    final past = _trips.where((t) => t.isPast).toList();
    final unscheduled = _trips.where((t) => t.isUnscheduled).toList();

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(silent: true),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Greeting
          Text(
            'Welcome, ${widget.user.name}',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          if (widget.user.department != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.user.department!,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF64748B),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Active Trips
          if (active.isNotEmpty) ...[
            _sectionHeader('Active Trip'),
            ...active.map((t) => _tripCard(t, isActive: true)),
            const SizedBox(height: 20),
          ],

          // Upcoming Trips
          if (upcoming.isNotEmpty) ...[
            _sectionHeader('Upcoming Trips'),
            ...upcoming.map((t) => _tripCard(t)),
            const SizedBox(height: 20),
          ],

          // Past Trips
          if (past.isNotEmpty) ...[
            _sectionHeader('Past Trips'),
            ...past.map((t) => _tripCard(t, dimmed: true)),
            const SizedBox(height: 20),
          ],

          // Other Trips (no dates set)
          if (unscheduled.isNotEmpty) ...[
            _sectionHeader('Other Trips'),
            ...unscheduled.map((t) => _tripCard(t)),
          ],

          // Empty state
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
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to create your first trip',
                    style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Color(0xFF334155),
        ),
      ),
    );
  }

  Future<void> _deleteTrip(Trip trip) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Trip'),
        content: Text('Delete "${trip.displayTitle}" and all its receipts? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final success = await _api.deleteTrip(trip.id);
    if (!mounted) return;
    if (success) {
      setState(() => _trips.removeWhere((t) => t.id == trip.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip deleted')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete trip'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _tripCard(Trip trip, {bool isActive = false, bool dimmed = false}) {
    final color = isActive ? const Color(0xFF1565C0) : const Color(0xFF475569);

    return Dismissible(
      key: Key(trip.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        await _deleteTrip(trip);
        return false;
      },
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isActive ? Border.all(color: const Color(0xFF1565C0), width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
                            ? const Color(0xFF1565C0).withOpacity(0.1)
                            : Colors.grey.withOpacity(0.1),
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
                '\$${trip.totalExpenses.toStringAsFixed(2)}',
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
