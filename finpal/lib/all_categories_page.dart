import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import '/local_db.dart';
import 'entities.dart';
import 'category_all_vendors_page.dart';

class CategorySummary {
  final String category;
  int vendorCount;
  int transactionCount;
  double totalSpent;

  CategorySummary({
    required this.category,
    required this.vendorCount,
    required this.transactionCount,
    required this.totalSpent,
  });
}

class AllCategoriesPage extends StatefulWidget {
  const AllCategoriesPage({super.key});

  @override
  State<AllCategoriesPage> createState() => _AllCategoriesPageState();
}

class _AllCategoriesPageState extends State<AllCategoriesPage> {
  static const _appBlue = Color(0xFF1565C0);
  static const _lightBlue = Color(0xFF42A5F5);

  List<CategorySummary> _categories = [];
  List<CategorySummary> _filteredCategories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _loading = true);

    final isar = await LocalDb.instance();
    final compartments = await isar.compartments.where().findAll();

    final Map<String, CategorySummary> categoryMap = {};

    for (var comp in compartments) {
      if (comp.category == null || comp.category!.isEmpty) continue;

      final receipts = await isar.receiptEntitys
          .filter()
          .compartmentIdEqualTo(comp.id)
          .findAll();

      if (receipts.isEmpty) continue;

      final total = receipts.fold<double>(
        0.0,
        (sum, r) => sum + (r.total ?? 0.0),
      );

      if (categoryMap.containsKey(comp.category)) {
        categoryMap[comp.category!]!.vendorCount++;
        categoryMap[comp.category!]!.transactionCount += receipts.length;
        categoryMap[comp.category!]!.totalSpent += total;
      } else {
        categoryMap[comp.category!] = CategorySummary(
          category: comp.category!,
          vendorCount: 1,
          transactionCount: receipts.length,
          totalSpent: total,
        );
      }
    }

    final categories = categoryMap.values.toList()
      ..sort((a, b) => a.category.compareTo(b.category));

    setState(() {
      _categories = categories;
      _filteredCategories = categories;
      _loading = false;
    });
  }

  void _filterCategories(String query) {
    setState(() {
      _filteredCategories = _categories
          .where((cat) =>
              cat.category.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  IconData getCategoryIcon(String category) {
    switch (category) {
      case 'Groceries':
        return Icons.shopping_cart;
      case 'Food & Drinks':
        return Icons.restaurant;
      case 'Entertainment':
        return Icons.movie;
      case 'Travel':
        return Icons.directions_bus;
      case 'Clothing':
        return Icons.shopping_bag;
      case 'Electronics':
        return Icons.devices;
      case 'Utilities':
        return Icons.water_drop;
      case 'Office Supplies':
        return Icons.edit_note;
      default:
        return Icons.category;
    }
  }

  Color getCategoryColor(String category) {
    switch (category) {
      case 'Groceries':
        return const Color(0xFF4CAF50);
      case 'Food & Drinks':
        return const Color(0xFFFF9800);
      case 'Entertainment':
        return const Color(0xFFE91E63);
      case 'Travel':
        return const Color(0xFF2196F3);
      case 'Clothing':
        return const Color(0xFF9C27B0);
      case 'Electronics':
        return const Color(0xFFF44336);
      case 'Utilities':
        return const Color(0xFF00BCD4);
      case 'Office Supplies':
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
        title: const Text("All Categories"),
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
                    onChanged: _filterCategories,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, color: _appBlue),
                      hintText: "Search categories...",
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),

                // Categories List
                Expanded(
                  child: _filteredCategories.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.category_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                "No categories found",
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
                          itemCount: _filteredCategories.length,
                          separatorBuilder: (_, __) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Container(
                              height: 1,
                              color: Colors.grey.shade300,
                            ),
                          ),
                          itemBuilder: (context, index) {
                            final category = _filteredCategories[index];
                            final categoryColor =
                                getCategoryColor(category.category);
                            final categoryIcon =
                                getCategoryIcon(category.category);

                            final isFirst = index == 0;
                            final isLast =
                                index == _filteredCategories.length - 1;

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
                                          builder: (_) =>
                                              CategoryAllVendorsPage(
                                            categoryName: category.category,
                                          ),
                                        ),
                                      ).then((_) => _loadCategories());
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 56,
                                            height: 56,
                                            decoration: BoxDecoration(
                                              color: categoryColor
                                                  .withOpacity(0.15),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              categoryIcon,
                                              color: categoryColor,
                                              size: 28,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  category.category,
                                                  style: const TextStyle(
                                                    fontSize: 17,
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  "${category.transactionCount} transaction${category.transactionCount != 1 ? 's' : ''}",
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            "\$${category.totalSpent.toStringAsFixed(2)}",
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
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