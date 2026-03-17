import 'package:flutter/material.dart';
import 'receipt.dart';
import 'api.dart';
import 'auth_service.dart';

class ReceiptDetailPage extends StatelessWidget {
  final Receipt receipt;

  const ReceiptDetailPage({super.key, required this.receipt});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 95,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Row(
            children: [
              SizedBox(width: 12),
              Icon(Icons.arrow_back_ios_new_rounded,
                  color: Color(0xFF007AFF), size: 20),
              SizedBox(width: 2),
              Text(
                "Back",
                style: TextStyle(
                  color: Color(0xFF007AFF),
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
      body: receipt.imageUrl != null
          ? FutureBuilder<String?>(
              future: AuthService.instance.getToken(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final url = APIService().receiptImageUrl(receipt.id);
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(
                      url,
                      headers: {'Authorization': 'Bearer ${snap.data}'},
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _buildNoImagePlaceholder(),
                    ),
                  ),
                );
              },
            )
          : _buildNoImagePlaceholder(),
      bottomNavigationBar: receipt.imageUrl != null
          ? Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: Colors.grey.shade100,
              child: const SafeArea(
                child: Text(
                  "Pinch to zoom - Drag to pan",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildNoImagePlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 32),
          Text(
            'No image available',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          const Text(
            'The receipt image was not saved',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
