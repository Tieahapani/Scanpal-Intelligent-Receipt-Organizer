import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'entities.dart';
import 'receipt_detail_page.dart';
import 'receipt_repository.dart';

class CompartmentPage extends StatefulWidget {
  final String merchant;
  final List<ReceiptEntity> receipts;

  const CompartmentPage({
    super.key,
    required this.merchant,
    required this.receipts,
  });

  static const _appBlue = Color(0xFF1565C0);

  @override
  State<CompartmentPage> createState() => _CompartmentPageState();
}

class _CompartmentPageState extends State<CompartmentPage> {
  final _repo = ReceiptRepository();
  late List<ReceiptEntity> _sortedReceipts;

  @override
  void initState() {
    super.initState();
    _sortedReceipts = List<ReceiptEntity>.from(widget.receipts)
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  String _formatMerchant(String name) {
    name = name.replaceAll(RegExp(r'[._]+'), ' ').trim();
    final words = name.split(' ');
    return words
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  Future<void> _deleteReceipt(ReceiptEntity receipt) async {
    if (receipt.imagePath != null && File(receipt.imagePath!).existsSync()) {
      await File(receipt.imagePath!).delete();
    }

    await _repo.deleteReceipt(receipt.id!);

    setState(() {
      _sortedReceipts.removeWhere((r) => r.id == receipt.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.6,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: CompartmentPage._appBlue),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _formatMerchant(widget.merchant),
          style: const TextStyle(
            color: CompartmentPage._appBlue,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),

      body: _sortedReceipts.isEmpty
          ? const Center(
              child: Text(
                'No receipts yet.',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              itemCount: _sortedReceipts.length,
              itemBuilder: (context, index) {
                final receipt = _sortedReceipts[index];

                return Dismissible(
                  key: Key(receipt.id.toString()),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    decoration: BoxDecoration(
                      color: CompartmentPage._appBlue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  onDismissed: (_) => _deleteReceipt(receipt),

                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReceiptDetailPage(receipt: receipt),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "# Receipt ${index + 1}",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                ),
                              ),
                            Text(
                            receipt.total != null
                            ? "${receipt.currency ?? '\$'}${receipt.total!.toStringAsFixed(2)}"
                            : "-",
                            style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: CompartmentPage._appBlue,
                            ),
                            ),

                            ],
                          ),

                          const SizedBox(height: 4),

                          Text(
                            dateFormat.format(receipt.date),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),

                          const SizedBox(height: 10),

                          Divider(
                            thickness: 1,
                            color: Colors.black12.withOpacity(0.2),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
