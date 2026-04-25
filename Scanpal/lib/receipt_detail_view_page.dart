import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'receipt.dart';
import 'models/trip.dart';
import 'api.dart';
import 'auth_service.dart';
import 'receipt_detail_page.dart';

/// Standalone receipt detail view — used from both ReceiptsPage and TravelerHomePage.
class ReceiptDetailViewPage extends StatefulWidget {
  final Receipt receipt;
  final List<Trip> trips;

  const ReceiptDetailViewPage({
    super.key,
    required this.receipt,
    required this.trips,
  });

  @override
  State<ReceiptDetailViewPage> createState() => _ReceiptDetailViewPageState();
}

class _ReceiptDetailViewPageState extends State<ReceiptDetailViewPage> {
  final _api = APIService();
  final _commentCtrl = TextEditingController();
  bool _isAdmin = false;

  static const _categoryLabels = {
    'Accommodation Cost': 'Accommodation',
    'Flight Cost': 'Flight',
    'Ground Transportation': 'Ground Transport',
    'Registration Cost': 'Registration',
    'Other AS Cost': 'Other AS Cost',
  };

  Receipt get receipt => widget.receipt;
  List<Trip> get trips => widget.trips;

  String get _category {
    final cat = receipt.travelCategory ?? receipt.category ?? 'Other AS Cost';
    return _categoryLabels[cat] ?? cat;
  }

  String get _tripName {
    if (receipt.tripId == null) return 'General';
    final trip = trips.where((t) => t.id == receipt.tripId).firstOrNull;
    return trip?.displayTitle ?? 'General';
  }

  @override
  void initState() {
    super.initState();
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

  // ─── iOS-style top toast ──────────────────────────────

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

  // ─── Approve Receipt ─────────────────────────────────

  Future<void> _approveReceipt() async {
    try {
      await _api.approveReceipt(receipt.id);
      if (mounted) _showToast('Receipt approved');
    } catch (e) {
      if (mounted) _showToast('Failed to approve: $e', isError: true);
    }
  }

  // ─── Send Comment ────────────────────────────────────

  Future<void> _sendComment() async {
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

  // ─── Delete Receipt ──────────────────────────────────

  Future<void> _confirmDelete() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
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
              children: [
                Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(color: const Color(0xFFFEE2E2), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const Icon(Icons.delete_outline, size: 28, color: Color(0xFFEF4444)),
                ),
                const SizedBox(height: 16),
                const Text('Delete Receipt?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
                const SizedBox(height: 8),
                Text(
                  'This will permanently delete this receipt. This action cannot be undone.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, false),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                        alignment: Alignment.center,
                        child: Text('Cancel', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                      ),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, true),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(12)),
                        alignment: Alignment.center,
                        child: const Text('Delete', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    )),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deleteReceipt(receipt.id);
      if (!mounted) return;
      _showToast('Receipt deleted');
      Navigator.pop(context, 'deleted');
    } catch (e) {
      if (mounted) _showToast('Failed to delete: $e', isError: true);
    }
  }

  // ─── Comment Sheet ───────────────────────────────────

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

  // ─── Admin Action Buttons ────────────────────────────

  Widget _buildAdminActions() {
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
                  onTap: _approveReceipt,
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = receipt.date != null
        ? DateFormat('MMM d, y').format(receipt.date!)
        : 'Unknown';

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
                    const Expanded(
                      child: Text(
                        'Receipt Details',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _confirmDelete(),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)),
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
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        _buildDetailImage(context),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
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
                              _category,
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
                  value: _tripName,
                ),

                // Line items if available
                if (receipt.items.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildLineItems(),
                ],
              ],
            ),
          ),

          // Admin actions at bottom
          if (_isAdmin) _buildAdminActions(),
        ],
      ),
    );
  }

  Widget _buildDetailImage(BuildContext context) {
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
        return CachedNetworkImage(imageUrl:
          url,
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

  Widget _buildLineItems() {
    return Container(
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
