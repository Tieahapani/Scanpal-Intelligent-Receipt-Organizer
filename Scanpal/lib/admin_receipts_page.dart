import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'receipt.dart';
import 'models/trip.dart';
import 'receipt_detail_page.dart';

class AdminReceiptsPage extends StatefulWidget {
  final List<Receipt> receipts;
  final List<Trip> trips;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const AdminReceiptsPage({
    super.key,
    required this.receipts,
    required this.trips,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  State<AdminReceiptsPage> createState() => _AdminReceiptsPageState();
}

class _AdminReceiptsPageState extends State<AdminReceiptsPage> {
  final _currency = NumberFormat.simpleCurrency();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedTripId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, Trip> get _tripMap {
    return {for (final t in widget.trips) t.id: t};
  }

  /// Unique trips that have receipts, for filter chips
  List<Trip> get _tripsWithReceipts {
    final tripIds = widget.receipts
        .where((r) => r.tripId != null)
        .map((r) => r.tripId!)
        .toSet();
    final map = _tripMap;
    return tripIds
        .where((id) => map.containsKey(id))
        .map((id) => map[id]!)
        .toList()
      ..sort((a, b) => (a.travelerName).compareTo(b.travelerName));
  }

  List<Receipt> get _filteredReceipts {
    var receipts = widget.receipts;

    // Filter by selected trip
    if (_selectedTripId != null) {
      receipts = receipts.where((r) => r.tripId == _selectedTripId).toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      final map = _tripMap;
      receipts = receipts.where((r) {
        // Match against merchant
        if (r.merchant?.toLowerCase().contains(q) == true) return true;
        // Match against travel category
        if (r.travelCategory?.toLowerCase().contains(q) == true) return true;
        // Match against trip info
        if (r.tripId != null && map.containsKey(r.tripId)) {
          final trip = map[r.tripId]!;
          if (trip.travelerName.toLowerCase().contains(q)) return true;
          if (trip.department?.toLowerCase().contains(q) == true) return true;
          if (trip.tripPurpose?.toLowerCase().contains(q) == true) return true;
          if (trip.destination?.toLowerCase().contains(q) == true) return true;
        }
        return false;
      }).toList();
    }

    return receipts;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading && widget.receipts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filteredReceipts;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search by traveler, merchant, trip...',
                hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Color(0xFF94A3B8)),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: const Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: const Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
                ),
              ),
            ),
          ),

          // Filter chips
          if (_tripsWithReceipts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 0, 0),
              child: SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text('All (${widget.receipts.length})'),
                        selected: _selectedTripId == null,
                        onSelected: (_) => setState(() => _selectedTripId = null),
                        selectedColor: const Color(0xFF1565C0),
                        backgroundColor: const Color(0xFF0891B2).withValues(alpha: 0.1),
                        side: BorderSide(
                          color: _selectedTripId == null
                              ? Colors.transparent
                              : const Color(0xFF0891B2).withValues(alpha: 0.3),
                        ),
                        labelStyle: TextStyle(
                          color: _selectedTripId == null ? Colors.white : const Color(0xFF0891B2),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    ..._tripsWithReceipts.map((trip) {
                      final label = trip.travelerName.isNotEmpty
                          ? '${trip.travelerName} - ${trip.displayTitle}'
                          : trip.displayTitle;
                      final isSelected = _selectedTripId == trip.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(label, overflow: TextOverflow.ellipsis),
                          selected: isSelected,
                          onSelected: (_) => setState(() {
                            _selectedTripId = isSelected ? null : trip.id;
                          }),
                          selectedColor: const Color(0xFF1565C0),
                          backgroundColor: const Color(0xFF0891B2).withValues(alpha: 0.1),
                          side: BorderSide(
                            color: isSelected
                                ? Colors.transparent
                                : const Color(0xFF0891B2).withValues(alpha: 0.3),
                          ),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFF0891B2),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Results count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${filtered.length} receipt${filtered.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Receipt list
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _receiptCard(filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty || _selectedTripId != null
                ? 'No receipts match your search'
                : 'No receipts found',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          if (_searchQuery.isNotEmpty || _selectedTripId != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _selectedTripId = null;
                });
              },
              child: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _receiptCard(Receipt receipt) {
    final map = _tripMap;
    final trip = receipt.tripId != null ? map[receipt.tripId] : null;
    final dateStr = receipt.date != null
        ? DateFormat('MMM d, y').format(receipt.date!)
        : 'No date';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReceiptDetailPage(receipt: receipt)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Traveler + department badges
            if (trip != null &&
                (trip.travelerName.isNotEmpty ||
                    (trip.department != null && trip.department!.isNotEmpty)))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (trip.travelerName.isNotEmpty)
                      _badge(Icons.person, trip.travelerName, const Color(0xFF7C3AED)),
                    if (trip.department != null && trip.department!.isNotEmpty)
                      _badge(Icons.business, trip.department!, const Color(0xFF0891B2)),
                  ],
                ),
              ),

            // Trip purpose
            if (trip != null && trip.tripPurpose != null && trip.tripPurpose!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  trip.displayTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),

            // Merchant, date, amount row
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.receipt, size: 18, color: Color(0xFF1565C0)),
                ),
                const SizedBox(width: 12),
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
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateStr,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _currency.format(receipt.effectiveTotal),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (receipt.travelCategory != null)
                      Text(
                        receipt.travelCategory!,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
