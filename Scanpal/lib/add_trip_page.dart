import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api.dart';
import 'travel_calendar.dart';

class AddTripPage extends StatefulWidget {
  const AddTripPage({super.key});

  @override
  State<AddTripPage> createState() => _AddTripPageState();
}

class _AddTripPageState extends State<AddTripPage> {
  final _api = APIService();
  final _nameCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _travelersCtrl = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  String _category = 'Conference';
  String _status = 'Upcoming';
  String? _travelType;
  bool _saving = false;

  static const _categories = [
    'Conference',
    'Advocacy',
    'Meeting',
    'Retreat',
    'Workshop',
    'Other',
  ];
  static const _statuses = ['Active', 'Completed', 'Upcoming'];
  static const _travelTypes = ['TAAR', 'One Day Travel', 'Exception'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _destCtrl.dispose();
    _descCtrl.dispose();
    _travelersCtrl.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _nameCtrl.text.trim().isNotEmpty &&
      _destCtrl.text.trim().isNotEmpty &&
      _startDate != null &&
      _endDate != null;

  Future<void> _pickDates() async {
    final result = await showTravelCalendar(
      context,
      initialStart: _startDate,
      initialEnd: _endDate,
    );
    if (result != null) {
      setState(() {
        _startDate = result.start;
        _endDate = result.end;
      });
    }
  }

  Future<void> _create() async {
    if (!_isValid) return;
    setState(() => _saving = true);
    try {
      final dest = _destCtrl.text.trim();
      final data = <String, dynamic>{
        'trip_purpose': _nameCtrl.text.trim(),
        'destination': dest,
        'departure_date': _startDate!.toIso8601String().split('T')[0],
        'return_date': _endDate!.toIso8601String().split('T')[0],
        'travel_type': _travelType,
        'category': _category,
        'status': _status.toLowerCase(),
        'description': _descCtrl.text.trim(),
        'travelers': _travelersCtrl.text.trim(),
      };

      final trip = await _api.createTrip(data);
      if (!mounted) return;
      Navigator.pop(context, trip);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Failed to create trip: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.arrow_back,
                          size: 18, color: Color(0xFF4B5563)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Add New Trip',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ],
              ),
            ),
            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Trip Name
                    _fieldLabel('TRIP NAME', required: true),
                    const SizedBox(height: 6),
                    _textField(_nameCtrl, 'e.g. Google Cloud Workshop',
                        onChanged: (_) => setState(() {})),
                    const SizedBox(height: 18),
                    // Destination
                    _fieldLabel('DESTINATION'),
                    const SizedBox(height: 6),
                    _textField(_destCtrl, 'e.g. Los Angeles, CA',
                        onChanged: (_) => setState(() {})),
                    const SizedBox(height: 18),
                    // Start / End Date
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('START DATE', required: true),
                              const SizedBox(height: 6),
                              _dateField(
                                value: _startDate != null
                                    ? dateFormat.format(_startDate!)
                                    : dateFormat.format(DateTime.now()),
                                onTap: _pickDates,
                                hasValue: _startDate != null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('END DATE', required: true),
                              const SizedBox(height: 6),
                              _dateField(
                                value: _endDate != null
                                    ? dateFormat.format(_endDate!)
                                    : dateFormat.format(
                                        DateTime.now().add(const Duration(days: 3))),
                                onTap: _pickDates,
                                hasValue: _endDate != null,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Travel Type
                    _fieldLabel('TRAVEL TYPE'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _travelTypes.map((type) {
                        final selected = _travelType == type;
                        return GestureDetector(
                          onTap: () => setState(() => _travelType = type),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: selected ? const Color(0xFF46166B) : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected ? const Color(0xFF46166B) : Colors.grey.shade300,
                              ),
                            ),
                            child: Text(
                              type,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: selected ? Colors.white : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    // Category
                    _fieldLabel('CATEGORY'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _categories.map((cat) {
                        final selected = _category == cat;
                        return GestureDetector(
                          onTap: () => setState(() => _category = cat),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF46166B)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFF46166B)
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF4B5563),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    // Status
                    _fieldLabel('STATUS'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _statuses.map((s) {
                        final selected = _status == s;
                        return GestureDetector(
                          onTap: () => setState(() => _status = s),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF1F2937)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFF1F2937)
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Text(
                              s,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF4B5563),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    // Description
                    _fieldLabel('DESCRIPTION'),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: TextField(
                        controller: _descCtrl,
                        maxLines: 4,
                        style: const TextStyle(
                            fontSize: 15, color: Color(0xFF1F2937)),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(14),
                          hintText: 'Brief description of this trip...',
                          hintStyle: TextStyle(color: Colors.grey.shade400),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Travelers
                    _fieldLabel('TRAVELERS (COMMA-SEPARATED)'),
                    const SizedBox(height: 6),
                    _textField(_travelersCtrl, 'Princy R., Alex M.'),
                    const SizedBox(height: 16),
                    // Required fields note
                    Center(
                      child: Text.rich(
                        TextSpan(
                          text: 'Please fill in all required fields marked with ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                          children: const [
                            TextSpan(
                              text: '*',
                              style: TextStyle(
                                color: Color(0xFFEF4444),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Create button
                    GestureDetector(
                      onTap: (_saving || !_isValid) ? null : _create,
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          color: _isValid
                              ? const Color(0xFF46166B)
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add,
                                      size: 18,
                                      color: _isValid
                                          ? Colors.white
                                          : Colors.grey.shade500),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Create Trip',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: _isValid
                                          ? Colors.white
                                          : Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String text, {bool required = false}) {
    if (required) {
      return Text.rich(
        TextSpan(
          text: '$text ',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
            letterSpacing: 0.8,
          ),
          children: const [
            TextSpan(
              text: '*',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade500,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _textField(TextEditingController ctrl, String hint,
      {ValueChanged<String>? onChanged}) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TextField(
        controller: ctrl,
        style: const TextStyle(fontSize: 15, color: Color(0xFF1F2937)),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
          isDense: true,
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget _dateField({required String value, required VoidCallback onTap, bool hasValue = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          style: TextStyle(
            fontSize: 15,
            color: hasValue ? const Color(0xFF111827) : Colors.grey.shade400,
          ),
        ),
      ),
    );
  }
}
