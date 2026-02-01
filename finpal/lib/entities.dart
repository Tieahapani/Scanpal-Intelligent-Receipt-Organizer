import 'package:isar/isar.dart';
import 'dart:typed_data';

part 'entities.g.dart';

/// Normalize a merchant to a stable key: lowercase, alnum+hyphen.
/// "Target  " -> "target", "Whole Foods Market" -> "whole-foods-market"
String merchantKeyFor(String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return 'unknown';
  final collapsed = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return collapsed.replaceAll(RegExp(r'^-+|-+$'), '');
}

@collection
class Compartment {
  Id id = Isar.autoIncrement;

  /// e.g. "target"
  @Index(unique: true, caseSensitive: false)
  late String key;

  /// Human-friendly title as last known (e.g., "Target")
  late String title;

  late DateTime createdAt;
  
  /// Category assigned by Gemini (e.g., "Shopping", "Groceries", "Food & Drinks")
  String? category;  // ✅ NEW: Category for grouping vendors
}

@embedded
class LineItemEmb {
  late String name;
  double? quantity;
  double? unitPrice;
  double? total;
}

@collection
class ReceiptEntity {
  Id id = Isar.autoIncrement;

  /// Your external receipt id (string from backend / OCR). Keep unique if you have one.
  @Index()
  String? receiptId;

  /// Compartment foreign key
  late int compartmentId;

  /// Raw merchant fields (mirrors your domain)
  String? merchant;      // last known title
  String? merchantKey;   // normalized, e.g. "target"

  late DateTime date;
  String? address;

  double? subtotal;
  double? tax;
  double total = 0.0;

  List<LineItemEmb> items = [];

  String? provider;

  // If you want confidences, store as JSON string to keep it simple
  String? confidencesJson;

  String? imagePath; 

  String? currency;
  String? category;  // Category stored at receipt level (for reference/migration)
}

/// New: UserEntity for login/register
@collection
class UserEntity {
  Id id = Isar.autoIncrement;

  late String fullName;
  late String location;

  @Index(unique: true, caseSensitive: false)
  late String username;
  late String email; 

  late String password;
  bool rememberMe = false;

  List<int>? profileImageBytes;
  bool isLoggedIn = false;
}