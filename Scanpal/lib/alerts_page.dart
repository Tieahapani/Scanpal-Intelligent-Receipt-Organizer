import 'package:flutter/material.dart';
import 'api.dart';
import 'models/trip.dart';
import 'receipt.dart';

class AlertsPage extends StatefulWidget {
  final List<Trip> trips;
  final List<Receipt> receipts;
  final String userName;
  final VoidCallback onTripTap;
  final List<Map<String, dynamic>> initialAlerts;

  const AlertsPage({
    super.key,
    required this.trips,
    required this.receipts,
    required this.userName,
    required this.onTripTap,
    this.initialAlerts = const [],
  });

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> with SingleTickerProviderStateMixin {
  static const _purple = Color(0xFF46166B);
  static const _gold = Color(0xFFE8A824);

  final _api = APIService();
  late TabController _tabController;
  List<Map<String, dynamic>> _alerts = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
    // Use cached alerts from home page immediately, then refresh in background
    _alerts = List<Map<String, dynamic>>.from(
      widget.initialAlerts.map((a) => Map<String, dynamic>.from(a)),
    );
    _fetchAlerts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchAlerts() async {
    try {
      await _api.triggerAlertGeneration();
      final alerts = await _api.fetchAlerts();
      if (mounted) setState(() => _alerts = alerts);
    } catch (e) {
      debugPrint('Failed to fetch alerts: $e');
    }
  }

  Future<void> _updateStatus(String alertId, String newStatus) async {
    // Optimistic update
    setState(() {
      final idx = _alerts.indexWhere((a) => a['id'] == alertId);
      if (idx != -1) _alerts[idx]['status'] = newStatus;
    });
    try {
      await _api.updateAlertStatus(alertId, newStatus);
    } catch (e) {
      debugPrint('Failed to update alert status: $e');
      _fetchAlerts(); // re-fetch on failure
    }
  }

  List<Map<String, dynamic>> _filtered(String status) {
    return _alerts.where((a) => a['status'] == status).toList();
  }

  // ── Alert display helpers ──

  _AlertStyle _styleFor(Map<String, dynamic> alert) {
    final type = alert['type'] ?? '';
    switch (type) {
      case 'trip_end_reminder':
        return _AlertStyle(
          icon: Icons.flight_land_rounded,
          color: const Color(0xFFF59E0B),
        );
      case 'pre_travel_reminder':
        return _AlertStyle(
          icon: Icons.flight_takeoff_rounded,
          color: const Color(0xFF6366F1),
        );
      case 'status_change':
        final msg = (alert['message'] ?? '').toString().toLowerCase();
        if (msg.contains('approved') || msg.contains('great news')) {
          return _AlertStyle(
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF10B981),
          );
        } else if (msg.contains('denied') || msg.contains('issue') || msg.contains('revision')) {
          return _AlertStyle(
            icon: Icons.error_rounded,
            color: const Color(0xFFEF4444),
          );
        }
        return _AlertStyle(
          icon: Icons.update_rounded,
          color: _purple,
        );
      case 'admin_comment':
        return _AlertStyle(
          icon: Icons.comment_rounded,
          color: const Color(0xFF3B82F6),
        );
      case 'traveler_action':
        final title = (alert['title'] ?? '').toString().toLowerCase();
        if (title.contains('receipt uploaded') || title.contains('image attached')) {
          return _AlertStyle(
            icon: Icons.receipt_long_rounded,
            color: const Color(0xFF10B981),
          );
        } else if (title.contains('trip') && title.contains('created')) {
          return _AlertStyle(
            icon: Icons.flight_takeoff_rounded,
            color: const Color(0xFF3B82F6),
          );
        } else if (title.contains('deleted')) {
          return _AlertStyle(
            icon: Icons.delete_outline_rounded,
            color: const Color(0xFFEF4444),
          );
        } else if (title.contains('updated')) {
          return _AlertStyle(
            icon: Icons.edit_rounded,
            color: const Color(0xFFF59E0B),
          );
        }
        return _AlertStyle(
          icon: Icons.person_rounded,
          color: const Color(0xFF8B5CF6),
        );
      case 'trip_approved':
        return _AlertStyle(
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF10B981),
        );
      case 'trip_discarded':
        return _AlertStyle(
          icon: Icons.cancel_rounded,
          color: const Color(0xFFEF4444),
        );
      default:
        return _AlertStyle(
          icon: Icons.notifications_rounded,
          color: _purple,
        );
    }
  }

  String _typeLabel(Map<String, dynamic> alert) {
    switch (alert['type']) {
      case 'trip_end_reminder': return 'TC Reminder';
      case 'pre_travel_reminder': return 'TAAR Reminder';
      case 'status_change': return 'Status Update';
      case 'admin_comment': return 'Admin Note';
      case 'traveler_action': return 'Traveler Activity';
      case 'trip_approved': return 'Trip Approved';
      case 'trip_discarded': return 'Trip Discarded';
      default: return 'Alert';
    }
  }

  String _timeAgo(String? isoDate) {
    if (isoDate == null) return '';
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return '';
    final diff = DateTime.now().toUtc().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final inbox = _filtered('inbox');
    final read = _filtered('read');
    final completed = _filtered('completed');

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Column(
        children: [
          // ── Purple gradient header ──
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF5A1E8E), _purple],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 20, 0),
                child: Column(
                  children: [
                    // Top bar
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Alerts',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (inbox.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _gold,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${inbox.length} new',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _purple,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Tab bar
                    Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelColor: _purple,
                        unselectedLabelColor: Colors.white.withValues(alpha: 0.8),
                        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        tabs: [
                          Tab(text: 'Inbox${inbox.isNotEmpty ? ' (${inbox.length})' : ''}'),
                          Tab(text: 'Read${read.isNotEmpty ? ' (${read.length})' : ''}'),
                          Tab(text: 'Done${completed.isNotEmpty ? ' (${completed.length})' : ''}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),

          // ── Tab content ──
          Expanded(
            child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTab(inbox, _Tab.inbox),
                      _buildTab(read, _Tab.read),
                      _buildTab(completed, _Tab.completed),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(List<Map<String, dynamic>> alerts, _Tab tab) {
    if (alerts.isEmpty) return _buildEmptyState(tab);
    return RefreshIndicator(
      color: _purple,
      onRefresh: _fetchAlerts,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
        itemCount: alerts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildAlertCard(alerts[i], tab),
      ),
    );
  }

  Widget _buildEmptyState(_Tab tab) {
    final (IconData icon, String title, String subtitle) = switch (tab) {
      _Tab.inbox => (Icons.check_circle_outline, 'All clear!', 'No alerts at the moment'),
      _Tab.read => (Icons.drafts_rounded, 'Nothing here', 'Alerts you\'ve read will appear here'),
      _Tab.completed => (Icons.task_alt_rounded, 'No completed actions', 'Completed alerts will appear here'),
    };

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 36, color: const Color(0xFF10B981)),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert, _Tab tab) {
    final style = _styleFor(alert);
    final title = alert['title'] ?? 'Alert';
    final message = alert['message'] ?? '';
    final alertId = alert['id'] as String;
    final isCompleted = tab == _Tab.completed;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCompleted ? const Color(0xFFF9FAFB) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(
            color: isCompleted ? const Color(0xFF10B981) : style.color,
            width: 4,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? const Color(0xFF10B981).withValues(alpha: 0.1)
                      : style.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  isCompleted ? Icons.check_circle_rounded : style.icon,
                  size: 18,
                  color: isCompleted ? const Color(0xFF10B981) : style.color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isCompleted
                            ? Colors.grey.shade500
                            : const Color(0xFF1F2937),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          _typeLabel(alert),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isCompleted ? Colors.grey.shade400 : style.color,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _timeAgo(alert['created_at']),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Message
          Text(
            message,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: isCompleted ? Colors.grey.shade400 : Colors.grey.shade700,
            ),
          ),
          // Action buttons
          const SizedBox(height: 12),
          Row(
            children: [
              if (tab == _Tab.inbox) ...[
                if (alert['type'] == 'trip_end_reminder') ...[
                  _actionChip(
                    icon: Icons.check_circle_rounded,
                    label: 'Receipts Submitted',
                    color: const Color(0xFF059669),
                    onTap: () => _updateStatus(alertId, 'dismissed'),
                  ),
                  const SizedBox(width: 8),
                  _actionChip(
                    icon: Icons.schedule_rounded,
                    label: 'Pending',
                    color: const Color(0xFFF59E0B),
                    onTap: () => _updateStatus(alertId, 'read'),
                  ),
                ] else
                  _actionChip(
                    icon: Icons.mark_email_read_rounded,
                    label: 'Mark as Read',
                    color: _purple,
                    onTap: () => _updateStatus(alertId, 'read'),
                  ),
              ],
              if (tab == _Tab.read) ...[
                if (alert['type'] == 'trip_end_reminder') ...[
                  _actionChip(
                    icon: Icons.check_circle_rounded,
                    label: 'Receipts Submitted',
                    color: const Color(0xFF059669),
                    onTap: () => _updateStatus(alertId, 'dismissed'),
                  ),
                  const SizedBox(width: 8),
                  _actionChip(
                    icon: Icons.move_to_inbox_rounded,
                    label: 'Back to Inbox',
                    color: Colors.grey.shade600,
                    onTap: () => _updateStatus(alertId, 'inbox'),
                  ),
                ] else ...[
                  _actionChip(
                    icon: Icons.task_alt_rounded,
                    label: 'Mark Completed',
                    color: const Color(0xFF059669),
                    onTap: () => _updateStatus(alertId, 'completed'),
                  ),
                  const SizedBox(width: 8),
                  _actionChip(
                    icon: Icons.move_to_inbox_rounded,
                    label: 'Back to Inbox',
                    color: Colors.grey.shade600,
                    onTap: () => _updateStatus(alertId, 'inbox'),
                  ),
                ],
              ],
              if (tab == _Tab.completed)
                _actionChip(
                  icon: Icons.move_to_inbox_rounded,
                  label: 'Move to Inbox',
                  color: Colors.grey.shade600,
                  onTap: () => _updateStatus(alertId, 'inbox'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertStyle {
  final IconData icon;
  final Color color;
  const _AlertStyle({required this.icon, required this.color});
}

enum _Tab { inbox, read, completed }
