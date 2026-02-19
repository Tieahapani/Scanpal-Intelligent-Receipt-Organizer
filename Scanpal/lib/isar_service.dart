import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '/entities.dart'; // ✅ your Isar collection model (ReceiptEntity)

class IsarService {
  // Singleton pattern (so you can access IsarService.instance)
  IsarService._internal();
  static final IsarService instance = IsarService._internal();

  late final Isar isar;

  /// Initialize Isar database (only once)
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();

    // ✅ Use your actual collection name — for example ReceiptEntity
    isar = await Isar.open(
      [ReceiptEntitySchema],
      directory: dir.path,
      inspector: true, // allows live inspection during development
    );
  }

  /// Close the database safely
  Future<void> close() async {
    await isar.close();
  }
}
