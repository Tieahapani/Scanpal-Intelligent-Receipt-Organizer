import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'models/trip.dart';
import 'receipt.dart';
import 'api.dart';
import 'auth_service.dart';
import 'admin_traveler_detail_page.dart';

class TravelerSummary {
  final String name;
  final String email;
  final String? department;
  final int tripCount;
  final double totalSpent;
  final int receiptCount;

  const TravelerSummary({
    required this.name,
    required this.email,
    required this.department,
    required this.tripCount,
    required this.totalSpent,
    required this.receiptCount,
  });
}

class AdminTravelersPage extends StatefulWidget {
  final List<Trip> trips;
  final List<Receipt> receipts;
  final VoidCallback? onRefresh;

  const AdminTravelersPage({
    super.key,
    required this.trips,
    required this.receipts,
    this.onRefresh,
  });

  @override
  State<AdminTravelersPage> createState() => _AdminTravelersPageState();
}

class _AdminTravelersPageState extends State<AdminTravelersPage> {
  static const _recentKey = 'recent_viewed_travelers';
  static const _maxRecent = 5;

  final _currency = NumberFormat.simpleCurrency();
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';
  List<String> _recentEmails = [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_recentKey) ?? [];
    if (mounted) setState(() => _recentEmails = list);
  }

  Future<void> _addToRecent(String email) async {
    final prefs = await SharedPreferences.getInstance();
    _recentEmails.remove(email);
    _recentEmails.insert(0, email);
    if (_recentEmails.length > _maxRecent) {
      _recentEmails = _recentEmails.sublist(0, _maxRecent);
    }
    await prefs.setStringList(_recentKey, _recentEmails);
  }

  // ─── Data ──────────────────────────────────────────────

  Map<String, int> get _receiptsPerTraveler {
    final Map<String, String> tripIdToEmail = {};
    for (final trip in widget.trips) {
      tripIdToEmail[trip.id.toString()] = trip.travelerEmail;
    }
    final Map<String, int> counts = {};
    for (final receipt in widget.receipts) {
      final tid = receipt.tripId;
      if (tid == null) continue;
      final email = tripIdToEmail[tid];
      if (email != null && email.isNotEmpty) {
        counts[email] = (counts[email] ?? 0) + 1;
      }
    }
    return counts;
  }

  void _addTripToSummary(Map<String, TravelerSummary> map, String email, Trip trip, {String? name, String? department}) {
    final existing = map[email];
    if (existing != null) {
      map[email] = TravelerSummary(
        name: (name != null && name.isNotEmpty) ? name : existing.name,
        email: email,
        department: department ?? existing.department,
        tripCount: existing.tripCount + 1,
        totalSpent: existing.totalSpent + trip.totalExpenses,
        receiptCount: 0,
      );
    } else {
      map[email] = TravelerSummary(
        name: name ?? email,
        email: email,
        department: department,
        tripCount: 1,
        totalSpent: trip.totalExpenses,
        receiptCount: 0,
      );
    }
  }

  List<TravelerSummary> get _allTravelers {
    final Map<String, TravelerSummary> map = {};
    for (final trip in widget.trips) {
      // Count for primary traveler
      final email = trip.travelerEmail;
      if (email.isNotEmpty) {
        _addTripToSummary(map, email, trip,
          name: trip.travelerName, department: trip.department);
      }
      // Count for co-travelers
      if (trip.travelers != null && trip.travelers!.isNotEmpty) {
        for (final coEmail in trip.travelers!.split(',')) {
          final trimmed = coEmail.trim();
          if (trimmed.isNotEmpty && trimmed != email) {
            _addTripToSummary(map, trimmed, trip, department: trip.department);
          }
        }
      }
    }
    final receiptCounts = _receiptsPerTraveler;
    return map.entries.map((e) => TravelerSummary(
      name: e.value.name,
      email: e.value.email,
      department: e.value.department,
      tripCount: e.value.tripCount,
      totalSpent: e.value.totalSpent,
      receiptCount: receiptCounts[e.key] ?? 0,
    )).toList()
      ..sort((a, b) => b.tripCount.compareTo(a.tripCount));
  }

  List<TravelerSummary> get _searchResults {
    if (_query.isEmpty) return [];
    final q = _query.toLowerCase();
    return _allTravelers.where((t) =>
      t.name.toLowerCase().contains(q) ||
      t.email.toLowerCase().contains(q) ||
      (t.department?.toLowerCase().contains(q) ?? false)
    ).toList();
  }

  List<TravelerSummary> get _recentTravelers {
    final all = _allTravelers;
    final list = <TravelerSummary>[];
    for (final email in _recentEmails) {
      final match = all.where((t) => t.email == email);
      if (match.isNotEmpty) list.add(match.first);
    }
    return list;
  }

  void _openTraveler(TravelerSummary traveler) async {
    await _addToRecent(traveler.email);
    if (!mounted) return;
    final travelerTrips = widget.trips
        .where((t) =>
          t.travelerEmail == traveler.email ||
          (t.travelers != null && t.travelers!.contains(traveler.email)))
        .toList();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminTravelerDetailPage(
          traveler: traveler,
          trips: travelerTrips,
          receipts: widget.receipts.where((r) =>
            travelerTrips.any((t) => t.id.toString() == r.tripId)
          ).toList(),
          onRefresh: widget.onRefresh,
        ),
      ),
    );
    widget.onRefresh?.call();
    _loadRecent(); // refresh recent list
  }

  // ─── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isSearching = _query.isNotEmpty;
    final results = _searchResults;
    final recent = _recentTravelers;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: isSearching
                ? _buildSearchResults(results)
                : _buildDefaultView(recent),
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            children: [
              // Back + title
              Row(
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
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        size: 14,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Find Traveler',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF46166B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_allTravelers.length}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF46166B),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Search bar — large and prominent
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _focusNode,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF111827),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search by name or email...',
                    hintStyle: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey.shade400,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 14, right: 10),
                      child: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    suffixIcon: _query.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Colors.grey.shade400,
                            ),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 4,
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

  // ─── Default View (no search) ──────────────────────────

  Widget _buildDefaultView(List<TravelerSummary> recent) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recent.isNotEmpty) ...[
            // Recently viewed section
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Row(
                children: [
                  Icon(Icons.history_rounded,
                      size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 6),
                  Text(
                    'Recently Viewed',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            ...recent.map(_buildTravelerCard),
            const SizedBox(height: 24),
          ],
          // Prompt to search
          _buildSearchPrompt(recent.isEmpty),
        ],
      ),
    );
  }

  Widget _buildSearchPrompt(bool noRecent) {
    return Center(
      child: Padding(
        padding: EdgeInsets.only(top: noRecent ? 80 : 16),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF46166B).withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.person_search_rounded,
                size: 28,
                color: const Color(0xFF46166B).withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              noRecent
                  ? 'Search for a traveler'
                  : 'Type to find more travelers',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Search by name or email to get started',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Search Results ────────────────────────────────────

  Widget _buildSearchResults(List<TravelerSummary> results) {
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'No travelers match "$_query"',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: results.length + 1, // +1 for result count header
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
            child: Text(
              '${results.length} result${results.length == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade400,
              ),
            ),
          );
        }
        return _buildTravelerCard(results[i - 1]);
      },
    );
  }

  // ─── Traveler Card ─────────────────────────────────────

  Widget _buildTravelerCard(TravelerSummary traveler) {
    return GestureDetector(
      onTap: () => _openTraveler(traveler),
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
            _travelerAvatar(traveler.email, traveler.name, 44),
            const SizedBox(width: 12),
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
                      _statChip('${traveler.receiptCount}', 'receipts'),
                      const SizedBox(width: 12),
                      _statChip('${traveler.tripCount}', 'trips'),
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

  Widget _statChip(String value, String label) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          color: Color(0xFF9CA3AF),
        ),
        children: [
          TextSpan(
            text: value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF4B5563),
            ),
          ),
          TextSpan(text: ' $label'),
        ],
      ),
    );
  }

  // ─── Avatar ────────────────────────────────────────────

  Widget _travelerAvatar(String email, String name, double size) {
    final api = APIService();
    return FutureBuilder<String?>(
      future: AuthService.instance.getToken(),
      builder: (context, tokenSnap) {
        if (!tokenSnap.hasData) return _initialsAvatar(name, size);
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(shape: BoxShape.circle),
          clipBehavior: Clip.antiAlias,
          child: CachedNetworkImage(
            imageUrl: api.travelerImageUrl(email),
            httpHeaders: {'Authorization': 'Bearer ${tokenSnap.data}'},
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => _initialsAvatar(name, size),
          ),
        );
      },
    );
  }

  Widget _initialsAvatar(String name, double size) {
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
}
