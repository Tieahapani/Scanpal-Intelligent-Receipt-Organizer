import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'models/user.dart';
import 'models/trip.dart';
import 'receipt.dart';
import 'api.dart';
import 'services/analytics_service.dart';
import 'auth_service.dart';
import 'login_page.dart';
import 'trip_detail_page.dart';
// import 'analytics_page.dart'; // kept — analytics page still exists, just hidden from nav
import 'receipts_page.dart';
import 'receipt_detail_view_page.dart';
import 'alerts_page.dart';
import 'trips_page.dart';
import 'add_trip_page.dart';
import 'profile_page.dart';
import 'settings_page.dart';

class TravelerHomePage extends StatefulWidget {
  final AppUser user;

  const TravelerHomePage({super.key, required this.user});

  @override
  State<TravelerHomePage> createState() => _TravelerHomePageState();
}

class _TravelerHomePageState extends State<TravelerHomePage> {
  final _api = APIService();
  List<Trip> _trips = [];
  List<Receipt> _receipts = [];
  AnalyticsService? _analyticsService;
  bool _loading = true;
  bool _dropdownOpen = false;
  bool _showScanMenu = false;
  String _paymentMethod = 'personal';
  int _avatarVersion = 0;
  Timer? _refreshTimer;

  // Upload progress state
  bool _isUploading = false;
  bool _uploadComplete = false;
  double _uploadProgress = 0.0;
  String _uploadLabel = '';       // "Scanning Receipt..." or "Uploading Receipt..."
  String _completeLabel = '';     // "Scan Complete" or "Upload Complete"
  String _uploadPaymentLabel = '';
  Timer? _progressTimer;

