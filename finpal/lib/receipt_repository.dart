// lib/data/receipt_repository.dart
import 'dart:convert';
import 'package:isar/isar.dart';
import 'receipt.dart' as domain; 
import 'entities.dart';
import 'local_db.dart';

class ReceiptRepository {
  // always grab instance through LocalDb
  Future<Isar> get _db async => LocalDb.instance();

  // -------- Compartments --------
  Future<Compartment> _ensureCompartmentFor(String? merchantTitle) async {
    final isar = await _db;
    final key = merchantKeyFor(merchantTitle);
    final existing =
        await isar.compartments.filter().keyEqualTo(key).findFirst();
    if (existing != null) return existing;

    final comp = Compartment()
      ..key = key
      ..title = (merchantTitle == null || merchantTitle.trim().isEmpty)
          ? 'Unknown'
          : merchantTitle.trim()
      ..createdAt = DateTime.now();

    await isar.writeTxn(() async {
      await isar.compartments.put(comp);
    });
    return comp;
  }

  // -------- User --------
  Future<UserEntity?> getCurrentUser() async {
    final isar = await _db;
    return await isar.userEntitys.where().findFirst();
  }

  Future<void> logoutUser() async{
    final isar = await _db;
  final user = await isar.userEntitys
        .filter()
        .isLoggedInEqualTo(true)
        .findFirst(); 
  if (user != null) {
    user.isLoggedIn = false;
    await isar.writeTxn(() async {
      await isar.userEntitys.put(user);
    });
  }
  }

  /// Deletes all receipts for the given merchant and removes the compartment itself.
Future<void> deleteCompartmentAndReceipts(String merchant) async {
  final isar = await _db;
  final key = merchantKeyFor(merchant);

  await isar.writeTxn(() async {
    // Find the compartment for this merchant
    final comp = await isar.compartments.filter().keyEqualTo(key).findFirst();
    if (comp == null) {
      // Still delete orphan receipts just in case
      await isar.receiptEntitys.filter().merchantEqualTo(merchant).deleteAll();
      return;
    }

    // Delete all receipts under this compartment
    await isar.receiptEntitys
        .filter()
        .compartmentIdEqualTo(comp.id)
        .deleteAll();

    // Delete the compartment itself
    await isar.compartments.delete(comp.id);
  });
}

  Future<void> deleteCurrentUser() async {
    final isar = await _db;
  await isar.writeTxn(() async {
    await isar.userEntitys.clear();      // delete all users
    await isar.receiptEntitys.clear();   // optional: delete receipts too
    await isar.compartments.clear();
  });
  }

  Future<void> updateUserProfileImageBytes(List<int> imageBytes) async {
  final isar = await _db;
  final user = await isar.userEntitys.where().findFirst();
  if (user != null) {
    user.profileImageBytes = imageBytes; // add this field in your User entity
    await isar.writeTxn(() async {
      await isar.userEntitys.put(user);
    });
    print('💾 Saved profile image (${imageBytes.length} bytes) to Isar');
  }
}

Future<void> saveUser(UserEntity user) async {
  final isar = await _db;
  await isar.writeTxn(() async {
    await isar.userEntitys.put(user);
  });
}

  // -------- Receipts --------
  Future<List<ReceiptEntity>> getAllReceipts() async {
    final isar = await _db;
    return await isar.receiptEntitys.where().findAll();
  }

  // ✅ Updated to accept imagePath
  Future<void> saveScanned(domain.Receipt r, {String? imagePath}) async {
    final isar = await _db;
    final comp = await _ensureCompartmentFor(r.merchant);

    final ent = ReceiptEntity()
      ..receiptId = r.id
      ..compartmentId = comp.id
      ..merchant = r.merchant
      ..merchantKey = merchantKeyFor(r.merchant)
      ..date = r.date ?? DateTime.now()
      ..address = r.address
      ..subtotal = r.subtotal
      ..tax = r.hasTax ? r.effectiveTax : null
      ..total = r.effectiveTotal
      ..provider = r.provider
      ..confidencesJson =
          r.confidences == null ? null : jsonEncode(r.confidences)
      ..imagePath = imagePath  // ✅ Save image path
      ..items = r.items.map((it) {
        final e = LineItemEmb()
          ..name = it.name
          ..quantity = it.quantity
          ..unitPrice = it.unitPrice
          ..total = it.total;
        return e;
      }).toList();

    await isar.writeTxn(() async {
      final existing = await isar.receiptEntitys
          .filter()
          .receiptIdEqualTo(r.id)
          .findFirst();
      if (existing != null) ent.id = existing.id;
      await isar.receiptEntitys.put(ent);
    });
  }

