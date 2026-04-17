import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'models/trip.dart';
import 'receipt.dart';
import 'api.dart';
import 'auth_service.dart';
import 'receipt_detail_page.dart';
import 'travel_calendar.dart';
import 'receipt_detail_view_page.dart';

class TripDetailPage extends StatefulWidget {
  final Trip trip;
  const TripDetailPage({super.key, required this.trip});

  @override
  State<TripDetailPage> createState() => _TripDetailPageState();
}

class _TripDetailPageState extends State<TripDetailPage> {
  final _api = APIService();
  final _currency = NumberFormat.simpleCurrency();
  late Trip _trip;
  List<Receipt> _receipts = [];
  bool _loading = true;
  bool _isAdmin = false;
  final _commentCtrl = TextEditingController();
  bool _sendingComment = false;

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

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _loadReceipts();
    _refreshTrip();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    final isAdmin = await AuthService.instance.getLastRoleIsAdmin();
    if (mounted) setState(() => _isAdmin = isAdmin);
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sendingComment = true);
    try {
      await _api.addTripComment(_trip.id, text);
      _commentCtrl.clear();
      if (mounted) {
        _showToast('Comment sent to traveler');
      }
    } catch (e) {
      if (mounted) {
        _showToast('Failed to send comment: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  Future<void> _loadReceipts() async {
    setState(() => _loading = true);
    try {
      final receipts = await _api.fetchReceipts(tripId: _trip.id);
      if (mounted) setState(() => _receipts = receipts);
    } catch (e) {
      debugPrint('Failed to load receipts: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshTrip() async {
    try {
      final updated = await _api.fetchTripDetail(_trip.id);
      if (mounted) setState(() => _trip = Trip.fromMap(updated));
    } catch (e) {
      debugPrint('Failed to refresh trip: $e');
    }
  }

  String get _statusLabel {
    final s = _trip.status?.toLowerCase();
    if (s == 'active') return 'Active';
    if (s == 'completed') return 'Completed';
    if (s == 'upcoming') return 'Upcoming';
    if (_trip.isActive) return 'Active';
    if (_trip.isUpcoming) return 'Upcoming';
    if (_trip.isPast) return 'Completed';
    return 'Active';
  }

  Color get _statusDotColor {
    final label = _statusLabel;
    if (label == 'Active') return const Color(0xFF34D399);
    if (label == 'Upcoming') return const Color(0xFF60A5FA);
    return const Color(0xFF9CA3AF);
  }

  int get _durationDays {
    if (_trip.departureDate == null || _trip.returnDate == null) return 0;
    return _trip.returnDate!.difference(_trip.departureDate!).inDays;
  }

  String get _categoryLabel {
    // Use saved category if available
    if (_trip.category != null && _trip.category!.isNotEmpty) {
      return _trip.category!;
    }
    final purpose = _trip.tripPurpose?.toLowerCase() ?? '';
    if (purpose.contains('conference')) return 'Conference';
    if (purpose.contains('workshop')) return 'Workshop';
    if (purpose.contains('training')) return 'Training';
    if (purpose.contains('meeting')) return 'Meeting';
    if (purpose.contains('retreat')) return 'Retreat';
    if (purpose.contains('seminar')) return 'Seminar';
    if (purpose.contains('summit')) return 'Summit';
    return 'Business';
  }

  String get _description {
    // Use saved description if available
    if (_trip.description != null && _trip.description!.trim().isNotEmpty) {
      return _trip.description!.trim();
    }
    final parts = <String>[];
    final purpose = _trip.tripPurpose ?? '';
    final dest = _trip.destination ?? '';
    final days = _durationDays;

    if (purpose.isNotEmpty && dest.isNotEmpty) {
      parts.add('$purpose at $dest.');
    } else if (purpose.isNotEmpty) {
      parts.add('$purpose.');
    } else if (dest.isNotEmpty) {
      parts.add('Trip to $dest.');
    }

    final covers = <String>[];
    if (_trip.accommodationCost > 0) covers.add('lodging');
    if (_trip.flightCost > 0) covers.add('flights');
    if (_trip.groundTransportation > 0) covers.add('transportation');
    if (_trip.registrationCost > 0) covers.add('registration');
    if (_trip.otherAsCost > 0) covers.add('other expenses');

    if (covers.isNotEmpty && days > 0) {
      final coverStr = covers.length == 1
          ? covers.first
          : covers.length == 2
              ? '${covers[0]} and ${covers[1]}'
              : '${covers.sublist(0, covers.length - 1).join(', ')}, and ${covers.last}';
      parts.add('Covers $coverStr for $days day${days == 1 ? '' : 's'}.');
    } else if (days > 0) {
      parts.add('Duration: $days day${days == 1 ? '' : 's'}.');
    }

    return parts.join(' ');
  }

  void _openEditTrip() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF5F5F5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _EditTripSheet(
        trip: _trip,
        onSaved: (updatedTrip) {
          setState(() => _trip = updatedTrip);
          _refreshTrip(); // also refresh from server for full data
        },
      ),
    );
  }

  Future<void> _deleteTrip() async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFFCE4EC),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.delete_outline, size: 28, color: Color(0xFFE91E63)),
            ),
            const SizedBox(height: 16),
            const Text(
              'Delete Trip?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This will permanently remove "${_trip.displayTitle}" and cannot be undone.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                height: 1.4,
              ),
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
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
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
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          fontSize: 15,
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
    );
    if (confirm != true) return;

    final success = await _api.deleteTrip(_trip.id);
    if (!mounted) return;
    if (success) {
      Navigator.pop(context, 'deleted');
    } else {
      _showToast('Failed to delete trip', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF46166B)),
              ),
            )
          : RefreshIndicator(
              color: const Color(0xFF46166B),
              onRefresh: () async {
                await Future.wait([_loadReceipts(), _refreshTrip()]);
              },
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildHeaderBar(),
                  _buildCoverImage(),
                  const SizedBox(height: 16),
                  _buildTotalSpentCard(),
                  const SizedBox(height: 12),
                  _buildDescriptionCard(),
                  const SizedBox(height: 12),
                  _buildDateRow(),
                  const SizedBox(height: 12),
                  _buildTravelerDurationRow(),
                  const SizedBox(height: 12),
                  _buildViewReceiptsCard(),
                  if (_isAdmin)
                    const SizedBox(height: 80), // space for bottom action buttons
                  const SizedBox(height: 40),
                ],
              ),
            ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isAdmin) _buildAdminActions(),
          _buildBottomNav(),
        ],
      ),
    );
  }

  // ─── Header Bar ────────────────────────────────────────

  Widget _buildHeaderBar() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Color(0xFF4B5563)),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Trip Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              // Edit button
              GestureDetector(
                onTap: _openEditTrip,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.edit_outlined, size: 16, color: Colors.grey.shade700),
                ),
              ),
              const SizedBox(width: 10),
              // Delete button
              GestureDetector(
                onTap: _deleteTrip,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFCE4EC),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFE91E63)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Cover Image ───────────────────────────────────────

  Widget _buildCoverImage() {
    final dest = _trip.destination ?? _trip.tripPurpose ?? '';
    final hash = dest.toLowerCase().hashCode.abs();
    final colors = _thumbGradients[hash % _thumbGradients.length];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background image or gradient fallback
            if (_trip.coverImageUrl != null)
              CachedNetworkImage(
                imageUrl: _trip.coverImageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors,
                    ),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                ),
              ),
            // Dark gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.6),
                  ],
                  stops: const [0.3, 1.0],
                ),
              ),
            ),
            // Badges + trip info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status + category badges
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _statusDotColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _statusLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _categoryLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Trip name
                  Text(
                    _trip.displayTitle,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_trip.destination != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 14, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          _trip.destination!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Total Spent Card ──────────────────────────────────

  Widget _buildTotalSpentCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFDF6E3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8A824).withOpacity(0.2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 3,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF46166B), Color(0xFFE8A824), Color(0xFF46166B)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TOTAL SPENT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9A7A2E),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _currency.format(_trip.totalExpenses),
                    style: const TextStyle(
                      fontSize: 30,
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

  // ─── Description Card ──────────────────────────────────

  Widget _buildDescriptionCard() {
    final desc = _description;
    if (desc.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DESCRIPTION',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade400,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              desc,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF4B5563),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Date Row ──────────────────────────────────────────

  Widget _buildDateRow() {
    final dateFormat = DateFormat('MMM d, yyyy');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _infoCard(
              icon: Icons.calendar_today_outlined,
              iconBgColor: const Color(0xFF46166B),
              iconColor: Colors.white,
              label: 'START DATE',
              value: _trip.departureDate != null
                  ? dateFormat.format(_trip.departureDate!)
                  : 'Not set',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _infoCard(
              icon: Icons.calendar_today_outlined,
              iconBgColor: const Color(0xFF46166B),
              iconColor: Colors.white,
              label: 'END DATE',
              value: _trip.returnDate != null
                  ? dateFormat.format(_trip.returnDate!)
                  : 'Not set',
            ),
          ),
        ],
      ),
    );
  }

  // ─── Travelers + Duration Row ──────────────────────────

  Widget _buildTravelerDurationRow() {
    final days = _durationDays;

    // Build travelers list: owner + comma-separated travelers from edit
    final allNames = <String>[_trip.travelerName];
    if (_trip.travelers != null && _trip.travelers!.trim().isNotEmpty) {
      allNames.addAll(
        _trip.travelers!.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
      );
    }
    final memberCount = allNames.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Travelers card
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Color(0xFFD49B1F),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.people_outline, size: 20, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'TRAVELERS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$memberCount member${memberCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Show avatar + name for each traveler
                    ...allNames.take(3).map((n) {
                      final nameParts = n.trim().split(RegExp(r'\s+'));
                      final ini = nameParts.length >= 2
                          ? '${nameParts.first[0]}${nameParts.last[0]}'.toUpperCase()
                          : n.isNotEmpty ? n[0].toUpperCase() : '?';
                      final short = nameParts.length >= 2
                          ? '${nameParts.first} ${nameParts.last[0]}.'
                          : n;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              decoration: const BoxDecoration(
                                color: Color(0xFF46166B),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                ini,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                short,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (memberCount > 3)
                      Text(
                        '+${memberCount - 3} more',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Duration card
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Color(0xFF46166B),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.schedule_outlined, size: 20, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'DURATION',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      days > 0 ? '$days day${days == 1 ? '' : 's'}' : 'Not set',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Info Card (for dates) ─────────────────────────────

  Widget _infoCard({
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade400,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }

  // ─── View Receipts Card ────────────────────────────────

  Widget _buildViewReceiptsCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: _openReceiptsList,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF46166B),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.receipt_long_outlined, size: 22, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'View Receipts',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_receipts.length} receipt${_receipts.length == 1 ? '' : 's'} for this trip',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 22, color: Colors.grey.shade300),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Receipts Bottom Sheet ─────────────────────────────

  void _openReceiptsList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _TripReceiptsPage(
          trip: _trip,
          receipts: _receipts,
          onRefresh: () {
            _loadReceipts();
            _refreshTrip();
          },
        ),
      ),
    );
  }

  // ─── Approve Trip ──────────────────────────────────────

  Future<void> _approveTrip() async {
    try {
      await _api.approveTrip(_trip.id);
      if (mounted) {
        _showToast('Trip approved');
        _refreshTrip();
      }
    } catch (e) {
      if (mounted) {
        _showToast('Failed to approve: $e', isError: true);
      }
    }
  }

  // ─── Add Comment Sheet ────────────────────────────────

  void _showCommentSheet() {
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
                    'Add a comment about this submission. The traveler will be notified.',
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
                            _sendComment();
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

  // ─── Admin Action Buttons ─────────────────────────────

  Widget _buildAdminActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _approveTrip,
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
              onTap: _showCommentSheet,
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
              // Home
              GestureDetector(
                onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
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
                onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
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
                onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
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

// ─── Trip Receipts Full Page ─────────────────────────────

class _TripReceiptsPage extends StatefulWidget {
  final Trip trip;
  final List<Receipt> receipts;
  final VoidCallback? onRefresh;

  const _TripReceiptsPage({required this.trip, required this.receipts, this.onRefresh});

  @override
  State<_TripReceiptsPage> createState() => _TripReceiptsPageState();
}

class _TripReceiptsPageState extends State<_TripReceiptsPage> {
  final _currency = NumberFormat.simpleCurrency();
  final _api = APIService();
  String? _token;

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

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final token = await AuthService.instance.getToken();
    if (mounted) setState(() => _token = token);
  }

  void _attachReceiptToPlaceholder(Receipt receipt) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
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
              const SizedBox(height: 20),
              Icon(Icons.admin_panel_settings, size: 40, color: const Color(0xFFE8A824)),
              const SizedBox(height: 12),
              Text(
                '${receipt.merchant ?? "Expense"} — ${_currency.format(receipt.effectiveTotal)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Added by your admin. You can attach your receipt.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _scanForPlaceholder(receipt);
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Scan'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1F2937),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _pickFromGalleryForPlaceholder(receipt);
                      },
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1F2937),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
  }

  Future<void> _scanForPlaceholder(Receipt receipt) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picked == null) return;
    await _attachImageToReceipt(receipt, File(picked.path));
  }

  Future<void> _pickFromGalleryForPlaceholder(Receipt receipt) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    await _attachImageToReceipt(receipt, File(picked.path));
  }

  Future<void> _attachImageToReceipt(Receipt receipt, File image) async {
    try {
      await _api.attachReceiptImage(image, receiptId: receipt.id);
      if (mounted) {
        _showToast('Receipt attached successfully');
        widget.onRefresh?.call();
      }
    } catch (e) {
      if (mounted) {
        _showToast('Failed to attach: $e', isError: true);
      }
    }
  }

  List<Receipt> get receipts => widget.receipts;
  Trip get trip => widget.trip;

  double get _totalAmount {
    double sum = 0;
    for (final r in receipts) {
      sum += r.effectiveTotal;
    }
    return sum;
  }

  String _categoryLabel(Receipt r) {
    final cat = r.travelCategory ?? r.category ?? '';
    if (cat.isEmpty) return '';
    // Map backend keys to display labels
    const labels = {
      'accommodation_cost': 'Lodging',
      'Accommodation Cost': 'Lodging',
      'flight_cost': 'Flight',
      'Flight Cost': 'Flight',
      'ground_transportation': 'Transportation',
      'Ground Transportation': 'Transportation',
      'registration_cost': 'Registration',
      'Registration Cost': 'Registration',
      'other_as_cost': 'Other AS Cost',
      'Other AS Cost': 'Other AS Cost',
    };
    return labels[cat] ?? cat;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.arrow_back, size: 18, color: Colors.grey.shade700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${trip.displayTitle} Receipts',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${receipts.length} receipt${receipts.length == 1 ? '' : 's'} · ${_currency.format(_totalAmount)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Receipt list
            Expanded(
              child: receipts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text(
                            'No receipts for this trip yet',
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: receipts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _receiptCard(context, receipts[i]),
                    ),
            ),
            // Bottom nav
            _buildBottomNav(context),
          ],
        ),
      ),
    );
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
      widget.onRefresh?.call();
      if (mounted) {
        _showToast('Receipt deleted');
      }
      return true;
    } catch (e) {
      if (mounted) {
        _showToast('Failed to delete: $e', isError: true);
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
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _receiptCard(BuildContext context, Receipt receipt) {
    final dateStr = receipt.date != null
        ? DateFormat('MMM d, yyyy').format(receipt.date!)
        : 'No date';
    final catLabel = _categoryLabel(receipt);

    return Dismissible(
      key: Key(receipt.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDeleteReceipt(receipt),
      background: Container(
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
              trips: [widget.trip],
            )),
          );
          widget.onRefresh?.call();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: receipt.isPlaceholder ? const Color(0xFFFFF8E1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: receipt.isPlaceholder
                ? const Color(0xFFE8A824).withOpacity(0.3)
                : Colors.grey.shade100,
          ),
        ),
        child: Row(
          children: [
            // Thumbnail
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.hardEdge,
              child: receipt.imageUrl != null && receipt.imageUrl!.isNotEmpty && _token != null
                  ? CachedNetworkImage(
                      imageUrl: _api.receiptImageUrl(receipt.id),
                      httpHeaders: {'Authorization': 'Bearer $_token'},
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Center(
                        child: Icon(Icons.receipt_outlined, size: 26, color: Colors.grey.shade400),
                      ),
                    )
                  : Center(
                      child: Icon(Icons.receipt_outlined, size: 26, color: Colors.grey.shade400),
                    ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    receipt.merchant ?? 'Unknown Merchant',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (catLabel.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              catLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: receipt.paymentMethod == 'corporate'
                                ? const Color(0xFFEDE7F6)
                                : const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            receipt.paymentMethod == 'corporate' ? 'AS Amex' : 'Personal',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: receipt.paymentMethod == 'corporate'
                                  ? const Color(0xFF46166B)
                                  : const Color(0xFFB08D3A),
                            ),
                          ),
                        ),
                        if (receipt.mealType != null)
                          _mealTypeTag(receipt.mealType!),
                      ],
                    ),
                  const SizedBox(height: 4),
                  Text(
                    dateStr,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Amount + chevron
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _currency.format(receipt.effectiveTotal),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 4),
                Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade300),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
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
              GestureDetector(
                onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 56,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.home_outlined, size: 22, color: Colors.grey.shade300),
                      const SizedBox(height: 2),
                      Text('Home', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey.shade400)),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
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
                      child: Text('Scan', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey.shade400)),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 56,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bar_chart_rounded, size: 22, color: Colors.grey.shade300),
                      const SizedBox(height: 2),
                      Text('Analytics', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey.shade400)),
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

