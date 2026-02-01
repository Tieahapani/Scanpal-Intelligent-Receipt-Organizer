import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:isar/isar.dart';
import '/local_db.dart';
import 'entities.dart';
import 'compartment_page.dart';
import 'home_screen.dart';
import 'monthly_summary_page.dart';
import 'all_categories_page.dart';
import 'profile_page.dart';

class VendorSummary {
  final String merchant;
  final int transactionCount;
  final double totalSpent;
  final List<ReceiptEntity> receipts;

  VendorSummary({
    required this.merchant,
    required this.transactionCount,
    required this.totalSpent,
    required this.receipts,
  });
}

class CategoryVendorsPage extends StatefulWidget {
  final String categoryName;
  final bool darkMode;
  final Function(bool) onThemeChanged;

  const CategoryVendorsPage({
    super.key,
    required this.categoryName,
    required this.darkMode,
    required this.onThemeChanged,
  });

  @override
  State<CategoryVendorsPage> createState() => _CategoryVendorsPageState();
}

class _CategoryVendorsPageState extends State<CategoryVendorsPage> {
  List<VendorSummary> _vendors = [];
  bool _loading = true;
  int _totalTransactions = 0;
  double _totalSpent = 0.0;
  int _selectedIndex = 0;

  static const _appBlue = Color(0xFF1565C0);
  static const _lightBlue = Color(0xFF42A5F5);

  @override
  void initState() {
    super.initState();
    _loadVendors();
  }