  // ✅ Updated to accept imagePath
  Future<(ReceiptEntity, Compartment)> saveAndReturnCompartment(
      domain.Receipt r, {String? imagePath}) async {
    final isar = await _db;
    final comp = await _ensureCompartmentFor(r.merchant);

    final ent = ReceiptEntity()
      ..receiptId = r.id
      ..compartmentId = comp.id
      ..merchant = r.merchant
      ..merchantKey = merchantKeyFor(r.merchant)
      ..date = r.date ?? DateTime.now()
      ..address = r.address
      ..subtotal = r.subtotal
      ..tax = r.hasTax ? r.effectiveTax : null
      ..total = r.effectiveTotal
      ..provider = r.provider
      ..confidencesJson =
          r.confidences == null ? null : jsonEncode(r.confidences)
      ..imagePath = imagePath  // ✅ Save image path
      ..items = r.items.map((it) {
        final e = LineItemEmb()
          ..name = it.name
          ..quantity = it.quantity
          ..unitPrice = it.unitPrice
          ..total = it.total;
        return e;
      }).toList();

    await isar.writeTxn(() async {
      final existing = await isar.receiptEntitys
          .filter()
          .receiptIdEqualTo(r.id)
          .findFirst();
      if (existing != null) ent.id = existing.id;
      await isar.receiptEntitys.put(ent);
    });

    return (ent, comp);
  }

  // -------- General receipt updater --------
  Future<bool> updateReceiptByReceiptId({
    required String receiptId,
    String? newMerchant,
    DateTime? newDate,
    String? newAddress,
    double? newSubtotal,
    double? newTax,
    double? newTotal,
    List<domain.LineItem>? newItems,
  }) async {
    final isar = await _db;

    return await isar.writeTxn(() async {
      final rec = await isar.receiptEntitys
          .filter()
          .receiptIdEqualTo(receiptId)
          .findFirst();

      if (rec == null) return false;

      if (newMerchant != null) {
        final safe = newMerchant.trim().isEmpty ? 'Unknown' : newMerchant.trim();
        rec.merchant = safe;
        rec.merchantKey = merchantKeyFor(safe);
        final comp = await _ensureCompartmentFor(safe);
        rec.compartmentId = comp.id;
      }

      if (newDate != null) rec.date = newDate;
      if (newAddress != null) rec.address = newAddress;
      if (newSubtotal != null) rec.subtotal = newSubtotal;
      if (newTax != null) rec.tax = newTax;
      if (newTotal != null) rec.total = newTotal;

      if (newItems != null) {
        rec.items = newItems.map((it) {
          final e = LineItemEmb()
            ..name = it.name
            ..quantity = it.quantity
            ..unitPrice = it.unitPrice
            ..total = it.total;
          return e;
        }).toList();
      }

      await isar.receiptEntitys.put(rec);
      return true;
    });
  }

  Future<void> updateMerchant(
    String id, {
    required String receiptId,
    required String newMerchant,
  }) async {
    await updateReceiptByReceiptId(
      receiptId: receiptId,
      newMerchant: newMerchant,
    );
  }

  Future<bool> deleteReceiptByIsarId(int isarId) async {
    final isar = await _db;
    return isar.writeTxn(() async {
      return await isar.receiptEntitys.delete(isarId);
    });
  }

  // ✅ Added deleteReceipt method for swipe-to-delete
  Future<bool> deleteReceipt(int receiptId) async {
    final isar = await _db;
    return await isar.writeTxn(() async {
      return await isar.receiptEntitys.delete(receiptId);
    });
  }

