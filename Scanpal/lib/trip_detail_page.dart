import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'models/trip.dart';
import 'receipt.dart';
import 'api.dart';
import 'receipt_detail_page.dart';
import 'monthly_summary_page.dart';

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

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _loadReceipts();
    _refreshTrip();
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

  Future<void> _scanReceipt() async {
    try {
      final images = await CunningDocumentScanner.getPictures(
        isGalleryImportAllowed: true,
      );
      if (images == null || images.isEmpty) return;

      if (!mounted) return;
      _showUploadingSnackbar();

      final result = await _api.uploadReceipt(
        File(images.first),
        tripId: _trip.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        setState(() {
          _receipts.insert(0, result.receipt);
          if (result.trip != null) _trip = result.trip!;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      if (!mounted) return;
      _showUploadingSnackbar();

      final result = await _api.uploadReceipt(
        File(picked.path),
        tripId: _trip.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        setState(() {
          _receipts.insert(0, result.receipt);
          if (result.trip != null) _trip = result.trip!;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showUploadingSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Processing receipt...'),
          ],
        ),
        duration: Duration(seconds: 30),
      ),
    );
  }

  Future<void> _deleteReceipt(Receipt receipt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Receipt'),
        content: Text('Delete receipt from ${receipt.merchant ?? "Unknown"}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final success = await _api.deleteReceipt(receipt.id);
    if (success && mounted) {
      setState(() => _receipts.removeWhere((r) => r.id == receipt.id));
      _refreshTrip();
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF0F172A),
        title: Text(
          trip.displayTitle,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded, color: Color(0xFF1565C0)),
            tooltip: 'Analytics',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MonthlySummaryPage(tripId: trip.id),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReceipts,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Trip info card
                  _buildTripInfoCard(trip),
                  const SizedBox(height: 20),

                  // Cost breakdown
                  _buildCostBreakdown(trip),
                  const SizedBox(height: 20),

                  // Receipts section
                  Row(
                    children: [
                      const Text(
                        'Receipts',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_receipts.length}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_receipts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            'No receipts yet',
                            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap + to scan or upload a receipt',
                            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._receipts.map((r) => _receiptTile(r)),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddOptions,
        backgroundColor: const Color(0xFF1565C0),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.document_scanner, color: Color(0xFF1565C0)),
                title: const Text('Scan Receipt'),
                subtitle: const Text('Use camera to scan a document'),
                onTap: () {
                  Navigator.pop(context);
                  _scanReceipt();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFF7C3AED)),
                title: const Text('From Gallery'),
                subtitle: const Text('Pick an existing photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromGallery();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTripInfoCard(Trip trip) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (trip.destination != null && trip.destination!.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.location_on, size: 16, color: Color(0xFF1565C0)),
                const SizedBox(width: 6),
                Text(
                  trip.destination!,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (trip.departureDate != null) ...[
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 6),
                Text(
                  _formatDateRange(trip.departureDate, trip.returnDate, months),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (trip.status != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                trip.status!,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1565C0)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCostBreakdown(Trip trip) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Budget Overview',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 12),
          _costRow('Accommodation', trip.accommodationCost),
          _costRow('Flight', trip.flightCost),
          _costRow('Ground Transport', trip.groundTransportation),
          _costRow('Registration', trip.registrationCost),
          _costRow('Other', trip.otherAsCost),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              Text(
                _currency.format(trip.totalExpenses),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1565C0)),
              ),
            ],
          ),
          if (trip.advance > 0) ...[
            const SizedBox(height: 8),
            _costRow('Advance', trip.advance),
            _costRow('Claim', trip.claim),
          ],
        ],
      ),
    );
  }

  Widget _costRow(String label, double amount) {
    if (amount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF64748B))),
          Text(_currency.format(amount), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _receiptTile(Receipt receipt) {
    final dateStr = receipt.date != null
        ? DateFormat('MMM d, y').format(receipt.date!)
        : 'No date';

    return Dismissible(
      key: Key(receipt.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        await _deleteReceipt(receipt);
        return false; // we handle removal in _deleteReceipt
      },
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ReceiptDetailPage(receipt: receipt)),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt, size: 20, color: Color(0xFF1565C0)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      receipt.merchant ?? 'Unknown Merchant',
                      style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1F2937),
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
                      fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A),
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
        ),
      ),
    );
  }

  String _formatDateRange(DateTime? start, DateTime? end, List<String> months) {
    if (start == null) return '';
    final s = '${months[start.month - 1]} ${start.day}, ${start.year}';
    if (end == null || end == start) return s;
    final e = '${months[end.month - 1]} ${end.day}, ${end.year}';
    return '$s - $e';
  }
}
