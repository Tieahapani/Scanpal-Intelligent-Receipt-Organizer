import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:isar/isar.dart';
import '/local_db.dart';
import 'entities.dart';
import 'compartment_page.dart';

class CategoryAllVendorsPage extends StatefulWidget {
  final String categoryName;

  const CategoryAllVendorsPage({
    super.key,
    required this.categoryName,
  });

  @override
  State<CategoryAllVendorsPage> createState() => _CategoryAllVendorsPageState();
}

class _CategoryAllVendorsPageState extends State<CategoryAllVendorsPage> {
  static const _appBlue = Color(0xFF1565C0);
  static const _lightBlue = Color(0xFF42A5F5);

  Map<String, List<ReceiptEntity>> _vendors = {};
  List<String> _filteredKeys = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadVendors();
  }

  String _formatMerchant(String name) {
    name = name.replaceAll(RegExp(r'[._]+'), ' ').trim();
    final words = name.split(' ');
    return words
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  Future<void> _loadVendors() async {
    setState(() => _loading = true);

    final isar = await LocalDb.instance();

    // Get all compartments in this category
    final compartments = await isar.compartments
        .filter()
        .categoryEqualTo(widget.categoryName)
        .findAll();

    final Map<String, List<ReceiptEntity>> grouped = {};

    for (var comp in compartments) {
      final receipts = await isar.receiptEntitys
          .filter()
          .compartmentIdEqualTo(comp.id)
          .findAll();

      if (receipts.isNotEmpty) {
        grouped[comp.title] = receipts;
      }
    }

    setState(() {
      _vendors = grouped;
      _filteredKeys = _vendors.keys.toList()..sort();
      _loading = false;
    });
  }

  void _filterVendors(String query) {
    setState(() {
      _filteredKeys = _vendors.keys
          .where((name) => name.toLowerCase().contains(query.toLowerCase()))
          .toList()
        ..sort();
    });
  }

  Future<void> _deleteVendor(String merchant) async {
    

    final isar = await LocalDb.instance();
    final key = merchantKeyFor(merchant);

    await isar.writeTxn(() async {
      final receipts = await isar.receiptEntitys
          .filter()
          .merchantKeyEqualTo(key)
          .findAll();

      for (final r in receipts) {
        if (r.imagePath != null && File(r.imagePath!).existsSync()) {
          await File(r.imagePath!).delete();
        }
        await isar.receiptEntitys.delete(r.id!);
      }

      final comp = await isar.compartments.filter().keyEqualTo(key).findFirst();
      if (comp != null) await isar.compartments.delete(comp.id);
    });

    await _loadVendors();
  }

  Future<void> _showEditVendorDialog(String oldMerchant) async {
    final controller = TextEditingController(text: oldMerchant);
    final isar = await LocalDb.instance();

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF0EA5E9),
                Color(0xFF2563EB),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                "Edit Vendor Name",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: "Enter new vendor name",
                  hintStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "Cancel",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final input = controller.text.trim();
                      if (input.isEmpty) return;

                      final newName = input;
                      final newKey = merchantKeyFor(newName);
                      final oldKey = merchantKeyFor(oldMerchant);

                      await isar.writeTxn(() async {
                        Compartment? oldComp = await isar.compartments
                            .filter()
                            .keyEqualTo(oldKey)
                            .findFirst();

                        Compartment? targetComp = await isar.compartments
                            .filter()
                            .keyEqualTo(newKey)
                            .findFirst();

                        if (targetComp != null) {
                          targetComp.title = newName;
                          await isar.compartments.put(targetComp);
                        } else if (oldComp != null) {
                          oldComp
                            ..key = newKey
                            ..title = newName;
                          await isar.compartments.put(oldComp);
                          targetComp = oldComp;
                        } else {
                          final newComp = Compartment()
                            ..key = newKey
                            ..title = newName
                            ..category = widget.categoryName
                            ..createdAt = DateTime.now();
                          final id = await isar.compartments.put(newComp);
                          newComp.id = id;
                          targetComp = newComp;
                        }

                        final receipts =
                            await isar.receiptEntitys.where().findAll();
                        for (final r in receipts) {
                          final currentKey = merchantKeyFor(
                            (r.merchant?.trim().isEmpty ?? true)
                                ? 'Unknown'
                                : r.merchant!,
                          );

                          if (currentKey == oldKey) {
                            r
                              ..merchant = newName
                              ..merchantKey = newKey
                              ..compartmentId = targetComp!.id;
                            await isar.receiptEntitys.put(r);
                          }
                        }

                        if (oldComp != null &&
                            targetComp != null &&
                            oldComp.id != targetComp.id) {
                          final remaining = await isar.receiptEntitys
                              .filter()
                              .compartmentIdEqualTo(oldComp.id)
                              .findFirst();

                          if (remaining == null) {
                            await isar.compartments.delete(oldComp.id);
                          }
                        }
                      });

                      if (mounted) {
                        Navigator.pop(context);
                        await _loadVendors();
                      }
                    },
                    child: const Text(
                      "Save",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FF),
      appBar: AppBar(
        title: Text(widget.categoryName),
        backgroundColor: Colors.white,
        foregroundColor: _appBlue,
        elevation: 0.4,
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Search Bar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    onChanged: _filterVendors,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, color: _appBlue),
                      hintText: "Search vendors...",
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),

                // Vendors List
                Expanded(
                  child: _filteredKeys.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.store_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                "No vendors found",
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: _filteredKeys.length,
                          separatorBuilder: (_, __) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Container(
                              height: 1,
                              color: Colors.grey.shade300,
                            ),
                          ),
                          itemBuilder: (context, index) {
                            final merchant = _filteredKeys[index];
                            final receipts = _vendors[merchant] ?? [];

                            final isFirst = index == 0;
                            final isLast = index == _filteredKeys.length - 1;

                            final radius = BorderRadius.only(
                              topLeft:
                                  isFirst ? const Radius.circular(12) : Radius.zero,
                              topRight:
                                  isFirst ? const Radius.circular(12) : Radius.zero,
                              bottomLeft:
                                  isLast ? const Radius.circular(12) : Radius.zero,
                              bottomRight:
                                  isLast ? const Radius.circular(12) : Radius.zero,
                            );

                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: ClipRRect(
                                borderRadius: radius,
                                child: Slidable(
                                  key: Key(merchant),
                                  endActionPane: ActionPane(
                                    motion: const DrawerMotion(),
                                    extentRatio: 0.55,
                                    children: [
                                      SlidableAction(
                                        onPressed: (_) =>
                                            _showEditVendorDialog(merchant),
                                        backgroundColor: Colors.blueAccent,
                                        foregroundColor: Colors.white,
                                        icon: Icons.edit,
                                        label: "Edit",
                                      ),
                                      SlidableAction(
                                        onPressed: (_) =>
                                            _deleteVendor(merchant),
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                        icon: Icons.delete,
                                        label: "Delete",
                                      ),
                                    ],
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: radius,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 10,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => CompartmentPage(
                                              merchant: merchant,
                                              receipts: receipts,
                                            ),
                                          ),
                                        ).then((_) => _loadVendors());
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 56,
                                              height: 56,
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [_appBlue, _lightBlue],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  _formatMerchant(merchant)
                                                      .substring(0, 1)
                                                      .toUpperCase(),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Text(
                                                _formatMerchant(merchant),
                                                style: const TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.black87,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}