// ─── Edit Trip Bottom Sheet ─────────────────────────────

class _EditTripSheet extends StatefulWidget {
  final Trip trip;
  final ValueChanged<Trip> onSaved;

  const _EditTripSheet({required this.trip, required this.onSaved});

  @override
  State<_EditTripSheet> createState() => _EditTripSheetState();
}

class _EditTripSheetState extends State<_EditTripSheet> {
  final _api = APIService();
  late TextEditingController _nameCtrl;
  late TextEditingController _destCtrl;
  late TextEditingController _descCtrl;
  final _travelerSearchCtrl = TextEditingController();
  final _travelerSearchFocus = FocusNode();
  List<Map<String, dynamic>> _selectedTravelers = [];
  List<Map<String, dynamic>> _travelerSuggestions = [];
  Timer? _searchDebounce;
  bool _showSuggestions = false;

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

  DateTime? _startDate;
  DateTime? _endDate;
  String _category = 'Conference';
  String _status = 'Active';
  String? _travelType;
  bool _saving = false;

  static const _categories = ['Conference', 'Advocacy', 'Meeting', 'Retreat', 'Workshop', 'Other'];
  static const _statuses = ['Active', 'Completed', 'Upcoming'];
  static const _travelTypes = ['TAAR', 'One Day Travel', 'Exception'];

