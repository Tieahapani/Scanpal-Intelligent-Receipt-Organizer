import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'entities.dart';

class LocalDb {
  static Isar? _isar;

  static Future<Isar> instance() async {
    // ✅ Prevent reopening if already open
    if (_isar != null && _isar!.isOpen) return _isar!;

    final dir = await getApplicationDocumentsDirectory();

    _isar = await Isar.open(
      [
        CompartmentSchema,
        ReceiptEntitySchema,
        UserEntitySchema, // ✅ user schema included
      ],
      directory: dir.path,
      inspector: false,
    );

    return _isar!;
  }

  // ✅ Optional: close Isar cleanly
  static Future<void> close() async {
    if (_isar != null && _isar!.isOpen) {
      await _isar!.close();
      _isar = null;
    }
  }
}
