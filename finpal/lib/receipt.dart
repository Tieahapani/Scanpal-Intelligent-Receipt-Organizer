// lib/receipt.dart

class LineItem {
  final String name;
  final double? quantity;   // nullable
  final double? unitPrice;  // nullable
  final double? total;      // nullable

  const LineItem({
    required this.name,
    this.quantity,
    this.unitPrice,
    this.total,
  });

  factory LineItem.fromMap(Map<String, dynamic> m) {
    double? _numOrNull(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return LineItem(
      name: (m['name'] ?? 'Item').toString(),
      quantity: _numOrNull(m['quantity']),
      unitPrice: _numOrNull(m['unit_price'] ?? m['price']),
      total: _numOrNull(m['total']),
    );
  }

  /// If backend didn't send a line total, compute qty * unitPrice
  double get computedTotal {
    if (total != null) return total!;
    if (quantity != null && unitPrice != null) {
      return quantity! * unitPrice!;
    }
    return 0.0;
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        if (quantity != null) 'quantity': quantity,
        if (unitPrice != null) 'unit_price': unitPrice,
        if (total != null) 'total': total,
      };

  /// Optional: makes editing items easy (kept for parity with Receipt.copyWith)
  LineItem copyWith({
    String? name,
    double? quantity,
    double? unitPrice,
    double? total,
  }) {
    return LineItem(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      total: total ?? this.total,
    );
  }
}

class Receipt {
  final String id;
  final String? merchant;
  final DateTime? date;     // ISO string from backend -> DateTime.tryParse
  final String? address;

  // Money fields as numbers (nullable)
  final double? subtotal;   // omitted if not present on receipt
  final double? tax;        // omitted if not present
  final double? tip;        // we ignore this in all math, but kept for backward compat
  final double total;       // required (backend always sends)

  final List<LineItem> items;
  final String? provider;   // "azure" (optional)
  final Map<String, double>? confidences; // optional debug/QA
  final List<String>? rawLines;
  final String? category;   // ✅ Category from Gemini backend
  final String? currency;   // ✅ NEW: Currency from Gemini backend

  const Receipt({
    required this.id,
    this.merchant,
    this.date,
    this.address,
    this.subtotal,
    this.tax,
    this.tip,
    required this.total,
    required this.items,
    this.provider,
    this.confidences,
    this.rawLines,
    this.category,
    this.currency,  // ✅ NEW
  });

  factory Receipt.fromMap(Map<String, dynamic> m) {
    double? _numOrNull(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    final rawItems = (m['items'] as List?) ?? const [];
    final items = rawItems
        .whereType<Map>()
        .map((e) => LineItem.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    // Parse ISO-like date string if present
    DateTime? parsedDate;
    final dateVal = m['date'];
    if (dateVal != null) {
      parsedDate = DateTime.tryParse(dateVal.toString());
    }

    // confidences are optional; if present, coerce to <String,double>
    Map<String, double>? conf;
    if (m['confidences'] is Map) {
      conf = (m['confidences'] as Map).map((k, v) {
        double? d;
        if (v is num) {
          d = v.toDouble();
        } else {
          d = double.tryParse(v.toString());
        }
        return MapEntry(k.toString(), d ?? 0.0);
      });
    }

    return Receipt(
      id: (m['id'] ?? DateTime.now().millisecondsSinceEpoch.toString()).toString(),
      merchant: m['merchant']?.toString(),
      date: parsedDate,
      address: m['address']?.toString(),
      subtotal: _numOrNull(m['subtotal']),
      tax: _numOrNull(m['tax']),
      tip: _numOrNull(m['tip']),
      total: _numOrNull(m['total']) ?? 0.0,
      items: items,
      provider: m['provider']?.toString(),
      confidences: conf,
      rawLines: (m['raw_lines'] as List?)?.map((e) => e.toString()).toList(),
      category: m['category']?.toString(),
      currency: m['currency']?.toString() ?? '\$',  // ✅ NEW: Parse currency from backend with fallback
    );
  }

  // --------------------------
  // Smart, tip-free calculations
  // --------------------------

  double _round2(double v) => (v * 100).roundToDouble() / 100.0;

  /// Sum of line totals (with fallback to qty*unitPrice)
  double get itemsSum =>
      items.fold(0.0, (s, it) => s + (it.computedTotal.isNaN ? 0.0 : it.computedTotal));

  /// Prefer explicit subtotal; otherwise sum of items.
  double get effectiveSubtotal => subtotal ?? itemsSum;

  /// We don't use tip at all in math; kept only for legacy display if you want it.
  double get effectiveTip => 0.0;

  /// Candidate tax if missing: total - subtotal (since tip is ignored)
  double get _taxCandidate {
    final raw = total - effectiveSubtotal;
    return _round2(raw < 0 ? 0.0 : raw);
  }

  /// Heuristic: treat as tax only if within 0.5%–15% of subtotal
  bool get _isPlausibleTax {
    final sub = effectiveSubtotal;
    if (sub <= 0) return false;
    final cand = _taxCandidate;
    if (cand <= 0.01) return false; // ignore tiny rounding dust
    final pct = cand / sub;
    return pct >= 0.005 && pct <= 0.15;
  }

  /// Public: does this receipt have tax?
  bool get hasTax => (tax != null && tax! > 0.01) || (tax == null && _isPlausibleTax);

  /// Public: tax value to display when `hasTax` is true; else 0
  double get effectiveTax {
    if (tax != null) return _round2(tax!);
    return hasTax ? _taxCandidate : 0.0;
  }

  /// Total to display; if backend gave 0, compute it.
  double get effectiveTotal {
    if (total == 0.0) {
      return _round2(effectiveSubtotal + effectiveTax);
    }
    return total;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        if (merchant != null) 'merchant': merchant,
        if (date != null) 'date': date!.toIso8601String(),
        if (address != null) 'address': address,
        if (subtotal != null) 'subtotal': subtotal,
        // Only include `tax` if we actually have/infer it
        if (hasTax) 'tax': effectiveTax,
        // Keep tip passthrough (legacy). Remove this line if you want to drop tips entirely from payloads:
        if (tip != null) 'tip': tip,
        'total': effectiveTotal, // ensure consistent total
        'items': items.map((e) => e.toMap()).toList(),
        if (provider != null) 'provider': provider,
        if (confidences != null) 'confidences': confidences,
        if (category != null) 'category': category,
        if (currency != null) 'currency': currency,  // ✅ NEW
      };

  /// Add this so the UI can easily update merchant (and other fields if needed)
  Receipt copyWith({
    String? id,
    String? merchant,
    DateTime? date,
    String? address,
    double? subtotal,
    double? tax,
    double? tip,
    double? total,
    List<LineItem>? items,
    String? provider,
    Map<String, double>? confidences,
    String? category,
    String? currency,  // ✅ NEW
  }) {
    return Receipt(
      id: id ?? this.id,
      merchant: merchant ?? this.merchant,
      date: date ?? this.date,
      address: address ?? this.address,
      subtotal: subtotal ?? this.subtotal,
      tax: tax ?? this.tax,
      tip: tip ?? this.tip,
      total: total ?? this.total,
      items: items ?? this.items,
      provider: provider ?? this.provider,
      confidences: confidences ?? this.confidences,
      category: category ?? this.category,
      currency: currency ?? this.currency,  // ✅ NEW
    );
  }
}