  Future<int> deleteCompartmentCascade(String merchantKey) async {
    final isar = await _db;
    return isar.writeTxn(() async {
      final comp =
          await isar.compartments.filter().keyEqualTo(merchantKey).findFirst();
      if (comp == null) return 0;

      final receipts = await isar.receiptEntitys
          .filter()
          .compartmentIdEqualTo(comp.id)
          .findAll();
      for (final r in receipts) {
        await isar.receiptEntitys.delete(r.id);
      }

      await isar.compartments.delete(comp.id);
      return receipts.length + 1;
    });
  }

  // -------- Lists --------
  Future<List<Compartment>> listCompartments() async {
    final isar = await _db;
    return isar.compartments.where().sortByTitle().findAll();
  }

  Future<List<ReceiptEntity>> listReceiptsInCompartment(
      String merchantKey) async {
    final isar = await _db;
    final comp =
        await isar.compartments.filter().keyEqualTo(merchantKey).findFirst();
    if (comp == null) return [];
    return isar.receiptEntitys
        .filter()
        .compartmentIdEqualTo(comp.id)
        .findAll();
  }

  // -------- Streams --------
  Stream<List<ReceiptEntity>> watchReceiptsInCompartment(
      String merchantKey) async* {
    final isar = await _db;
    final comp =
        await isar.compartments.filter().keyEqualTo(merchantKey).findFirst();
    if (comp == null) {
      yield const [];
      return;
    }
    yield* isar.receiptEntitys
        .filter()
        .compartmentIdEqualTo(comp.id)
        .sortByDateDesc()
        .watch(fireImmediately: true);
  }

  Stream<List<Compartment>> watchCompartments() async* {
    final isar = await _db;
    yield* isar.compartments.where().sortByTitle().watch(fireImmediately: true);
  }

  Stream<List<ReceiptEntity>> watchAllReceipts() async* {
    final isar = await _db;
    yield* isar.receiptEntitys
        .where()
        .sortByDateDesc()
        .watch(fireImmediately: true);
  }

  // -------- Mapping --------
  domain.Receipt toDomain(ReceiptEntity e) {
    return domain.Receipt(
      id: e.receiptId ?? e.id.toString(),
      merchant: e.merchant,
      date: e.date,
      address: e.address,
      subtotal: e.subtotal,
      tax: e.tax,
      tip: null,
      total: e.total,
      items: e.items
          .map((it) => domain.LineItem(
                name: it.name,
                quantity: it.quantity,
                unitPrice: it.unitPrice,
                total: it.total,
              ))
          .toList(),
      provider: e.provider,
      confidences: e.confidencesJson == null
          ? null
          : (jsonDecode(e.confidencesJson!) as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }

  // -------- Line item updater --------
  Future<bool> updateLineItem({
    required String receiptId,
    required int lineIndex,
    required domain.LineItem newItem,
  }) async {
    final isar = await _db;

    return await isar.writeTxn(() async {
      final rec = await isar.receiptEntitys
          .filter()
          .receiptIdEqualTo(receiptId)
          .findFirst();

      if (rec == null) return false;
      if (lineIndex < 0 || lineIndex >= rec.items.length) return false;

      final updatedEmb = LineItemEmb()
        ..name = newItem.name
        ..quantity = newItem.quantity
        ..unitPrice = newItem.unitPrice
        ..total = newItem.total;

      final items = List<LineItemEmb>.from(rec.items);
      items[lineIndex] = updatedEmb;
      rec.items = items;

      await isar.receiptEntitys.put(rec);
      return true;
    });
  }

  // -------- Save full receipt --------
  Future<int> saveScannedReceipt({
    required domain.Receipt receipt,
    String? imagePath,
  }) async {
    await saveScanned(receipt, imagePath: imagePath);

    final isar = await _db;
    final saved = await isar.receiptEntitys
        .filter()
        .receiptIdEqualTo(receipt.id)
        .findFirst();
    return saved?.id ?? -1;
  }
}