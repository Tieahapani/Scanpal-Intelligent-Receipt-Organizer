import 'dart:io';
import 'receipt.dart';
import 'api.dart';
import 'models/trip.dart';

class ReceiptRepository {
  final APIService _api = APIService();

  Future<List<Receipt>> getReceiptsForTrip(String tripId) async {
    return _api.fetchReceipts(tripId: tripId);
  }

  Future<({Receipt receipt, Trip? trip})> uploadAndGetSuggestion(File image, String tripId) async {
    return _api.uploadReceipt(image, tripId: tripId);
  }

  Future<Map<String, dynamic>> confirmCategory(String receiptId, String category) async {
    return _api.confirmCategory(receiptId, category);
  }

  Future<bool> deleteReceipt(String receiptId) async {
    return _api.deleteReceipt(receiptId);
  }

  Future<List<Receipt>> getAllReceipts() async {
    return _api.fetchReceipts();
  }
}
