import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'receipt.dart';
import 'models/trip.dart';
import 'api.dart';
import 'auth_service.dart';
import 'receipt_detail_page.dart';

/// Standalone receipt detail view — used from both ReceiptsPage and TravelerHomePage.
class ReceiptDetailViewPage extends StatelessWidget {
  final Receipt receipt;
  final List<Trip> trips;

  const ReceiptDetailViewPage({
    super.key,
    required this.receipt,
    required this.trips,
  });
   
  static const _categoryLabels = {
    'Accommodation Cost': 'Accommodation',
    'Flight Cost': 'Flight',
    'Ground Transportation': 'Ground Transport',
    'Registration Cost': 'Registration',
    'Other AS Cost': 'Other AS Cost',
  };

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
                    const Text(
                      'Receipt Details',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
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
                          color: Colors.black.withOpacity(0.08),
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
                              color: Colors.black.withOpacity(0.5),
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
                        color: Colors.black.withOpacity(0.04),
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
        return Image.network(
          url,
          headers: {'Authorization': 'Bearer ${snap.data}'},
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (_, __, ___) => Container(
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
            color: Colors.black.withOpacity(0.04),
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
            color: Colors.black.withOpacity(0.04),
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









