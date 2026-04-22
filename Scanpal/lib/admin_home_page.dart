import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'models/user.dart';
import 'models/trip.dart';
import 'receipt.dart';
import 'api.dart';
import 'auth_service.dart';
import 'login_page.dart';
import 'trips_page.dart';
import 'pending_review_page.dart';
import 'profile_page.dart';
import 'settings_page.dart';
import 'add_trip_page.dart';
import 'admin_travelers_page.dart';
import 'admin_traveler_detail_page.dart';
import 'admin_receipts_page.dart';
import 'analytics_page.dart';
import 'services/analytics_service.dart';

class AdminHomePage extends StatefulWidget {
  final AppUser user;
  const AdminHomePage({super.key, required this.user});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  final _api = APIService();
  final _currency = NumberFormat.simpleCurrency();
  List<Trip> _trips = [];
  List<Receipt> _receipts = [];
  bool _loading = true;
  Timer? _refreshTimer;
  bool _dropdownOpen = false;
  int _avatarVersion = 0;
  List<Map<String, dynamic>> _cachedAlerts = [];

  // Scan state
  bool _showScanMenu = false;
  String _paymentMethod = 'personal';
  bool _isUploading = false;
  bool _uploadComplete = false;
  double _uploadProgress = 0.0;
  String _uploadLabel = '';
  String _completeLabel = '';
  String _uploadPaymentLabel = '';
  Timer? _progressTimer;

  int get _alertCount => _cachedAlerts.length;

  int get _totalTravelers =>
      _trips.map((t) => t.travelerEmail).toSet().length;

  // ─── Derived traveler summaries ────────────────────────

  Map<String, int> get _receiptsPerTraveler {
    final Map<String, String> tripIdToEmail = {};
    for (final trip in _trips) {
      tripIdToEmail[trip.id.toString()] = trip.travelerEmail;
    }
    final Map<String, int> counts = {};
    for (final receipt in _receipts) {
      final tid = receipt.tripId;
      if (tid == null) continue;
      final email = tripIdToEmail[tid];
      if (email != null && email.isNotEmpty) {
        counts[email] = (counts[email] ?? 0) + 1;
      }
    }
    return counts;
  }

  List<_TravelerSummary> get _travelerSummaries {
    final Map<String, _TravelerSummary> map = {};
    for (final trip in _trips) {
      final email = trip.travelerEmail;
      if (email.isEmpty) continue;
      final existing = map[email];
      if (existing != null) {
        map[email] = _TravelerSummary(
          name: trip.travelerName.isNotEmpty ? trip.travelerName : existing.name,
          email: email,
          department: trip.department ?? existing.department,
          tripCount: existing.tripCount + 1,
          totalSpent: existing.totalSpent + trip.totalExpenses,
          receiptCount: 0,
        );
      } else {
        map[email] = _TravelerSummary(
          name: trip.travelerName,
          email: email,
          department: trip.department,
          tripCount: 1,
          totalSpent: trip.totalExpenses,
          receiptCount: 0,
        );
      }
    }
    final receiptCounts = _receiptsPerTraveler;
    final list = map.entries.map((e) => _TravelerSummary(
      name: e.value.name,
      email: e.value.email,
      department: e.value.department,
      tripCount: e.value.tripCount,
      totalSpent: e.value.totalSpent,
      receiptCount: receiptCounts[e.key] ?? 0,
    )).toList()
      ..sort((a, b) => b.tripCount.compareTo(a.tripCount));
    return list;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadAlerts();
    _loadReceipts();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadData(silent: true);
      _loadAlerts();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    try {
      final reviews = await _api.fetchPendingReviews();
      if (mounted) setState(() => _cachedAlerts = reviews);
    } catch (_) {}
  }