  void _showScanSheet() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        height: 180,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                // Navigate to home screen which has the camera functionality
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HomeScreen(
                      darkMode: widget.darkMode,
                      onThemeChanged: widget.onThemeChanged,
                    ),
                  ),
                  (route) => false,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Upload from gallery'),
              onTap: () {
                Navigator.pop(context);
                // Navigate to home screen which has the gallery functionality
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HomeScreen(
                      darkMode: widget.darkMode,
                      onThemeChanged: widget.onThemeChanged,
                    ),
                  ),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadVendors() async {
    setState(() => _loading = true);

    final isar = await LocalDb.instance();

    // Get all compartments in this category
    final compartments = await isar.compartments
        .filter()
        .categoryEqualTo(widget.categoryName)
        .findAll();

    final List<VendorSummary> vendors = [];
    int totalTrans = 0;
    double totalSpend = 0.0;

    for (var comp in compartments) {
      // Get ALL receipts for this vendor (not just from this category)
      final receipts = await isar.receiptEntitys
          .filter()
          .compartmentIdEqualTo(comp.id)
          .findAll();

      if (receipts.isEmpty) continue;

      final total = receipts.fold<double>(
        0.0,
        (sum, r) => sum + (r.total ?? 0.0),
      );

      vendors.add(VendorSummary(
        merchant: comp.title,
        transactionCount: receipts.length,
        totalSpent: total,
        receipts: receipts,
      ));

      // For category summary, only count receipts in THIS category
      final categoryReceipts = receipts.where((r) => r.category == widget.categoryName).toList();
      totalTrans += categoryReceipts.length;
      totalSpend += categoryReceipts.fold<double>(0.0, (sum, r) => sum + (r.total ?? 0.0));
    }

    // Sort by total spent (descending) and take top 5
    vendors.sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
    final topVendors = vendors.take(5).toList();

    setState(() {
      _vendors = topVendors;
      _totalTransactions = totalTrans;
      _totalSpent = totalSpend;
      _loading = false;
    });
  }

  Future<void> _deleteVendor(String merchant) async {
  // Directly delete without confirmation
  // ... rest of delete logic (keep everything after the dialog code)

 

    final isar = await LocalDb.instance();
    final merchantKey = merchantKeyFor(merchant);

    await isar.writeTxn(() async {
      final receipts = await isar.receiptEntitys
          .filter()
          .merchantKeyEqualTo(merchantKey)
          .findAll();

      for (var r in receipts) {
        if (r.imagePath != null && File(r.imagePath!).existsSync()) {
          await File(r.imagePath!).delete();
        }
        await isar.receiptEntitys.delete(r.id!);
      }

      final comp = await isar.compartments
          .filter()
          .keyEqualTo(merchantKey)
          .findFirst();
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
                        Compartment? oldCompartment = await isar.compartments
                            .filter()
                            .keyEqualTo(oldKey)
                            .findFirst();

                        Compartment? targetCompartment = await isar.compartments
                            .filter()
                            .keyEqualTo(newKey)
                            .findFirst();

                        if (targetCompartment != null) {
                          targetCompartment.title = newName;
                          await isar.compartments.put(targetCompartment);
                        } else if (oldCompartment != null) {
                          oldCompartment
                            ..key = newKey
                            ..title = newName;
                          await isar.compartments.put(oldCompartment);
                          targetCompartment = oldCompartment;
                        } else {
                          final newCompartment = Compartment()
                            ..key = newKey
                            ..title = newName
                            ..category = widget.categoryName
                            ..createdAt = DateTime.now();
                          final newId =
                              await isar.compartments.put(newCompartment);
                          newCompartment.id = newId;
                          targetCompartment = newCompartment;
                        }

                        final receipts =
                            await isar.receiptEntitys.where().findAll();
                        for (final receipt in receipts) {
                          final currentKey = merchantKeyFor(
                            (receipt.merchant == null ||
                                    receipt.merchant!.trim().isEmpty)
                                ? 'Unknown'
                                : receipt.merchant!,
                          );
                          if (currentKey == oldKey) {
                            receipt
                              ..merchant = newName
                              ..merchantKey = newKey;
                            receipt.compartmentId = targetCompartment!.id;
                            await isar.receiptEntitys.put(receipt);
                          }
                        }

                        if (oldCompartment != null &&
                            targetCompartment != null &&
                            oldCompartment.id != targetCompartment.id) {
                          final remaining = await isar.receiptEntitys
                              .filter()
                              .compartmentIdEqualTo(oldCompartment.id)
                              .findFirst();
                          if (remaining == null) {
                            await isar.compartments.delete(oldCompartment.id);
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

  IconData _getCategoryIcon() {
    switch (widget.categoryName.toLowerCase()) {
      case 'groceries':
        return Icons.shopping_cart;
      case 'restaurants':
      case 'food & drinks':
        return Icons.restaurant;
      case 'entertainment':
        return Icons.movie;
      case 'transport':
        return Icons.directions_bus;
      case 'shopping':
        return Icons.shopping_bag;
      case 'health':
        return Icons.health_and_safety;
      case 'utilities':
        return Icons.water_drop;
      case 'education':
        return Icons.school;
      default:
        return Icons.category;
    }
  }

  Color _getCategoryColor() {
    switch (widget.categoryName.toLowerCase()) {
      case 'groceries':
        return const Color(0xFF4CAF50);
      case 'restaurants':
      case 'food & drinks':
        return const Color(0xFFFF9800);
      case 'entertainment':
        return const Color(0xFFE91E63);
      case 'transport':
        return const Color(0xFF2196F3);
      case 'shopping':
        return const Color(0xFF9C27B0);
      case 'health':
        return const Color(0xFFF44336);
      case 'utilities':
        return const Color(0xFF00BCD4);
      case 'education':
        return const Color(0xFF3F51B5);
      default:
        return const Color(0xFF607D8B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.categoryName,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _vendors.isEmpty
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
                        "No vendors in this category",
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 12, bottom: 10, top: 10),
                      child: Text(
                        "Top Vendors",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                            ..._vendors.map((vendor) {
                              return Slidable(
                                key: Key(vendor.merchant),
                                endActionPane: ActionPane(
                                  motion: const DrawerMotion(),
                                  extentRatio: 0.65,
                                  children: [
                                    CustomSlidableAction(
                                      backgroundColor: Colors.transparent,
                                      onPressed: (_) {},
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: InkWell(
                                              onTap: () => _showEditVendorDialog(
                                                  vendor.merchant),
                                              child: Container(
                                                height: 72,
                                                decoration: BoxDecoration(
                                                  color: Colors.blueAccent,
                                                  borderRadius:
                                                      const BorderRadius.only(
                                                    bottomLeft:
                                                        Radius.circular(12),
                                                    topLeft: Radius.circular(12),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: const [
                                                    Icon(Icons.edit,
                                                        color: Colors.white,
                                                        size: 18),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      "Edit",
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: InkWell(
                                              onTap: () =>
                                                  _deleteVendor(vendor.merchant),
                                              child: Container(
                                                height: 72,
                                                decoration: BoxDecoration(
                                                  color: Colors.redAccent,
                                                  borderRadius:
                                                      const BorderRadius.only(
                                                    topRight: Radius.circular(12),
                                                    bottomRight:
                                                        Radius.circular(12),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: const [
                                                    Icon(Icons.delete,
                                                        color: Colors.white,
                                                        size: 18),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      "Delete",
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                child: Container(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CompartmentPage(
                                            merchant: vendor.merchant,
                                            receipts: vendor.receipts,
                                          ),
                                        ),
                                      ).then((_) => _loadVendors());
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                        horizontal: 16,
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 48,
                                            height: 48,
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
                                                vendor.merchant
                                                    .substring(0, 1)
                                                    .toUpperCase(),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Text(
                                              vendor.merchant,
                                              style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ],
                        ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              gradient: const LinearGradient(
                colors: [_appBlue, _lightBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _NavIcon(
                  index: 0,
                  icon: Icons.receipt_long,
                  selectedIndex: _selectedIndex,
                  onTap: () {
                    // Navigate back to home screen
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HomeScreen(
                          darkMode: widget.darkMode,
                          onThemeChanged: widget.onThemeChanged,
                        ),
                      ),
                      (route) => false,
                    );
                  },
                ),
                _NavIcon(
                  index: 1,
                  icon: Icons.show_chart,
                  selectedIndex: _selectedIndex,
                  onTap: () {
                    setState(() => _selectedIndex = 1);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MonthlySummaryPage()),
                    ).then((_) => setState(() => _selectedIndex = 0));
                  },
                ),
                _NavIcon(
                  index: 2,
                  icon: Icons.add_circle,
                  size: 36,
                  selectedIndex: _selectedIndex,
                  onTap: _showScanSheet,
                ),
                _NavIcon(
                  index: 3,
                  icon: Icons.folder_open,
                  selectedIndex: _selectedIndex,
                  onTap: () {
                    setState(() => _selectedIndex = 3);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AllCategoriesPage()),
                    ).then((_) {
                      if (mounted) setState(() => _selectedIndex = 0);
                      _loadVendors();
                    });
                  },
                ),
                _NavIcon(
                  index: 4,
                  icon: Icons.settings,
                  selectedIndex: _selectedIndex,
                  onTap: () {
                    setState(() => _selectedIndex = 4);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ProfilePage(
                                darkMode: widget.darkMode,
                                onThemeChanged: widget.onThemeChanged,
                              )),
                    ).then((_) => setState(() => _selectedIndex = 0));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final int index;
  final int selectedIndex;
  final VoidCallback onTap;
  final double size;

  const _NavIcon({
    required this.icon,
    required this.index,
    required this.selectedIndex,
    required this.onTap,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSelected = index == selectedIndex;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutQuad,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? Colors.white : Colors.transparent,
        ),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 200),
          scale: isSelected ? 1.1 : 1.0,
          curve: Curves.easeOutBack,
          child: Icon(
            icon,
            size: size,
            color: isSelected ? const Color(0xFF1565C0) : Colors.grey[300],
          ),
        ),
      ),
    );
  }
}