  @override
  void initState() {
    super.initState();
    final t = widget.trip;
    _nameCtrl = TextEditingController(text: t.tripPurpose ?? '');
    _destCtrl = TextEditingController(text: t.destination ?? '');
    _travelType = t.travelType;
    _descCtrl = TextEditingController(text: t.description ?? '');
    // Parse existing travelers (comma-separated emails) into chip data
    if (t.travelers != null && t.travelers!.trim().isNotEmpty) {
      for (final email in t.travelers!.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
        _selectedTravelers.add({'name': email, 'email': email});
      }
      // Resolve names from backend
      _resolveExistingTravelers();
    }
    _startDate = t.departureDate;
    _endDate = t.returnDate;
    _category = t.category ?? _inferCategory(t.tripPurpose);
    _status = _inferStatus(t);
  }

  String _inferCategory(String? purpose) {
    if (purpose == null) return 'Conference';
    final p = purpose.toLowerCase();
    for (final cat in _categories) {
      if (p.contains(cat.toLowerCase())) return cat;
    }
    return 'Conference';
  }

  String _inferStatus(Trip t) {
    if (t.isActive) return 'Active';
    if (t.isUpcoming) return 'Upcoming';
    if (t.isPast) return 'Completed';
    return 'Active';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _destCtrl.dispose();
    _descCtrl.dispose();
    _travelerSearchCtrl.dispose();
    _travelerSearchFocus.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _pickDates() async {
    final result = await showTravelCalendar(
      context,
      initialStart: _startDate,
      initialEnd: _endDate,
    );
    if (result != null) {
      setState(() {
        _startDate = result.start;
        _endDate = result.end;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updates = <String, dynamic>{
        'trip_purpose': _nameCtrl.text.trim(),
        'destination': _destCtrl.text.trim(),
        'departure_date': _startDate?.toIso8601String(),
        'return_date': _endDate?.toIso8601String(),
        'travel_type': _travelType,
        'category': _category,
        'status': _status.toLowerCase(),
        'description': _descCtrl.text.trim(),
        'travelers': _selectedTravelers.map((t) => t['email']).join(','),
      };

      debugPrint('Saving trip updates: $updates');
      final updated = await _api.updateTrip(widget.trip.id, updates);
      debugPrint('Trip updated successfully: ${updated.tripPurpose}, ${updated.destination}');
      if (!mounted) return;
      widget.onSaved(updated);
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Edit trip save error: $e');
      if (!mounted) return;
      _showToast('Failed to save: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final dateFormat = DateFormat('MMM d, yyyy');

    return Container(
      color: const Color(0xFFF5F5F5),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Title row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Edit Trip',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.close, size: 15, color: Colors.grey.shade600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Trip Name
                  _fieldLabel('TRIP NAME'),
                  const SizedBox(height: 5),
                  _textField(_nameCtrl, 'Enter trip name'),
                  const SizedBox(height: 14),
                  // Destination
                  _fieldLabel('DESTINATION'),
                  const SizedBox(height: 5),
                  _textField(_destCtrl, 'Enter destination'),
                  const SizedBox(height: 14),
                  // Start / End Date
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel('START DATE'),
                            const SizedBox(height: 5),
                            _dateField(
                              value: _startDate != null ? dateFormat.format(_startDate!) : 'Select',
                              onTap: _pickDates,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel('END DATE'),
                            const SizedBox(height: 5),
                            _dateField(
                              value: _endDate != null ? dateFormat.format(_endDate!) : 'Select',
                              onTap: _pickDates,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Travel Type
                  _fieldLabel('TRAVEL TYPE'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _travelTypes.map((type) {
                      final selected = _travelType == type;
                      return GestureDetector(
                        onTap: () => setState(() => _travelType = type),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF46166B) : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected ? const Color(0xFF46166B) : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            type,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: selected ? Colors.white : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  // Category
                  _fieldLabel('CATEGORY'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _categories.map((cat) {
                      final selected = _category == cat;
                      return GestureDetector(
                        onTap: () => setState(() => _category = cat),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF46166B) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected ? const Color(0xFF46166B) : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            cat,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: selected ? Colors.white : const Color(0xFF4B5563),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  // Status
                  _fieldLabel('STATUS'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _statuses.map((s) {
                      final selected = _status == s;
                      return GestureDetector(
                        onTap: () => setState(() => _status = s),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF1F2937) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected ? const Color(0xFF1F2937) : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            s,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: selected ? Colors.white : const Color(0xFF4B5563),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  // Description
                  _fieldLabel('DESCRIPTION'),
                  const SizedBox(height: 5),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: TextField(
                      controller: _descCtrl,
                      maxLines: 3,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937)),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(12),
                        hintText: 'Add a description...',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Co-Travelers
                  _fieldLabel('CO-TRAVELERS'),
                  const SizedBox(height: 5),
                  _buildTravelerChipField(),
                  const SizedBox(height: 22),
                  // Save button
                  GestureDetector(
                    onTap: _saving ? null : _save,
                    child: Container(
                      width: double.infinity,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFF46166B),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check, size: 17, color: Colors.white),
                                SizedBox(width: 6),
                                Text(
                                  'Save Changes',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
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
        ),
      ),
    );
  }

  Future<void> _resolveExistingTravelers() async {
    // Try to resolve emails to names via search
    final resolved = <Map<String, dynamic>>[];
    for (final t in _selectedTravelers) {
      try {
        final results = await _api.searchUsers(t['email']);
        final match = results.firstWhere(
          (r) => r['email'] == t['email'],
          orElse: () => t,
        );
        resolved.add(match);
      } catch (_) {
        resolved.add(t);
      }
    }
    if (mounted) setState(() => _selectedTravelers = resolved);
  }

  void _onTravelerSearch(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _travelerSuggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await _api.searchUsers(query.trim());
        final selectedEmails = _selectedTravelers.map((t) => t['email']).toSet();
        final filtered = results.where((r) => !selectedEmails.contains(r['email'])).toList();
        if (mounted) {
          setState(() {
            _travelerSuggestions = filtered;
            _showSuggestions = filtered.isNotEmpty;
          });
        }
      } catch (_) {}
    });
  }

  void _addTraveler(Map<String, dynamic> user) {
    setState(() {
      _selectedTravelers.add(user);
      _travelerSearchCtrl.clear();
      _travelerSuggestions = [];
      _showSuggestions = false;
    });
    _travelerSearchFocus.requestFocus();
  }

  void _removeTraveler(String email) {
    setState(() {
      _selectedTravelers.removeWhere((t) => t['email'] == email);
    });
  }

  Widget _buildTravelerChipField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selectedTravelers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _selectedTravelers.map((t) {
                      return Container(
                        padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF46166B).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              t['name'] ?? t['email'],
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF46166B),
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => _removeTraveler(t['email']),
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF46166B).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, size: 10, color: Color(0xFF46166B)),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              TextField(
                controller: _travelerSearchCtrl,
                focusNode: _travelerSearchFocus,
                style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937)),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  hintText: _selectedTravelers.isEmpty ? 'Search by name...' : 'Add another...',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  isDense: true,
                ),
                onChanged: _onTravelerSearch,
              ),
            ],
          ),
        ),
        if (_showSuggestions)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _travelerSuggestions.map((user) {
                return InkWell(
                  onTap: () => _addTraveler(user),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFF46166B).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            (user['name'] ?? '?')[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF46166B),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user['name'] ?? '',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              Text(
                                '${user['email']}${user['department'] != null ? ' · ${user['department']}' : ''}',
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.add_circle_outline, size: 16, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade500,
        letterSpacing: 0.6,
      ),
    );
  }

  Widget _textField(TextEditingController ctrl, String hint) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: ctrl,
        style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937)),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          isDense: true,
        ),
      ),
    );
  }

  Widget _dateField({required String value, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: value == 'Select' ? Colors.grey.shade400 : const Color(0xFF1F2937),
          ),
        ),
      ),
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