  Future<void> _loadReceipts() async {
    try {
      final receipts = await _api.fetchReceipts();
      if (mounted) setState(() => _receipts = receipts);
    } catch (_) {}
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final trips = await _api.fetchTrips(sync: true);
      if (mounted) setState(() => _trips = trips);
    } catch (e) {
      debugPrint('Failed to load admin data: $e');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
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

  // ─── Avatar ────────────────────────────────────────────

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
              child: CachedNetworkImage(
                imageUrl: '${_api.profileImageUrl()}?v=$_avatarVersion',
                httpHeaders: {'Authorization': 'Bearer ${tokenSnap.data}'},
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _initialsAvatar(size),
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

  Widget _travelerAvatar(String email, String name, double size) {
    return FutureBuilder<String?>(
      future: AuthService.instance.getToken(),
      builder: (context, tokenSnap) {
        if (!tokenSnap.hasData) return _travelerInitials(name, size);
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(shape: BoxShape.circle),
          clipBehavior: Clip.antiAlias,
          child: CachedNetworkImage(
            imageUrl: _api.travelerImageUrl(email),
            httpHeaders: {'Authorization': 'Bearer ${tokenSnap.data}'},
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => _travelerInitials(name, size),
          ),
        );
      },
    );
  }

  Widget _travelerInitials(String name, double size) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : (name.isNotEmpty ? name[0].toUpperCase() : '?');

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
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.30,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ─── Scan Methods ──────────────────────────────────────

  Future<void> _handleScan(ImageSource source) async {
    setState(() => _showScanMenu = false);
    if (_trips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No trips available to assign receipt to')),
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
    if (photo == null) return;

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

      _progressTimer?.cancel();
      setState(() {
        _uploadProgress = 1.0;
        _uploadComplete = true;
        _receipts.insert(0, result.receipt);
        if (result.trip != null) {
          final idx = _trips.indexWhere((t) => t.id == result.trip!.id);
          if (idx >= 0) _trips[idx] = result.trip!;
        }
      });

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

  void _startUploadProgress({required bool isCamera}) {
    setState(() {
      _isUploading = true;
      _uploadComplete = false;
      _uploadProgress = 0.0;
      _uploadLabel = isCamera ? 'Scanning Receipt...' : 'Uploading Receipt...';
      _completeLabel = isCamera ? 'Scan Complete' : 'Upload Complete';
      _uploadPaymentLabel = _paymentMethod == 'corporate' ? 'AS Amex' : 'Personal';
    });

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
                  Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF46166B).withValues(alpha: 0.1),
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
                    'Help us categorize this meal expense',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 20),
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
                            color: isSelected ? color.withValues(alpha: 0.15) : Colors.grey.shade50,
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

  int _fuzzyScore(String query, Trip trip) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return 1;

    final title = trip.displayTitle.toLowerCase();
    final dest = (trip.destination ?? '').toLowerCase();
    final traveler = trip.travelerName.toLowerCase();

    int best = 0;

    for (final field in [title, dest, traveler]) {
      if (field.isEmpty) continue;
      if (field == q) { best = 100; continue; }
      if (field.startsWith(q)) { best = best < 90 ? 90 : best; continue; }
      final words = field.split(RegExp(r'[\s,\-]+'));
      for (final w in words) {
        if (w.startsWith(q)) { best = best < 80 ? 80 : best; break; }
      }
      if (field.contains(q)) { best = best < 60 ? 60 : best; continue; }
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
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (ctx) {
        String searchQuery = '';
        final searchController = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            List<Trip> displayTrips;
            if (searchQuery.trim().isEmpty) {
              final sorted = List<Trip>.from(_trips)
                ..sort((a, b) {
                  final aDate = a.departureDate ?? DateTime(2000);
                  final bDate = b.departureDate ?? DateTime(2000);
                  return bDate.compareTo(aDate);
                });
              displayTrips = sorted.take(5).toList();
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
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 30,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                              color: const Color(0xFFE8A824).withValues(alpha: 0.12),
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
                    // Scrollable trip list
                    Flexible(
                      child: displayTrips.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'No trips match "$searchQuery"',
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: displayTrips.length,
                              itemBuilder: (_, i) {
                                final trip = displayTrips[i];
                                return InkWell(
                                  onTap: () => Navigator.pop(ctx, trip),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE8A824).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.folder_outlined, size: 22, color: Color(0xFFE8A824)),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                trip.displayTitle,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF1F2937),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                trip.travelerName,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade500,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade300),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    // Search bar
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
                                  color: const Color(0xFF46166B).withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: TextField(
                                controller: searchController,
                                onChanged: (v) => setSheetState(() => searchQuery = v),
                                decoration: InputDecoration(
                                  hintText: 'Search trips or travelers...',
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
            );
          },
        );
      },
    );
  }

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
                                  ? const LinearGradient(colors: [Color(0xFFE8A824), Color(0xFFE8A824)])
                                  : const LinearGradient(colors: [Color(0xFF46166B), Color(0xFFE8A824)]),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
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
                      _uploadComplete ? Icons.check_circle_outline : Icons.document_scanner_outlined,
                      size: 22,
                      color: _uploadComplete ? const Color(0xFFE8A824) : const Color(0xFF46166B),
                    ),
                  ),
                  const SizedBox(width: 12),
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
                              decoration: BoxDecoration(color: paymentColor, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _uploadComplete ? '$_uploadPaymentLabel · Saved' : _uploadPaymentLabel,
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_uploadComplete)
                    const Icon(Icons.check_circle_outline, size: 28, color: Color(0xFFE8A824))
                  else
                    Text(
                      '${(_uploadProgress * 100).toInt()}%',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade400),
                    ),
                ],
              ),
            ],
          ),
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

  // ─── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Stack(
        children: [
          _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(Color(0xFF46166B)),
                  ),
                )
              : RefreshIndicator(
                  color: const Color(0xFF46166B),
                  onRefresh: () async {
                    await Future.wait([
                      _loadData(silent: true),
                      _loadReceipts(),
                      _loadAlerts(),
                    ]);
                  },
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _buildHeader(),
                      _buildGoldOverviewCard(),
                      _buildQuickActionCards(),
                      _buildTravelersList(),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),

          // Floating "Add New Trip" pill
          if (!_loading)
            Positioned(
              right: 20,
              bottom: 24,
              child: GestureDetector(
                onTap: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddTripPage()),
                  );
                  if (result != null) _loadData(silent: true);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF46166B),
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF46166B).withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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

          // Dropdown overlay
          if (_dropdownOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _dropdownOpen = false),
                child: Container(color: Colors.transparent),
              ),
            ),

          if (_dropdownOpen)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 20,
              child: _buildDropdownMenu(),
            ),

          // Scan menu overlay
          if (_showScanMenu) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showScanMenu = false),
                child: Container(color: Colors.black.withValues(alpha: 0.4)),
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

          // Upload progress overlay
          if (_isUploading) ...[
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(color: Colors.black.withValues(alpha: 0.15)),
              ),
            ),
            _buildUploadOverlay(),
          ],
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ─── Header ────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildProfileButton(),
              Image.asset('assets/asgo_logo.jpeg', height: 32, fit: BoxFit.contain),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileButton() {
    final dept = widget.user.department;
    final subtitle = dept != null && dept.isNotEmpty
        ? 'Admin · $dept'
        : 'Admin';

    return GestureDetector(
      onTap: () => setState(() => _dropdownOpen = !_dropdownOpen),
      child: Row(
        children: [
          _buildAvatar(40),
          const SizedBox(width: 12),
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
              Text(
                subtitle,
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
    );
  }

  // ─── Dropdown Menu ─────────────────────────────────────

  Widget _buildDropdownMenu() {
    return Material(
      elevation: 0,
      color: Colors.transparent,
      child: Container(
        width: 224,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200.withValues(alpha: 0.8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50.withValues(alpha: 0.6),
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

  Widget _dropdownItem(IconData icon, String label,
      {bool isDestructive = false, VoidCallback? onTap}) {
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
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color)),
          ],
        ),
      ),
    );
  }

  // ─── Gold Overview Card (Receipts + Trips) ─────────────

  Widget _buildGoldOverviewCard() {
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
          border: Border.all(color: const Color(0xFFE8A824).withValues(alpha: 0.2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Purple-gold gradient top bar
            Container(
              height: 3,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF46166B), Color(0xFFE8A824), Color(0xFF46166B)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              child: Row(
                children: [
                  // Receipts stat
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminReceiptsPage(
                              receipts: _receipts,
                              trips: _trips,
                              isLoading: _loading,
                              onRefresh: () async {
                                await Future.wait([
                                  _loadData(silent: true),
                                  _loadReceipts(),
                                ]);
                              },
                            ),
                          ),
                        );
                        _loadReceipts();
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.description_outlined,
                              size: 14,
                              color: Color(0xFFB08D3A),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${_receipts.length}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Receipts',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF9A7A2E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Trips stat
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TripsPage(
                              trips: _trips,
                              onRefresh: () => _loadData(silent: true),
                              showDepartmentFilter: true,
                            ),
                          ),
                        );
                        _loadData(silent: true);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.folder_outlined,
                              size: 14,
                              color: Color(0xFFB08D3A),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${_trips.length}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Trips',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF9A7A2E),
                            ),
                          ),
                        ],
                      ),
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

  // ─── Quick Action Cards (Pending Reviews + Travelers) ──

  Widget _buildQuickActionCards() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          // Pending Reviews
          Expanded(
            child: GestureDetector(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PendingReviewPage(
                      trips: _trips,
                      receipts: _receipts,
                      userName: widget.user.name,
                      onTripTap: () => _loadData(silent: true),
                      initialAlerts: _cachedAlerts,
                    ),
                  ),
                );
                _loadAlerts();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
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
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF46166B).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.schedule_outlined,
                        size: 15,
                        color: Color(0xFF46166B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_alertCount',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Pending Reviews',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Travelers
          Expanded(
            child: GestureDetector(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminTravelersPage(
                      trips: _trips,
                      receipts: _receipts,
                      onRefresh: () => _loadData(silent: true),
                    ),
                  ),
                );
                _loadData(silent: true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
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
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8A824).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.people_outline,
                        size: 15,
                        color: Color(0xFFE8A824),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_totalTravelers',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Travelers',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Travelers List ────────────────────────────────────

  Widget _buildTravelersList() {
    final travelers = _travelerSummaries;
    final displayList = travelers.take(3).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TRAVELERS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 1.0,
                ),
              ),
              if (travelers.length > 3)
                GestureDetector(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminTravelersPage(
                          trips: _trips,
                          receipts: _receipts,
                          onRefresh: () => _loadData(silent: true),
                        ),
                      ),
                    );
                    _loadData(silent: true);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'View All',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF46166B),
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right, size: 14, color: Color(0xFF46166B)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (displayList.isEmpty)
            _buildEmptyTravelers()
          else
            ...displayList.map((t) => _buildTravelerCard(t)),
        ],
      ),
    );
  }

  Widget _buildEmptyTravelers() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
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
        children: [
          Icon(Icons.people_outline, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'No travelers yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTravelerCard(_TravelerSummary traveler) {
    return GestureDetector(
      onTap: () async {
        final travelerTrips = _trips
            .where((t) => t.travelerEmail == traveler.email)
            .toList();
        final summary = TravelerSummary(
          name: traveler.name,
          email: traveler.email,
          department: traveler.department,
          tripCount: traveler.tripCount,
          totalSpent: traveler.totalSpent,
          receiptCount: traveler.receiptCount,
        );
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdminTravelerDetailPage(
              traveler: summary,
              trips: travelerTrips,
              receipts: _receipts.where((r) =>
                travelerTrips.any((t) => t.id.toString() == r.tripId)
              ).toList(),
              onRefresh: () => _loadData(silent: true),
            ),
          ),
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
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            _travelerAvatar(traveler.email, traveler.name, 44),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    traveler.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (traveler.department != null &&
                      traveler.department!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      traveler.department!,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF9CA3AF),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Color(0xFF9CA3AF)),
                          children: [
                            TextSpan(
                              text: '${traveler.receiptCount}',
                              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF4B5563)),
                            ),
                            const TextSpan(text: ' receipts'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Color(0xFF9CA3AF)),
                          children: [
                            TextSpan(
                              text: '${traveler.tripCount}',
                              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF4B5563)),
                            ),
                            const TextSpan(text: ' trips'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _currency.format(traveler.totalSpent),
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4B5563),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade300),
          ],
        ),
      ),
    );
  }

  // ─── Bottom Nav ────────────────────────────────────────

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
              // Analytics
              GestureDetector(
                onTap: () {
                  final analyticsService = AnalyticsService(
                    receipts: _receipts,
                    trips: _trips,
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: const Color(0xFFFAFAFA),
                        body: AnalyticsPage(
                          analyticsService: analyticsService,
                          onBack: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                  );
                },
                child: SizedBox(
                  width: 56,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bar_chart_rounded, size: 22, color: Colors.grey.shade400),
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

// ─── Helper model ────────────────────────────────────────

class _TravelerSummary {
  final String name;
  final String email;
  final String? department;
  final int tripCount;
  final double totalSpent;
  final int receiptCount;

  const _TravelerSummary({
    required this.name,
    required this.email,
    required this.department,
    required this.tripCount,
    required this.totalSpent,
    required this.receiptCount,
  });
}
