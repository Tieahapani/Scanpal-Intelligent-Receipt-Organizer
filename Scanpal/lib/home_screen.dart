// 1. Add to pubspec.yaml:
// dependencies:
//   cunning_document_scanner: ^1.2.3
//   image_cropper: ^5.0.1 # For iOS gallery
//   image_picker: ^1.0.4 # For iOS gallery

// 2. iOS Permissions (ios/Runner/Info.plist):
//   <key>NSCameraUsageDescription</key>
//   <string>We need camera access to scan receipts</string>
//   <key>NSPhotoLibraryUsageDescription</key>
//   <string>We need photo library access to import receipts</string>

// 3. iOS minimum version (ios/Podfile):
//   platform :ios, '11.0'

// ===== UPDATED CODE =====

import 'dart:io';
import 'dart:typed_data';
import 'package:finpal/all_categories_page.dart';
import 'package:finpal/category_vendors_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'api.dart';
import 'receipt_repository.dart';
import 'entities.dart';
import 'profile_page.dart';
import 'compartment_page.dart';
import 'monthly_summary_page.dart';
import '/local_db.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:image_cropper/image_cropper.dart';



class CategorySummary {
  final String category;
  int transactionCount;
  double totalSpent;
  String currency; // ← NEW: Track by currency

  CategorySummary({
    required this.category,
    required this.transactionCount,
    required this.totalSpent,
    this.currency = '\$'
  });

  // For backward compatibility

}

class EmptyReceiptsView extends StatelessWidget {
  const EmptyReceiptsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFF6F7FB),
            Color(0xFFEFF1F6),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 80,
            color: Colors.grey,
          ),
          const SizedBox(height: 20),
          const Text(
            "No receipts here yet.",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Scan a receipt to get started",
            style: TextStyle(
              fontSize: 15,
              color: Colors.black38,
            ),
          ),
        ],
      ),
    );
  }
}

class LensScanOverlay extends StatefulWidget {
  final Uint8List imageBytes;

  const LensScanOverlay({super.key, required this.imageBytes});

  @override
  State<LensScanOverlay> createState() => _LensScanOverlayState();
}

