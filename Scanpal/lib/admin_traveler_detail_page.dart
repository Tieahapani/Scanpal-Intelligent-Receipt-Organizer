import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'models/trip.dart';
import 'receipt.dart';
import 'api.dart';
import 'auth_service.dart';
import 'trip_detail_page.dart';
import 'admin_travelers_page.dart';
import 'receipt_detail_view_page.dart';

class AdminTravelerDetailPage extends StatefulWidget {
  final TravelerSummary traveler;
  final List<Trip> trips;
  final List<Receipt> receipts;
  final VoidCallback? onRefresh;

  const AdminTravelerDetailPage({
    super.key,
    required this.traveler,
    required this.trips,
    this.receipts = const [],
    this.onRefresh,
  });

  @override
  State<AdminTravelerDetailPage> createState() =>
      _AdminTravelerDetailPageState();
}

class _AdminTravelerDetailPageState extends State<AdminTravelerDetailPage> {
  final _api = APIService();
  final _currency = NumberFormat.simpleCurrency();
  final _searchCtrl = TextEditingController();

  int _activeTab = 0; // 0=receipts, 1=trips
  String _searchQuery = '';
  String _sortBy = 'newest';
  // Mutable copies for local actions (approve/discard)
  late List<Receipt> _receipts;
  late List<Trip> _trips;
  final Set<String> _approvedTripIds = {};
  final Set<String> _discardedTripIds = {};