  // Cached backend alerts
  List<Map<String, dynamic>> _cachedAlerts = [];
  int get _backendAlertCount => _cachedAlerts.where((a) => a['status'] == 'inbox').length;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadAlerts();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadData(silent: true);
      _loadAlerts();
    });
  }

  Future<void> _loadAlerts() async {
    try {
      final alerts = await _api.fetchAlerts();
      if (mounted) setState(() => _cachedAlerts = alerts);
    } catch (_) {}
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _progressTimer?.cancel();
    super.dispose();
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
          _receipts = receipts;
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
    final trip = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddTripPage()),
    );
    if (trip != null && mounted) {
      setState(() => _trips.insert(0, trip));
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TripDetailPage(trip: trip)),
      );
      _loadData(silent: true);
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



  String get _userInitials {
    final parts = widget.user.name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return widget.user.name.isNotEmpty ? widget.user.name[0].toUpperCase() : '?';
  }

  Widget _buildAvatar(double size) {
    return FutureBuilder<AppUser?>(
      future: AuthService.instance.getUser(),
      builder: (context, userSnap) {
        final user = userSnap.data ?? widget.user;
        final hasImage = user.profileImage != null && user.profileImage!.isNotEmpty;
        if (!hasImage) return _initialsAvatar(size);
        return FutureBuilder<String?>(
          future: AuthService.instance.getToken(),
          builder: (context, tokenSnap) {
            if (!tokenSnap.hasData) return _initialsAvatar(size);
            return Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              clipBehavior: Clip.antiAlias,
              child: Image.network(
                '${_api.profileImageUrl()}?v=$_avatarVersion',
                headers: {'Authorization': 'Bearer ${tokenSnap.data}'},
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _initialsAvatar(size),
              ),
            );
          },
        );
      },
    );
  }

  Widget _initialsAvatar(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF46166B), Color(0xFF7B3FA0)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _userInitials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.33,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  double get _currentMonthSpending {
    final now = DateTime.now();
    double total = 0;
    for (final t in _trips) {
      final d = t.departureDate;
      if (d != null && d.month == now.month && d.year == now.year) {
        total += t.totalExpenses;
      }
    }
    return total;
  }

  double get _previousMonthSpending {
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1);
    double total = 0;
    for (final t in _trips) {
      final d = t.departureDate;
      if (d != null && d.month == prev.month && d.year == prev.year) {
        total += t.totalExpenses;
      }
    }
    return total;
  }

  double? get _monthOverMonthChange {
    final current = _currentMonthSpending;
    final prev = _previousMonthSpending;
    if (prev == 0 || current == 0) return null;
    return ((current - prev) / prev) * 100;
  }

  String get _currentMonthLabel {
    return DateFormat('MMMM yyyy').format(DateTime.now());
  }

  int get _alertCount => _backendAlertCount;

  Future<void> _handleScan(ImageSource source) async {
    setState(() => _showScanMenu = false);
    if (_trips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a trip first before scanning receipts')),
      );
      return;
    }

    // 1. Pick trip
    Trip target;
    if (_trips.length == 1) {
      target = _trips.first;
    } else {
      final picked = await _pickTrip(source: source);
      if (picked == null) return;
      target = picked;
    }

    // 2. Open camera or gallery
    if (!mounted) return;
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: source,
      imageQuality: 85,
    );
    if (photo == null) return; // user cancelled

    // 3. Upload receipt with progress overlay
    if (!mounted) return;
    final isCamera = source == ImageSource.camera;
    _startUploadProgress(isCamera: isCamera);

    try {
      final result = await _api.uploadReceipt(
        File(photo.path),
        tripId: target.id,
        paymentMethod: _paymentMethod,
      );
      if (!mounted) return;

      // Show complete state
      _progressTimer?.cancel();
      setState(() {
        _uploadProgress = 1.0;
        _uploadComplete = true;
      });

      // Update local data
      setState(() {
        _receipts.insert(0, result.receipt);
        if (result.trip != null) {
          final idx = _trips.indexWhere((t) => t.id == result.trip!.id);
          if (idx >= 0) _trips[idx] = result.trip!;
        }
        _analyticsService = AnalyticsService(receipts: _receipts, trips: _trips);
      });

      // Auto-dismiss after 2 seconds, then show meal type picker if Meals
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _isUploading = false);
          final cat = (result.receipt.travelCategory ?? result.receipt.category ?? '').toLowerCase();
          if (cat == 'meals') {
            _showMealTypePicker(result.receipt);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      _progressTimer?.cancel();
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showMealTypePicker(Receipt receipt) async {
    const mealTypes = [
      {'key': 'breakfast', 'label': 'Breakfast', 'icon': Icons.free_breakfast_outlined, 'color': Color(0xFFF59E0B)},
      {'key': 'lunch', 'label': 'Lunch', 'icon': Icons.lunch_dining_outlined, 'color': Color(0xFF3B82F6)},
      {'key': 'dinner', 'label': 'Dinner', 'icon': Icons.dinner_dining_outlined, 'color': Color(0xFF8B5CF6)},
      {'key': 'incidentals', 'label': 'Incidentals', 'icon': Icons.receipt_long_outlined, 'color': Color(0xFF6B7280)},
      {'key': 'hospitality', 'label': 'Hospitality', 'icon': Icons.local_bar_outlined, 'color': Color(0xFFE8A824)},
    ];

    String? selected;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Icon circle
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF46166B).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.restaurant_menu, color: Color(0xFF46166B), size: 28),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'What type of meal?',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Help us categorize your meal expense',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 20),
                  // Meal type chips
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: mealTypes.map((mt) {
                      final isSelected = selected == mt['key'];
                      final color = mt['color'] as Color;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selected = mt['key'] as String),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? color.withOpacity(0.15) : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? color : Colors.grey.shade200,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(mt['icon'] as IconData, size: 20, color: isSelected ? color : Colors.grey.shade400),
                              const SizedBox(width: 8),
                              Text(
                                mt['label'] as String,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  color: isSelected ? color : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  // Confirm button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: selected != null ? () => Navigator.pop(ctx) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF46166B),
                        disabledBackgroundColor: Colors.grey.shade200,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Text(
                        'Confirm',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: selected != null ? Colors.white : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Skip button
                  TextButton(
                    onPressed: () {
                      selected = null;
                      Navigator.pop(ctx);
                    },
                    child: Text(
                      'Skip for now',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (selected == null || !mounted) return;

    // Save meal type to backend
    try {
      final updated = await _api.updateMealType(receipt.id, selected!);
      if (mounted) {
        setState(() {
          final idx = _receipts.indexWhere((r) => r.id == receipt.id);
          if (idx >= 0) _receipts[idx] = updated;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save meal type: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _startUploadProgress({required bool isCamera}) {
    setState(() {
      _isUploading = true;
      _uploadComplete = false;
      _uploadProgress = 0.0;
      _uploadLabel = isCamera ? 'Scanning Receipt...' : 'Uploading Receipt...';
      _completeLabel = isCamera ? 'Scan Complete' : 'Upload Complete';
      _uploadPaymentLabel = _paymentMethod == 'corporate' ? 'AS Amex' : 'Personal';
    });

    // Simulate progress up to 90% over ~4 seconds
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        if (_uploadProgress < 0.9) {
          _uploadProgress += 0.02 + (0.9 - _uploadProgress) * 0.01;
        } else {
          timer.cancel();
        }
      });
    });
  }

  Widget _buildUploadOverlay() {
    final paymentColor = _uploadPaymentLabel == 'AS Amex'
        ? const Color(0xFF46166B)
        : const Color(0xFFE8A824);

    return Positioned(
      left: 16,
      right: 16,
      bottom: 100,
      child: AnimatedOpacity(
        opacity: _isUploading ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Gradient progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 4,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final fullWidth = constraints.maxWidth;
                      final fillWidth = fullWidth * _uploadProgress;
                      return Stack(
                        children: [
                          Container(color: Colors.grey.shade200),
                          Container(
                            width: fillWidth,
                            decoration: BoxDecoration(
                              gradient: _uploadComplete
                                  ? const LinearGradient(
                                      colors: [Color(0xFFE8A824), Color(0xFFE8A824)],
                                    )
                                  : const LinearGradient(
                                      colors: [Color(0xFF46166B), Color(0xFFE8A824)],
                                    ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Content row
              Row(
                children: [
                  // Icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _uploadComplete
                          ? const Color(0xFFE8A824).withOpacity(0.12)
                          : const Color(0xFF46166B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _uploadComplete
                          ? Icons.check_circle_outline
                          : Icons.document_scanner_outlined,
                      size: 22,
                      color: _uploadComplete
                          ? const Color(0xFFE8A824)
                          : const Color(0xFF46166B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _uploadComplete ? _completeLabel : _uploadLabel,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: paymentColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _uploadComplete
                                  ? '$_uploadPaymentLabel · Saved'
                                  : _uploadPaymentLabel,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Percentage or checkmark
                  if (_uploadComplete)
                    Icon(
                      Icons.check_circle_outline,
                      size: 28,
                      color: const Color(0xFFE8A824),
                    )
                  else
                    Text(
                      '${(_uploadProgress * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400,
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

  /// Fuzzy-match score: higher = better match. Returns 0 if no match.
  int _fuzzyScore(String query, Trip trip) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return 1; // everything matches empty query

    final title = trip.displayTitle.toLowerCase();
    final dest = (trip.destination ?? '').toLowerCase();

    int best = 0;

    for (final field in [title, dest]) {
      if (field.isEmpty) continue;
      // Exact match
      if (field == q) { best = 100; continue; }
      // Starts with query
      if (field.startsWith(q)) { best = best < 90 ? 90 : best; continue; }
      // Word-start match (e.g. "nyc" matches "NYC Conference")
      final words = field.split(RegExp(r'[\s,\-]+'));
      for (final w in words) {
        if (w.startsWith(q)) { best = best < 80 ? 80 : best; break; }
      }
      // Contains substring
      if (field.contains(q)) { best = best < 60 ? 60 : best; continue; }
      // Initials match (e.g. "nc" matches "NYC Conference")
      final initials = words.where((w) => w.isNotEmpty).map((w) => w[0]).join();
      if (initials.contains(q)) { best = best < 50 ? 50 : best; continue; }
    }

    return best;
  }

  Future<Trip?> _pickTrip({required ImageSource source}) async {
    return showModalBottomSheet<Trip>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (ctx) {
        String searchQuery = '';
        final searchController = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // When empty, show 3 most recent trips; when typing, fuzzy filter all trips
            List<Trip> displayTrips;
            if (searchQuery.trim().isEmpty) {
              final sorted = List<Trip>.from(_trips)
                ..sort((a, b) {
                  final aDate = a.departureDate ?? DateTime(2000);
                  final bDate = b.departureDate ?? DateTime(2000);
                  return bDate.compareTo(aDate);
                });
              displayTrips = sorted.take(3).toList();
            } else {
              final scored = _trips
                  .map((t) => MapEntry(t, _fuzzyScore(searchQuery, t)))
                  .where((e) => e.value > 0)
                  .toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              displayTrips = scored.map((e) => e.key).toList();
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 14,
                right: 14,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 90,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 30,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: IntrinsicHeight(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 14, 14, 0),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.arrow_back, size: 22, color: Color(0xFF1F2937)),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Assign to Trip',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1F2937),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    source == ImageSource.camera
                                        ? 'Scan will start after selecting a trip'
                                        : 'Upload will start after selecting a trip',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8A824).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.receipt_long_outlined,
                                size: 20,
                                color: Color(0xFFE8A824),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Trip list
                      if (displayTrips.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'No trips match "$searchQuery"',
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                          ),
                        )
                      else
                        ...displayTrips.map((trip) => _buildPickerTripCard(ctx, trip)),
                      const SizedBox(height: 8),
                      // Bottom search bar
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: const Color(0xFF46166B).withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                ),
                                child: TextField(
                                  controller: searchController,
                                  onChanged: (v) => setSheetState(() => searchQuery = v),
                                  decoration: InputDecoration(
                                    hintText: 'Search for your trips....',
                                    hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () {
                                if (displayTrips.isNotEmpty) {
                                  Navigator.pop(ctx, displayTrips.first);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF46166B),
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: const Text(
                                  'Go',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
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
          },
        );
      },
    );
  }

  Widget _buildPickerTripCard(BuildContext ctx, Trip trip) {
    return GestureDetector(
      onTap: () => Navigator.pop(ctx, trip),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Folder icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFE8A824).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.folder_outlined,
                size: 22,
                color: Color(0xFFE8A824),
              ),
            ),
            const SizedBox(width: 14),
            // Trip name only
            Expanded(
              child: Text(
                trip.displayTitle,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade300),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Stack(
        children: [
          // Main content — always home tab
          _buildHomeTab(),

          // Dropdown overlay — tap to close
          if (_dropdownOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _dropdownOpen = false),
                child: Container(color: Colors.transparent),
              ),
            ),

          // Dropdown menu — rendered at top-level so it's above all content
          if (_dropdownOpen)
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              left: 20,
              child: _buildDropdownMenu(),
            ),

          // Scan menu overlay
          if (_showScanMenu) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showScanMenu = false),
                child: Container(color: Colors.black.withOpacity(0.4)),
              ),
            ),
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildScanMenu(),
              ),
            ),
          ],

          // Upload progress overlay — blur stays throughout, all disappears at once
          if (_isUploading) ...[
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(color: Colors.black.withOpacity(0.15)),
              ),
            ),
            _buildUploadOverlay(),
          ],

          // Add New Trip floating pill
          if (!_showScanMenu)
            Positioned(
              right: 20,
              bottom: 24,
              child: GestureDetector(
                onTap: _showCreateTripDialog,
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
                    children: [
                      const Icon(Icons.add, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      const Text(
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
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHomeTab() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF46166B)),
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF46166B),
      onRefresh: () => _loadData(silent: true),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildHeader(),
          _buildStatCards(),
          _buildRecentActivity(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            children: [
              // Top row: profile + logo
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildProfileButton(),
                  Image.asset(
                    'assets/asgo_logo.jpeg',
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Spending Card
              _buildSpendingCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileButton() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => setState(() => _dropdownOpen = !_dropdownOpen),
          child: Row(
            children: [
              // Avatar
              _buildAvatar(40),
              const SizedBox(width: 12),
              // Name + department
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.user.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _dropdownOpen ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.keyboard_arrow_down,
                          size: 14,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                  if (widget.user.department != null)
                    Text(
                      '${widget.user.department} · Traveler',
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
      ],
    );
  }

  Widget _buildDropdownMenu() {
    return Material(
      elevation: 0,
      color: Colors.transparent,
      child: Container(
        width: 224,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200.withOpacity(0.8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // User info header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50.withOpacity(0.6),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.user.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.user.email,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ),
            _dropdownItem(Icons.person_outline, 'My Profile', onTap: () async {
              setState(() => _dropdownOpen = false);
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
              if (mounted) setState(() => _avatarVersion++);
            }),
            _dropdownItem(Icons.settings_outlined, 'Settings', onTap: () {
              setState(() => _dropdownOpen = false);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
            }),
            _dropdownItem(Icons.help_outline, 'Help & Support', onTap: () {
              setState(() => _dropdownOpen = false);
            }),
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade100)),
              ),
              child: _dropdownItem(Icons.logout, 'Log Out', isDestructive: true, onTap: () {
                setState(() => _dropdownOpen = false);
                _logout();
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdownItem(IconData icon, String label, {bool isDestructive = false, VoidCallback? onTap}) {
    final color = isDestructive ? Colors.red.shade500 : const Color(0xFF6B7280);
    final iconColor = isDestructive ? Colors.red.shade400 : const Color(0xFF9CA3AF);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Spending Card ────────────────────────────────────

  Widget _buildSpendingCard() {
    final firstName = widget.user.name.split(' ').first;

    // find the active trip — today falls between start and end date
    final now = DateTime.now();
    final activeTrip = _trips.cast<Trip?>().firstWhere(
      (t) {
        if (t!.departureDate == null || t.returnDate == null) return false;
        final start = DateTime(t.departureDate!.year, t.departureDate!.month, t.departureDate!.day);
        final end = DateTime(t.returnDate!.year, t.returnDate!.month, t.returnDate!.day);
        final today = DateTime(now.year, now.month, now.day);
        return !today.isBefore(start) && !today.isAfter(end);
      },
      orElse: () => null,
    );

    if (activeTrip == null) {
      // check for the nearest upcoming trip
      final upcomingTrips = _trips.where((t) {
        if (t.departureDate == null) return false;
        final start = DateTime(t.departureDate!.year, t.departureDate!.month, t.departureDate!.day);
        final today = DateTime(now.year, now.month, now.day);
        return start.isAfter(today);
      }).toList()
        ..sort((a, b) => a.departureDate!.compareTo(b.departureDate!));

      final upcomingTrip = upcomingTrips.isNotEmpty ? upcomingTrips.first : null;

      if (upcomingTrip != null) {
        // show upcoming trip card
        final receiptCount = _receipts.where((r) => r.tripId == upcomingTrip.id).length;
        final totalExpenses = upcomingTrip.totalExpenses;
        final dollars = totalExpenses.truncate().toString();
        final cents = ((totalExpenses * 100).truncate() % 100).toString().padLeft(2, '0');
        final daysUntil = DateTime(upcomingTrip.departureDate!.year, upcomingTrip.departureDate!.month, upcomingTrip.departureDate!.day)
            .difference(DateTime(now.year, now.month, now.day)).inDays;
        final daysLabel = daysUntil == 1 ? 'Starts tomorrow' : 'Starts in $daysUntil days';

        return Container(
          width: double.infinity,
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
              Positioned(
                top: 0, left: 0, right: 0,
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
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE8A824).withValues(alpha: 0.1)),
                      ),
                      child: const Icon(
                        Icons.flight_takeoff,
                        color: Color(0xFFB08D3A),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'UPCOMING TRIP',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: Color(0xFF9A7A2E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            upcomingTrip.tripPurpose ?? 'Trip',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A2E),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.receipt_long, size: 13, color: Color(0xFF9A7A2E)),
                              const SizedBox(width: 4),
                              Text(
                                '$receiptCount receipts',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF9A7A2E)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6, height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE8A824),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                daysLabel,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFB08D3A),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '\$$dollars',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
                              ),
                              TextSpan(
                                text: '.$cents',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      // no active or upcoming trip
      return Container(
        width: double.infinity,
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
            Positioned(
              top: 0, left: 0, right: 0,
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
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hey, $firstName',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF46166B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'You don\'t have any active or upcoming trip at the moment.',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      fontStyle: FontStyle.italic,
                      color: Color(0xFF9A7A2E),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // active trip found — show active trip card
    final receiptCount = _receipts.where((r) => r.tripId == activeTrip.id).length;
    final totalExpenses = activeTrip.totalExpenses;
    final dollars = totalExpenses.truncate().toString();
    final cents = ((totalExpenses * 100).truncate() % 100).toString().padLeft(2, '0');

    return Container(
      width: double.infinity,
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
          // top gradient bar
          Positioned(
            top: 0, left: 0, right: 0,
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
            child: Row(
              children: [
                // location icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE8A824).withValues(alpha: 0.1)),
                  ),
                  child: const Icon(
                    Icons.location_on_outlined,
                    color: Color(0xFFB08D3A),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                // trip info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ACTIVE TRIP',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: Color(0xFF9A7A2E),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        activeTrip.tripPurpose ?? 'Trip',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.receipt_long, size: 13, color: Color(0xFF9A7A2E)),
                          const SizedBox(width: 4),
                          Text(
                            '$receiptCount receipts',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9A7A2E),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // status + total
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDE7F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6, height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF46166B),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'In Progress',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF46166B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '\$$dollars',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          TextSpan(
                            text: '.$cents',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Stat Cards ───────────────────────────────────────

  Widget _buildStatCards() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: _statCard(
              icon: Icons.description_outlined,
              iconBgColor: const Color(0xFF46166B).withOpacity(0.08),
              iconColor: const Color(0xFF46166B),
              value: '${_receipts.length}',
              label: 'Receipts',
              onTap: () async {
                final result = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReceiptsPage(
                      receipts: _receipts,
                      trips: _trips,
                      onRefresh: () => _loadData(silent: true),
                    ),
                  ),
                );
                if (!mounted) return;
                if (result == 'scan') {
                  setState(() => _showScanMenu = true);
                }
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statCard(
              icon: Icons.folder_outlined,
              iconBgColor: const Color(0xFFE8A824).withOpacity(0.1),
              iconColor: const Color(0xFFD49B1F),
              value: '${_trips.length}',
              label: 'Trips',
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TripsPage(
                      trips: _trips,
                      onRefresh: () => _loadData(silent: true),
                      analyticsService: _analyticsService,
                    ),
                  ),
                );
                _loadData(silent: true);
                if (result == 'scan' && mounted) {
                  setState(() => _showScanMenu = true);
                }
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statCard(
              icon: Icons.notifications_outlined,
              iconBgColor: Colors.red.shade50,
              iconColor: Colors.red.shade500,
              value: '$_alertCount',
              label: 'Alerts',
              badgeCount: _alertCount,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AlertsPage(
                      trips: _trips,
                      receipts: _receipts,
                      userName: widget.user.name,
                      onTripTap: () => _loadData(silent: true),
                      initialAlerts: _cachedAlerts,
                    ),
                  ),
                );
                _loadData(silent: true);
                _loadAlerts();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String value,
    required String label,
    int badgeCount = 0,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
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
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 17, color: iconColor),
              ),
              if (badgeCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.red.shade500,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
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

  // ─── Recent Scans ──────────────────────────────────

  List<Receipt> get _recentScans {
    final sorted = List<Receipt>.from(
      _receipts.where((r) => !r.isPlaceholder),
    )..sort((a, b) => (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)));
    return sorted.take(3).toList();
  }

  Widget _buildRecentActivity() {
    final scans = _recentScans;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        children: [
          // Section header
          const Row(
            children: [
              Text(
                'RECENT SCANS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (scans.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(Icons.document_scanner_outlined, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    'No scans yet',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap Scan to upload your first receipt',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                ],
              ),
            )
          else
            ...scans.map((receipt) => _recentScanCard(receipt)),
        ],
      ),
    );
  }

  String _receiptCategoryLabel(Receipt r) {
    final cat = r.travelCategory ?? r.category ?? 'Other AS Cost';
    const labels = {
      'Accommodation Cost': 'Accommodation',
      'Flight Cost': 'Flight',
      'Ground Transportation': 'Ground Transport',
      'Registration Cost': 'Registration',
      'Other AS Cost': 'Other AS Cost',
    };
    return labels[cat] ?? cat;
  }


  Future<bool> _confirmDeleteReceipt(Receipt receipt) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF46166B).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline, color: Color(0xFF46166B), size: 28),
              ),
              const SizedBox(height: 16),
              const Text('Delete Receipt?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
              const SizedBox(height: 8),
              Text(
                'Are you sure you want to delete "${receipt.merchant ?? 'this receipt'}"? This action cannot be undone.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.4),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, false),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text('Cancel', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, true),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF46166B), Color(0xFF7B3FA0)]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: const Text('Delete', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return false;
    try {
      await _api.deleteReceipt(receipt.id);
      _loadData(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF46166B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text('Receipt deleted successfully', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade600,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Failed to delete: $e', style: const TextStyle(color: Colors.white))),
              ],
            ),
          ),
        );
      }
      return false;
    }
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

  Widget _recentScanCard(Receipt receipt) {
    final category = _receiptCategoryLabel(receipt);
    final dateStr = receipt.date != null
        ? DateFormat('MMM d, y').format(receipt.date!)
        : '';

    return Dismissible(
      key: Key(receipt.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDeleteReceipt(receipt),
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF46166B),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 24),
      ),
      child: GestureDetector(
      onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ReceiptDetailViewPage(
              receipt: receipt,
              trips: _trips,
            )),
          );
          _loadData(silent: true);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
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
            return _receiptPlaceholder(size);
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
            child: Image.network(
              url,
              headers: {'Authorization': 'Bearer ${snap.data}'},
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _receiptPlaceholder(size),
            ),
          );
        },
      );
    }
    return _receiptPlaceholder(size);
  }

  Widget _receiptPlaceholder(double size) {
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

  // ─── Scan Menu ────────────────────────────────────────

  Widget _buildScanMenu() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Payment method toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paid with',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _paymentMethod = 'personal'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _paymentMethod == 'personal' ? const Color(0xFF46166B) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _paymentMethod == 'personal'
                                  ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 1))]
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.person_outline, size: 14,
                                    color: _paymentMethod == 'personal' ? Colors.white : Colors.grey.shade400),
                                const SizedBox(width: 5),
                                Text(
                                  'Personal',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _paymentMethod == 'personal' ? Colors.white : Colors.grey.shade400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _paymentMethod = 'corporate'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _paymentMethod == 'corporate' ? const Color(0xFF46166B) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _paymentMethod == 'corporate'
                                  ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 1))]
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.credit_card, size: 14,
                                    color: _paymentMethod == 'corporate' ? Colors.white : Colors.grey.shade400),
                                const SizedBox(width: 5),
                                Text(
                                  'AS Amex',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _paymentMethod == 'corporate' ? Colors.white : Colors.grey.shade400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade100),
          // Scan Receipt
          InkWell(
            onTap: () => _handleScan(ImageSource.camera),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.camera_alt, size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Scan Receipt',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Use camera to capture receipt',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade300),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade100),
          // Upload from Gallery
          InkWell(
            onTap: () => _handleScan(ImageSource.gallery),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8A824),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.add_photo_alternate, size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Upload from Gallery',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Choose an existing photo',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade300),
                ],
              ),
            ),
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
              // Home (always active)
              SizedBox(
                width: 56,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.home, size: 22, color: Color(0xFF46166B)),
                    const SizedBox(height: 2),
                    const Text(
                      'Home',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF46166B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Color(0xFF46166B),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
              // Center Scan FAB
              _buildScanFab(),
              // Alerts
              _alertsNavItem(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _alertsNavItem() {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AlertsPage(
              trips: _trips,
              receipts: _receipts,
              userName: widget.user.name,
              onTripTap: () => _loadData(silent: true),
              initialAlerts: _cachedAlerts,
            ),
          ),
        );
        _loadData(silent: true);
        _loadAlerts();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.notifications_outlined,
                  size: 22,
                  color: const Color(0xFFD1D5DB),
                ),
                if (_alertCount > 0)
                  Positioned(
                    top: -4,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.red.shade500,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      constraints: const BoxConstraints(minWidth: 16),
                      child: Text(
                        '$_alertCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Alerts',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanFab() {
    return GestureDetector(
      onTap: () => setState(() => _showScanMenu = !_showScanMenu),
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
                gradient: _showScanMenu
                    ? null
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF46166B), Color(0xFF7B3FA0)],
                      ),
                color: _showScanMenu ? const Color(0xFF6B7280) : null,
                boxShadow: [
                  BoxShadow(
                    color: _showScanMenu
                        ? Colors.black.withOpacity(0.2)
                        : const Color(0xFF46166B).withOpacity(0.35),
                    blurRadius: _showScanMenu ? 16 : 20,
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
}