class _LensScanOverlayState extends State<LensScanOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.black.withOpacity(0.5),
      child: Stack(
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                widget.imageBytes,
                fit: BoxFit.contain,
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Positioned(
                top: MediaQuery.of(context).size.height * 0.1 +
                    (_controller.value *
                        MediaQuery.of(context).size.height *
                        0.7),
                left: 0,
                right: 0,
                child: Container(
                  height: 20,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue.withOpacity(0),
                        Colors.blue.withOpacity(0.5),
                        Colors.blue.withOpacity(0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                "Scanning receipt…",
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final bool darkMode;
  final Function(bool) onThemeChanged;

  const HomeScreen({
    super.key,
    required this.darkMode,
    required this.onThemeChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = APIService();
  final _picker = ImagePicker();
  final _repo = ReceiptRepository();

  bool _loading = false;
  Map<String, List<ReceiptEntity>> _compartments = {};
  String? _userName;
  int _selectedIndex = 0;

  static const _appBlue = Color(0xFF1565C0);
  static const _lightBlue = Color(0xFF42A5F5);

  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 300), () async {
      await _loadUser();
      await _loadCompartments();
    });

    _scrollController.addListener(() {
      setState(() {
        _scrollOffset = _scrollController.offset.clamp(0, 120);
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final user = await _repo.getCurrentUser();
    if (mounted) setState(() => _userName = user?.username ?? "User");
  }

  Future<void> _loadCompartments() async {
    final isar = await LocalDb.instance();
    final receipts = await isar.receiptEntitys.where().findAll();

    final Map<String, List<ReceiptEntity>> grouped = {};
    for (final receipt in receipts) {
      final merchant = (receipt.merchant?.trim().isNotEmpty ?? false)
          ? receipt.merchant!.trim()
          : "Unknown";
      grouped.putIfAbsent(merchant, () => []).add(receipt);
    }

    if (mounted) setState(() => _compartments = grouped);
  }



  // ✅ Camera scanning with cunning_document_scanner (auto-crop)
  Future<String?> scanWithCamera() async {
    try {
      List<String> pictures = await CunningDocumentScanner.getPictures(
            noOfPages: 1,
            isGalleryImportAllowed: false, // Camera only
          ) ??
          [];
      if (pictures.isEmpty) return null;
      return pictures.first;
    } catch (e) {
      debugPrint("Camera scan error: $e");
      return null;
    }
  }

  // ✅ Gallery scanning - Platform specific
  Future<String?> scanFromGallery() async {
    try {
      if (Platform.isAndroid) {
        // Android: Use cunning_document_scanner (auto-crop)
        List<String> pictures = await CunningDocumentScanner.getPictures(
              noOfPages: 1,
              isGalleryImportAllowed: true, // Gallery allowed on Android
            ) ??
            [];
        if (pictures.isEmpty) return null;
        return pictures.first;
      } else {
        // iOS: Use image_picker + manual cropper
        final XFile? pickedFile = await _picker.pickImage(
          source: ImageSource.gallery,
        );
        if (pickedFile == null) return null;

        // Manual crop for iOS
        final croppedPath = await _cropImage(pickedFile.path);
        return croppedPath;
      }
    } catch (e) {
      debugPrint("Gallery scan error: $e");
      return null;
    }
  }

  // ✅ Manual image cropper for iOS gallery
  Future<String?> _cropImage(String imagePath) async {
    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: imagePath,
        compressQuality: 95,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Receipt',
            toolbarColor: _appBlue,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
          IOSUiSettings(
            title: 'Crop Receipt',
            minimumAspectRatio: 0.5,
          ),
        ],
      );

      if (croppedFile == null) return null;

      // Enhance image quality
      final bytes = await File(croppedFile.path).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return croppedFile.path;

      // Resize if too large
      if (image.width > 2000) {
        image = img.copyResize(image, width: 2000);
      }

      // Enhance contrast and brightness
      image = img.adjustColor(
        image,
        contrast: 1.1,
        brightness: 1.05,
      );

      // Save enhanced image
      final enhancedPath = croppedFile.path.replaceAll('.jpg', '_enhanced.jpg');
      await File(enhancedPath).writeAsBytes(
        img.encodeJpg(image, quality: 95),
      );

      return enhancedPath;
    } catch (e) {
      debugPrint('Crop error: $e');
      return null;
    }
  }

  Future<List<CategorySummary>> getTopCategories(Isar isar) async {
  final compartments = await isar.compartments.where().findAll();
  final List<CategorySummary> categories = [];

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

    // ← NEW: Get currency from the first receipt (all receipts in same category likely same currency)
    final currency = receipts.first.currency ?? '\$';

    // Find existing category or create new
    final existingIndex =
        categories.indexWhere((c) => c.category == comp.category);
    if (existingIndex != -1) {
      categories[existingIndex].transactionCount += receipts.length;
      categories[existingIndex].totalSpent += total;
    } else {
      categories.add(CategorySummary(
        category: comp.category!,
        transactionCount: receipts.length,
        totalSpent: total,
        currency: currency,  // ← NEW: Store currency
      ));
    }
  }

  categories.sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
  return categories.take(5).toList();
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
        return Icons.school;
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

  String _formatMerchant(String name) {
    name = name.replaceAll(RegExp(r'[._]+'), ' ').trim();
    final words = name.split(' ');
    return words
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  Widget _buildTopCategoriesSection() {
    return FutureBuilder(
      future: LocalDb.instance().then((isar) => getTopCategories(isar)),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final topCategories = snapshot.data!;
        if (topCategories.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 12, bottom: 10, top: 10),
              child: Text(
                "Top Categories",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            ...topCategories.map((category) {
              final categoryColor = getCategoryColor(category.category);
              final categoryIcon = getCategoryIcon(category.category);

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
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
                        builder: (_) => CategoryVendorsPage(
                          categoryName: category.category,
                          darkMode: widget.darkMode,
                          onThemeChanged: widget.onThemeChanged,
                        ),
                      ),
                    ).then((_) => _loadCompartments());
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: categoryColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            categoryIcon,
                            color: categoryColor,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                category.category,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
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
                           "${category.currency}${category.totalSpent.toStringAsFixed(2)}",
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
              );
            }).toList(),
          ],
        );
      },
    );
  }

  Future<File> _compressReceiptImage(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  img.Image? image = img.decodeImage(bytes);
  
  if (image == null) return File(imagePath);

  // Resize to max 1500px width
  if (image.width > 1500) {
    image = img.copyResize(image, width: 1500);
  }
  
  // Enhance for OCR
  image = img.adjustColor(
    image,
    contrast: 1.15,
    brightness: 1.08,
  );

  // Compress to JPEG
  Uint8List compressedBytes = img.encodeJpg(image, quality: 85);

  // If still > 3MB, compress more aggressively
  if (compressedBytes.length > 3 * 1024 * 1024) {
    compressedBytes = img.encodeJpg(image, quality: 70);
  }

  // Save compressed version
  final compressedPath = imagePath.replaceAll('.jpg', '_compressed.jpg')
                                  .replaceAll('.png', '_compressed.jpg');
  await File(compressedPath).writeAsBytes(compressedBytes);
  
  debugPrint('Compressed: ${compressedBytes.length ~/ 1024}KB (was ${bytes.length ~/ 1024}KB)');
  return File(compressedPath);
}




  // ✅ MAIN: Pick and upload - platform aware
  Future<void> _pickAndUpload(ImageSource source) async {
    BuildContext? loaderContext;

    try {
      String? scannedPath;

      // Choose method based on source
      if (source == ImageSource.camera) {
        // Camera: cunning_document_scanner (auto-crop both platforms)
        scannedPath = await scanWithCamera();
      } else {
        // Gallery: cunning on Android, manual crop on iOS
        scannedPath = await scanFromGallery();
      }

      if (scannedPath == null) return; // User cancelled

      // Read the scanned/cropped image
      final File imageFile = File(scannedPath);
      final Uint8List processedBytes = await imageFile.readAsBytes();

      // Show scanning overlay
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          loaderContext = ctx;
          return LensScanOverlay(imageBytes: processedBytes);
        },
      );

      // Save to permanent storage
      final appDir = await getApplicationSupportDirectory();
      final fileName = 'receipt_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final permanentPath = '${appDir.path}/$fileName';
      await File(permanentPath).writeAsBytes(processedBytes);
      final compressedFile = await _compressReceiptImage(permanentPath);

      // Upload to API for OCR
      final uploaded = await _api.uploadReceipt(compressedFile);

      final detectedCurrency = uploaded.currency ?? '\$';
      final realMerchant = uploaded.merchant ?? "Unknown";
      final realKey = merchantKeyFor(realMerchant);
      final category = uploaded.category; // ✅ Get category from backend

      final isar = await LocalDb.instance();

      // Save to local database
      await isar.writeTxn(() async {
        var comp = await isar.compartments
            .filter()
            .keyEqualTo(realKey)
            .findFirst();

        if (comp != null) {
          // Update existing compartment with new category if provided
          if (category != null && category.isNotEmpty) {
            comp.category = category;
            await isar.compartments.put(comp);
          }
        } else {
          // Create new compartment with category
          comp = Compartment()
            ..key = realKey
            ..title = realMerchant
            ..createdAt = DateTime.now()
            ..category = category; // ✅ Save category from Gemini
          comp.id = await isar.compartments.put(comp);
        }

        await isar.receiptEntitys.put(
          ReceiptEntity()
            ..merchant = realMerchant
            ..merchantKey = realKey
            ..compartmentId = comp!.id
            ..date = uploaded.date ?? DateTime.now()
            ..total = uploaded.total ?? 0.0
            ..address = uploaded.address
            ..currency = detectedCurrency
            ..imagePath = permanentPath
            ..category = category // ✅ Also save to receipt for reference
            ..items = uploaded.items.map((it) {
              return LineItemEmb()
                ..name = it.name
                ..quantity = it.quantity
                ..unitPrice = it.unitPrice
                ..total = it.total;
            }).toList(),
        );
      });

      await _loadCompartments();
    } catch (e) {
      debugPrint("Error uploading receipt: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing receipt: $e')),
        );
      }
    } finally {
      if (loaderContext != null && mounted) {
        Navigator.pop(loaderContext!);
      }
    }
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
                _pickAndUpload(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Upload from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUpload(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FF),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.only(
                  top: 55, left: 20, right: 20, bottom: 12),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: const [
                  Text(
                    "Receipts",
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Track spending across your favorite categories",
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 10)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildTopCategoriesSection(),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_compartments.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyReceiptsView(),
            ),
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
                  onTap: () => setState(() => _selectedIndex = 0),
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
                      _loadCompartments();
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