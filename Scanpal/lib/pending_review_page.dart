import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'api.dart';
import 'models/trip.dart';
import 'receipt.dart';
import 'trip_detail_page.dart';
import 'auth_service.dart';

class PendingReviewPage extends StatefulWidget {
  final List<Trip> trips;
  final List<Receipt> receipts;
  final String userName;
  final VoidCallback onTripTap;
  final List<Map<String, dynamic>> initialAlerts;

  const PendingReviewPage({
    super.key,
    required this.trips,
    required this.receipts,
    required this.userName,
    required this.onTripTap,
    this.initialAlerts = const [],
  });

  @override
  State<PendingReviewPage> createState() => _PendingReviewPageState();
}

class _PendingReviewPageState extends State<PendingReviewPage> {
  static const _purple = Color(0xFF46166B);
  static const _gold = Color(0xFFE8A824);

  final _api = APIService();
  final _currency = NumberFormat.simpleCurrency();
  final _commentCtrl = TextEditingController();
  List<Map<String, dynamic>> _reviews = [];
  String _filter = 'all';
  bool _loading = true;
  Timer? _tickTimer;
  String? _token;
  final Set<String> _readIds = {};

  @override
  void initState() {
    super.initState();
    _fetchReviews();
    _loadToken();
    _tickTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadToken() async {
    final t = await AuthService.instance.getToken();
    if (mounted) setState(() => _token = t);
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchReviews() async {
    try {
      final reviews = await _api.fetchPendingReviews();
      if (mounted) setState(() { _reviews = reviews; _loading = false; });
    } catch (e) {
      debugPrint('Failed to fetch pending reviews: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'all') return _reviews;
    return _reviews.where((r) => r['review_type'] == _filter).toList();
  }

  String _rid(Map<String, dynamic> r) => r['id']?.toString() ?? '';
  int get _unreadCount => _reviews.where((r) => !_readIds.contains(_rid(r))).length;
  int get _receiptUnreadCount => _reviews.where((r) => r['review_type'] == 'receipt' && !_readIds.contains(_rid(r))).length;
  int get _tripUnreadCount => _reviews.where((r) => r['review_type'] == 'trip' && !_readIds.contains(_rid(r))).length;

  bool _isReceipt(Map<String, dynamic> r) => r['review_type'] == 'receipt';

  String _timeAgo(String? isoDate) {
    if (isoDate == null) return '';
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return '';
    final diff = DateTime.now().toUtc().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }

  // ── Navigation ──

  void _onReviewTap(Map<String, dynamic> review) {
    if (_isReceipt(review)) {
      _openReceiptReview(review);
    } else {
      _openTripReview(review);
    }
  }

  Trip? _findTrip(Map<String, dynamic> review) {
    final tripId = review['trip_id'];
    if (tripId == null) return null;
    final id = tripId.toString();
    for (final t in widget.trips) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> _openTripReview(Map<String, dynamic> review) async {
    final trip = _findTrip(review);
    if (trip != null && mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetailPage(trip: trip)));
      widget.onTripTap();
      _fetchReviews();
    }
  }

  Future<void> _openReceiptReview(Map<String, dynamic> review) async {
    final receiptId = review['receipt_id'] as String?;
    if (receiptId == null) {
      _openTripReview(review);
      return;
    }
    try {
      final receipt = await _api.fetchReceiptById(receiptId);
      if (!mounted) return;
      _showReceiptReviewSheet(review, receipt);
    } catch (e) {
      debugPrint('Failed to fetch receipt: $e');
      if (mounted) _openTripReview(review);
    }
  }

  // ── iOS-style top toast ──

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

  // ── Approve ──

  Future<void> _approveReview(Map<String, dynamic> review) async {
    final id = review['id']?.toString() ?? '';
    try {
      await _api.approvePendingReview(id);
      if (mounted) {
        setState(() {
          _reviews.removeWhere((r) => r['id']?.toString() == id);
          _readIds.remove(id);
        });
        _showToast('Review approved');
      }
    } catch (e) {
      if (mounted) _showToast('Failed: $e', isError: true);
    }
  }

  // ── Comment Sheet ──

  void _showCommentSheet(Map<String, dynamic> review) {
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
                  Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: Text('Add Comment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1F2937)))),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(width: 32, height: 32, decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle), alignment: Alignment.center, child: Icon(Icons.close, size: 18, color: Colors.grey.shade500)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Add a comment about this submission. The traveler will be notified.', style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.4)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _commentCtrl,
                    maxLines: 4, minLines: 3, autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'e.g. Please provide a clearer receipt image...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                      filled: true, fillColor: const Color(0xFFFAFAFA),
                      contentPadding: const EdgeInsets.all(14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.3))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.3))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(height: 48, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)), alignment: Alignment.center, child: Text('Cancel', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade600))),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: GestureDetector(
                        onTap: () async {
                          final text = _commentCtrl.text.trim();
                          if (text.isEmpty) return;
                          Navigator.pop(ctx);
                          try {
                            await _api.commentPendingReview(review['id'], text);
                            if (mounted) _showToast('Comment sent to traveler');
                          } catch (e) {
                            if (mounted) _showToast('Failed: $e', isError: true);
                          }
                        },
                        child: Container(height: 48, decoration: BoxDecoration(color: _purple, borderRadius: BorderRadius.circular(12)), alignment: Alignment.center, child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.chat_bubble_outline, size: 16, color: Colors.white), SizedBox(width: 8), Text('Send', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white))])),
                      )),
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

  // ── Receipt Review Sheet ──

  void _showReceiptReviewSheet(Map<String, dynamic> review, Receipt receipt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    const Expanded(child: Text('Review Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1F2937)))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: _gold.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 6, height: 6, decoration: const BoxDecoration(color: _gold, shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        const Text('Pending', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF9A7A2E))),
                      ]),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    if (receipt.imageUrl != null)
                      FutureBuilder<String?>(
                        future: AuthService.instance.getToken(),
                        builder: (_, snap) {
                          if (!snap.hasData) return Container(height: 200, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)), alignment: Alignment.center, child: const CircularProgressIndicator(color: _purple));
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: CachedNetworkImage(imageUrl: _api.receiptImageUrl(receipt.id), httpHeaders: {'Authorization': 'Bearer ${snap.data}'}, height: 220, width: double.infinity, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(height: 200, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)), alignment: Alignment.center, child: Icon(Icons.image_not_supported_outlined, size: 40, color: Colors.grey.shade400))),
                          );
                        },
                      ),
                    const SizedBox(height: 16),
                    _infoRow(Icons.person_outline, _purple, 'SUBMITTED BY', review['traveler_name'] ?? 'Unknown'),
                    const SizedBox(height: 10),
                    _infoRow(Icons.description_outlined, _purple, 'TRIP', review['trip_name'] ?? 'N/A'),
                    const SizedBox(height: 10),
                    _infoRow(Icons.calendar_today_outlined, const Color(0xFF9A7A2E), 'DATE SUBMITTED', _formatDate(review['created_at'])),
                    const SizedBox(height: 10),
                    _infoRow(Icons.sell_outlined, const Color(0xFF9A7A2E), 'CATEGORY', receipt.travelCategory ?? receipt.category ?? 'Uncategorized'),
                    if (receipt.merchant != null) ...[const SizedBox(height: 10), _infoRow(Icons.store_outlined, _purple, 'MERCHANT', receipt.merchant!)],
                    const SizedBox(height: 10),
                    _infoRow(Icons.attach_money, const Color(0xFF059669), 'AMOUNT', _currency.format(receipt.total)),
                    if (receipt.mealType != null) ...[const SizedBox(height: 10), _infoRow(Icons.restaurant_outlined, _gold, 'MEAL TYPE', receipt.mealType![0].toUpperCase() + receipt.mealType!.substring(1))],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              // Action buttons
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade100))),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(child: GestureDetector(
                        onTap: () { Navigator.pop(ctx); _approveReview(review); },
                        child: Container(height: 48, decoration: BoxDecoration(color: const Color(0xFFFDF6E3), borderRadius: BorderRadius.circular(12), border: Border.all(color: _gold.withValues(alpha: 0.3))), alignment: Alignment.center, child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check, size: 18, color: Color(0xFF9A7A2E)), SizedBox(width: 8), Text('Approve', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF9A7A2E)))])),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: GestureDetector(
                        onTap: () { Navigator.pop(ctx); _showCommentSheet(review); },
                        child: Container(height: 48, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _purple.withValues(alpha: 0.3))), alignment: Alignment.center, child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.chat_bubble_outline, size: 16, color: _purple), SizedBox(width: 8), Text('Add Comment', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _purple))])),
                      )),
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

  Widget _infoRow(IconData icon, Color color, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle), alignment: Alignment.center, child: Icon(icon, size: 20, color: color)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade400, letterSpacing: 0.8)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
        ])),
      ]),
    );
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return 'Unknown';
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return 'Unknown';
    return DateFormat('MMM d, yyyy').format(dt);
  }

  // ── Helpers ──

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Widget _buildAvatar(Map<String, dynamic> review, {double size = 46}) {
    final travelerEmail = review['traveler_email'] as String?;
    final travelerName = review['traveler_name'] as String? ?? '';
    final isReceipt = _isReceipt(review);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isReceipt
              ? [const Color(0xFFE8A824), const Color(0xFFD49B1F)]
              : [_purple, const Color(0xFF7B3FA0)],
        ),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: (travelerEmail != null && _token != null)
          ? CachedNetworkImage(
              imageUrl: _api.travelerImageUrl(travelerEmail),
              httpHeaders: {'Authorization': 'Bearer $_token'},
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Center(
                child: Text(
                  _initials(travelerName),
                  style: TextStyle(
                    fontSize: size * 0.34,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                _initials(travelerName),
                style: TextStyle(
                  fontSize: size * 0.34,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Column(
        children: [
          // ── Header ──
          Container(
            color: Colors.white,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Pending Reviews',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF1F2937)),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Icon(Icons.close, size: 18, color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Filter tabs ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                _tabChip('All', 'all', _unreadCount),
                const SizedBox(width: 16),
                _tabChip('Receipts', 'receipt', _receiptUnreadCount),
                const SizedBox(width: 16),
                _tabChip('Trips', 'trip', _tripUnreadCount),
              ],
            ),
          ),
          Container(height: 1, color: Colors.grey.shade200),

          // ── Content ──
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _purple))
                : RefreshIndicator(
                    color: _purple,
                    onRefresh: _fetchReviews,
                    child: filtered.isEmpty
                        ? ListView(children: [_buildEmptyState()])
                        : ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: filtered.length,
                            itemBuilder: (_, i) => _buildNotificationCard(filtered[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(String label, String value, int unreadCount) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? const Color(0xFF1F2937) : Colors.grey.shade500,
                ),
              ),
              if (unreadCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF1F2937) : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$unreadCount',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : Colors.grey.shade500,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 2,
            width: 40,
            color: selected ? const Color(0xFF3B82F6) : Colors.transparent,
          ),
        ],
      ),
    );
  }

  // ── Notification-style card ──

  Widget _buildNotificationCard(Map<String, dynamic> review) {
    final title = review['title'] as String? ?? 'New activity';
    final travelerName = review['traveler_name'] as String? ?? '';
    final timeAgo = _timeAgo(review['created_at']);
    final details = review['details'] as String?;
    final tripName = review['trip_name'] as String?;
    final isReceipt = _isReceipt(review);
    final reviewId = _rid(review);
    final isRead = _readIds.contains(reviewId);

    return GestureDetector(
      onTap: () {
        if (!isRead) setState(() => _readIds.add(reviewId));
        _onReviewTap(review);
      },
      child: Container(
        color: isRead ? Colors.white : const Color(0xFFF0F7FF),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Blue unread dot (hidden when read)
                  Padding(
                    padding: const EdgeInsets.only(top: 18, right: 10),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isRead ? Colors.transparent : const Color(0xFF3B82F6),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  // Avatar
                  _buildAvatar(review),
                  const SizedBox(width: 12),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title rich text
                        RichText(
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: const TextStyle(fontSize: 14, color: Color(0xFF1F2937), height: 1.4),
                            children: [
                              TextSpan(
                                text: travelerName,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              TextSpan(
                                text: ' ${_descriptionFromTitle(title, travelerName)}',
                              ),
                            ],
                          ),
                        ),
                        // Quoted details
                        if (details != null && details.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.only(left: 10),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(color: Colors.grey.shade300, width: 2.5),
                              ),
                            ),
                            child: Text(
                              '"$details"',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                fontStyle: FontStyle.italic,
                                height: 1.4,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        // Meta: badge + trip
                        if (tripName != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isReceipt ? _gold.withValues(alpha: 0.1) : _purple.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isReceipt ? 'Receipt' : 'Trip',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isReceipt ? const Color(0xFF9A7A2E) : _purple),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  tripName,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
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
                  // Time + three-dot menu
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        timeAgo,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 6),
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        iconSize: 20,
                        icon: Icon(Icons.more_horiz, size: 20, color: Colors.grey.shade400),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        color: Colors.white,
                        elevation: 8,
                        onSelected: (value) {
                          if (value == 'approve') _approveReview(review);
                          if (value == 'comment') _showCommentSheet(review);
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'approve',
                            child: Row(children: [
                              Icon(Icons.check_circle_outline, size: 18, color: const Color(0xFF9A7A2E)),
                              const SizedBox(width: 10),
                              const Text('Approve', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'comment',
                            child: Row(children: [
                              Icon(Icons.chat_bubble_outline, size: 18, color: _purple),
                              const SizedBox(width: 10),
                              const Text('Add Comment', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            ]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
          ],
        ),
      ),
    );
  }

  String _descriptionFromTitle(String title, String travelerName) {
    // Remove traveler name from the beginning if present
    var desc = title;
    if (desc.toLowerCase().startsWith(travelerName.toLowerCase())) {
      desc = desc.substring(travelerName.length).trimLeft();
    }
    // Remove leading dash or colon
    if (desc.startsWith('—') || desc.startsWith('-') || desc.startsWith(':')) {
      desc = desc.substring(1).trimLeft();
    }
    return desc;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(children: [
          Container(width: 72, height: 72, decoration: BoxDecoration(color: _purple.withValues(alpha: 0.08), shape: BoxShape.circle), alignment: Alignment.center, child: const Icon(Icons.assignment_outlined, size: 36, color: _purple)),
          const SizedBox(height: 16),
          const Text('No pending reviews', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
          const SizedBox(height: 6),
          Text('New submissions will appear here', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        ]),
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: widget.isError ? const Color(0xFFFEE2E2) : const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: widget.isError
                      ? const Color(0xFFFCA5A5)
                      : const Color(0xFF6EE7B7),
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
    );
  }
}