  @override
  void initState() {
    super.initState();
    _receipts = List.from(widget.receipts);
    _trips = List.from(widget.trips);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─── Filtering & Sorting ───────────────────────────────

  List<Receipt> get _filteredReceipts {
    var list = List<Receipt>.from(_receipts);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((r) {
        final merchant = (r.merchant ?? '').toLowerCase();
        final category = (r.category ?? '').toLowerCase();
        return merchant.contains(q) || category.contains(q);
      }).toList();
    }
    list.sort((a, b) {
      switch (_sortBy) {
        case 'oldest':
          return (a.date ?? DateTime(2000)).compareTo(b.date ?? DateTime(2000));
        case 'highest':
          return b.total.compareTo(a.total);
        case 'lowest':
          return a.total.compareTo(b.total);
        default: // newest
          return (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000));
      }
    });
    return list;
  }

  List<Trip> get _filteredTrips {
    var list = List<Trip>.from(_trips);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((t) {
        final name = t.displayTitle.toLowerCase();
        final dest = (t.destination ?? '').toLowerCase();
        return name.contains(q) || dest.contains(q);
      }).toList();
    }
    list.sort((a, b) {
      switch (_sortBy) {
        case 'oldest':
          return (a.departureDate ?? DateTime(2000))
              .compareTo(b.departureDate ?? DateTime(2000));
        case 'highest':
          return b.totalExpenses.compareTo(a.totalExpenses);
        case 'lowest':
          return a.totalExpenses.compareTo(b.totalExpenses);
        default:
          return (b.departureDate ?? DateTime(2000))
              .compareTo(a.departureDate ?? DateTime(2000));
      }
    });
    return list;
  }

  String get _totalSpentFormatted => NumberFormat.simpleCurrency().format(widget.traveler.totalSpent);

  // ─── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Column(
        children: [
          _buildHeader(),
          _buildProfileCard(),
          _buildTabToggle(),
          _buildSearchSortBar(),
          Expanded(
            child: _activeTab == 0
                ? _buildReceiptsList()
                : _buildTripsList(),
          ),
        ],
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────

  Widget _buildHeader() {
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
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.arrow_back_ios_new,
                      size: 14, color: Color(0xFF4B5563)),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Traveler Details',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Gold Profile Card ─────────────────────────────────

  Widget _buildProfileCard() {
    final t = widget.traveler;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFDF6E3), Color(0xFFFBF0D1)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFFE8A824).withValues(alpha: 0.2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Gradient top bar
            Container(
              height: 3,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF46166B),
                    Color(0xFFE8A824),
                    Color(0xFF46166B)
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                children: [
                  // Avatar + Info row
                  Row(
                    children: [
                      _travelerAvatar(t.email, t.name, 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (t.department != null &&
                                t.department!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                t.department!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF9A7A2E),
                                ),
                              ),
                            ],
                            const SizedBox(height: 1),
                            Text(
                              t.email,
                              style: TextStyle(
                                fontSize: 10,
                                color: const Color(0xFF9A7A2E)
                                    .withValues(alpha: 0.7),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Divider
                  Container(
                    height: 1,
                    color: const Color(0xFFE8A824).withValues(alpha: 0.15),
                  ),
                  const SizedBox(height: 12),
                  // Stats row
                  Row(
                    children: [
                      _goldStat('${_receipts.length}', 'Receipts'),
                      _goldStat('${_trips.length}', 'Trips'),
                      _goldStat(_totalSpentFormatted, 'Total'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _goldStat(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: Color(0xFF9A7A2E),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Tab Toggle ────────────────────────────────────────

  Widget _buildTabToggle() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _tabButton(0, Icons.description_outlined, 'Receipts'),
            _tabButton(1, Icons.folder_outlined, 'Trips'),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(int index, IconData icon, String label) {
    final selected = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _activeTab = index;
          _searchQuery = '';
          _searchCtrl.clear();
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF46166B) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF46166B).withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 14,
                  color:
                      selected ? Colors.white : Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color:
                      selected ? Colors.white : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Search + Sort Bar ─────────────────────────────────

  Widget _buildSearchSortBar() {
    final isFiltered = _sortBy != 'newest';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Row(
        children: [
          // Search field
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF111827)),
                decoration: InputDecoration(
                  hintText: _activeTab == 0
                      ? 'Search receipts...'
                      : 'Search trips...',
                  hintStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade400),
                  prefixIcon: Icon(Icons.search,
                      size: 14, color: Colors.grey.shade400),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                          child: Icon(Icons.close,
                              size: 14, color: Colors.grey.shade400),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 4),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Sort button
          GestureDetector(
            onTap: _showSortSheet,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isFiltered
                    ? const Color(0xFF46166B).withValues(alpha: 0.08)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isFiltered
                      ? const Color(0xFF46166B).withValues(alpha: 0.2)
                      : Colors.grey.shade200,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_vert_rounded,
                      size: 14,
                      color: isFiltered
                          ? const Color(0xFF46166B)
                          : Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text(
                    'Sort',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isFiltered
                          ? const Color(0xFF46166B)
                          : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Receipts List ─────────────────────────────────────

  Widget _buildReceiptsList() {
    final receipts = _filteredReceipts;
    if (receipts.isEmpty) {
      return _buildEmptyState(Icons.description_outlined, 'No receipts');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      itemCount: receipts.length,
      itemBuilder: (_, i) => _buildReceiptCard(receipts[i]),
    );
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

  Widget _mealTypeBadge(String mealType) {
    final color = _mealTypeColors[mealType] ?? const Color(0xFF6B7280);
    final label = _mealTypeLabels[mealType] ?? mealType;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildReceiptCard(Receipt receipt) {
    final dateStr = receipt.date != null
        ? DateFormat('MMM d, yyyy').format(receipt.date!)
        : '';
    final cardLabel =
        receipt.paymentMethod == 'corporate' ? 'AS Amex' : 'Personal';
    final cardColor = receipt.paymentMethod == 'corporate'
        ? const Color(0xFF46166B)
        : const Color(0xFFE8A824);
    final category = receipt.category ?? receipt.travelCategory ?? 'Other';
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReceiptDetailViewPage(
              receipt: receipt,
              trips: _trips,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
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
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Receipt image thumbnail
              _receiptThumb(receipt, category),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        // Category badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                        // Card type badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cardColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            cardLabel,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: cardColor,
                            ),
                          ),
                        ),
                        // Meal type badge
                        if (receipt.mealType != null)
                          _mealTypeBadge(receipt.mealType!),
                      ],
                    ),
                  ],
                ),
              ),
              // Amount + date
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _currency.format(receipt.total),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade300,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade300),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Trips List ────────────────────────────────────────

  Widget _buildTripsList() {
    final trips = _filteredTrips;
    if (trips.isEmpty) {
      return _buildEmptyState(Icons.folder_outlined, 'No trips');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      itemCount: trips.length,
      itemBuilder: (_, i) => _buildTripCard(trips[i]),
    );
  }

  Widget _buildTripCard(Trip trip) {
    final isApproved = _approvedTripIds.contains(trip.id.toString()) ||
        trip.status?.toLowerCase() == 'approved';
    final isDiscarded = _discardedTripIds.contains(trip.id.toString()) ||
        trip.status?.toLowerCase() == 'discarded';

    String statusLabel;
    Color statusColor;
    Color statusBg;
    Color dotColor;
    IconData? statusIcon;
    if (isDiscarded) {
      statusLabel = 'Discarded';
      statusColor = const Color(0xFFC0392B);
      statusBg = const Color(0xFFC0392B).withValues(alpha: 0.08);
      dotColor = const Color(0xFFC0392B);
      statusIcon = Icons.cancel;
    } else if (isApproved) {
      statusLabel = 'Approved';
      statusColor = const Color(0xFF059669);
      statusBg = const Color(0xFF059669).withValues(alpha: 0.08);
      dotColor = const Color(0xFF059669);
      statusIcon = Icons.check_circle;
    } else if (trip.isActive) {
      statusLabel = 'Active';
      statusColor = const Color(0xFF059669);
      statusBg = const Color(0xFF059669).withValues(alpha: 0.08);
      dotColor = const Color(0xFF34D399);
    } else if (trip.isUpcoming) {
      statusLabel = 'Upcoming';
      statusColor = const Color(0xFFB8860B);
      statusBg = const Color(0xFFE8A824).withValues(alpha: 0.1);
      dotColor = const Color(0xFFE8A824);
    } else {
      statusLabel = 'Completed';
      statusColor = const Color(0xFF46166B);
      statusBg = const Color(0xFF46166B).withValues(alpha: 0.08);
      dotColor = const Color(0xFF46166B);
    }

    final receiptCount = _receipts.where((r) => r.tripId == trip.id.toString()).length;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TripDetailPage(trip: trip)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
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
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              // Top row: icon + name + status
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _tripThumb(trip),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.displayTitle,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (trip.destination != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            trip.destination!,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (statusIcon != null)
                          Icon(statusIcon, size: 10, color: statusColor)
                        else
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: dotColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        const SizedBox(width: 4),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Details row
              Padding(
                padding: const EdgeInsets.only(left: 52, top: 12),
                child: Row(
                  children: [
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today_outlined,
                              size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _formatDateRange(
                                  trip.departureDate, trip.returnDate),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(Icons.description_outlined,
                              size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(
                            '$receiptCount',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _currency.format(trip.totalExpenses),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade300),
                  ],
                ),
              ),
              // Form status badge
              if (trip.status != null && trip.status!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 52, top: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _formStatusColors(trip.status!).bg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: _formStatusColors(trip.status!).dot,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              trip.status!,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _formStatusColors(trip.status!).text,
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
      ),
    );
  }

  // ─── Sort Bottom Sheet ─────────────────────────────────

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Sort By',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close,
                        size: 20, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
            ...[
              ('newest', 'Newest First'),
              ('oldest', 'Oldest First'),
              ('highest', 'Highest Amount'),
              ('lowest', 'Lowest Amount'),
            ].map((option) {
              final selected = _sortBy == option.$1;
              return GestureDetector(
                onTap: () {
                  setState(() => _sortBy = option.$1);
                  Navigator.pop(context);
                },
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF46166B).withValues(alpha: 0.08)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        option.$2,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? const Color(0xFF46166B)
                              : Colors.grey.shade600,
                        ),
                      ),
                      if (selected)
                        const Icon(Icons.check,
                            size: 16, color: Color(0xFF46166B)),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ─── Form Status Colors ────────────────────────────────

  static ({Color dot, Color text, Color bg}) _formStatusColors(String status) {
    switch (status) {
      case 'No ODTA Submitted':
        return (dot: const Color(0xFF9CA3AF), text: const Color(0xFF6B7280), bg: const Color(0xFFF3F4F6));
      case 'TAAR Sent':
        return (dot: const Color(0xFFA855F7), text: const Color(0xFF7E22CE), bg: const Color(0xFFF3E8FF));
      case 'TAAR Reviewed':
        return (dot: const Color(0xFFE8A824), text: const Color(0xFFB8860B), bg: const Color(0xFFFFF8E1));
      case 'TAAR Processed':
        return (dot: const Color(0xFF7B3FA0), text: const Color(0xFF46166B), bg: const Color(0xFFF0E6F6));
      case 'TC Sent':
        return (dot: const Color(0xFFA855F7), text: const Color(0xFF7E22CE), bg: const Color(0xFFF3E8FF));
      case 'TC Pending Review':
        return (dot: const Color(0xFFE8A824), text: const Color(0xFFB8860B), bg: const Color(0xFFFFF8E1));
      case 'TC Correction Needed':
        return (dot: const Color(0xFFD97706), text: const Color(0xFF92400E), bg: const Color(0xFFFEF3C7));
      case 'TC Processed':
        return (dot: const Color(0xFF7B3FA0), text: const Color(0xFF46166B), bg: const Color(0xFFF0E6F6));
      case 'Approved':
        return (dot: const Color(0xFF46166B), text: const Color(0xFF46166B), bg: const Color(0xFFF0E6F6));
      default:
        return (dot: const Color(0xFFA78BFA), text: const Color(0xFF7C3AED), bg: const Color(0xFFF5F3FF));
    }
  }

  // ─── Helpers ───────────────────────────────────────────

  Widget _buildEmptyState(IconData icon, String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 28, color: Colors.grey.shade300),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tripThumb(Trip trip) {
    final fallback = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFFE8A824).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.location_on_outlined,
          size: 17, color: Color(0xFFD49B1F)),
    );

    if (trip.coverImageUrl == null || trip.coverImageUrl!.isEmpty) {
      return fallback;
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: CachedNetworkImage(
        imageUrl: trip.coverImageUrl!,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }

  Widget _receiptThumb(Receipt receipt, String category) {
    return FutureBuilder<String?>(
      future: AuthService.instance.getToken(),
      builder: (context, tokenSnap) {
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: (receipt.imageUrl != null &&
                  receipt.imageUrl!.isNotEmpty &&
                  tokenSnap.hasData)
              ? CachedNetworkImage(
                  imageUrl: _api.receiptImageUrl(receipt.id),
                  httpHeaders: {
                    'Authorization': 'Bearer ${tokenSnap.data}'
                  },
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Center(
                    child: Icon(_categoryIcon(category),
                        size: 18, color: const Color(0xFF46166B)),
                  ),
                )
              : Center(
                  child: Icon(_categoryIcon(category),
                      size: 18, color: const Color(0xFF46166B)),
                ),
        );
      },
    );
  }

  IconData _categoryIcon(String category) {
    final c = category.toLowerCase();
    if (c.contains('transport') || c.contains('flight') || c.contains('uber') || c.contains('lyft')) {
      return Icons.directions_car_outlined;
    }
    if (c.contains('meal') || c.contains('food') || c.contains('dinner') || c.contains('lunch')) {
      return Icons.restaurant_outlined;
    }
    if (c.contains('lodg') || c.contains('hotel') || c.contains('accommodation')) {
      return Icons.hotel_outlined;
    }
    if (c.contains('registration') || c.contains('conference')) {
      return Icons.confirmation_number_outlined;
    }
    return Icons.receipt_outlined;
  }

  Widget _travelerAvatar(String email, String name, double size) {
    return FutureBuilder<String?>(
      future: AuthService.instance.getToken(),
      builder: (context, tokenSnap) {
        if (!tokenSnap.hasData) return _initials(name, size);
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(shape: BoxShape.circle),
          clipBehavior: Clip.antiAlias,
          child: CachedNetworkImage(
            imageUrl: _api.travelerImageUrl(email),
            httpHeaders: {'Authorization': 'Bearer ${tokenSnap.data}'},
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => _initials(name, size),
          ),
        );
      },
    );
  }

  Widget _initials(String name, double size) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final ini = parts.length >= 2
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
        ini,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.30,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatDateRange(DateTime? start, DateTime? end) {
    if (start == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final s = '${months[start.month - 1]} ${start.day}';
    if (end == null || end == start) return '$s, ${start.year}';
    return '$s–${months[end.month - 1]} ${end.day}, ${end.year}';
  }
}
