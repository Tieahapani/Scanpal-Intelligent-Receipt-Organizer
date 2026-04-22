import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api.dart';
import 'auth_service.dart';
import 'departments.dart';
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
  final _travelerSearchCtrl = TextEditingController();
  final _travelerSearchFocus = FocusNode();
  final List<Map<String, dynamic>> _selectedTravelers = []; // [{name, email, department}]
  List<Map<String, dynamic>> _travelerSuggestions = [];
  Timer? _searchDebounce;
  bool _showSuggestions = false;

  DateTime? _startDate;
  DateTime? _endDate;
  String _category = 'Conference';
  String _status = 'Upcoming';
  String? _travelType;
  Department? _selectedDepartment;
  List<Department> _departments = [];
  bool _saving = false;
  bool _isAdmin = false;

  // Primary traveler (admin only)
  Map<String, dynamic>? _primaryTraveler;

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
  void initState() {
    super.initState();
    _fetchDepartments();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    final isAdmin = await AuthService.instance.getLastRoleIsAdmin();
    if (mounted) setState(() => _isAdmin = isAdmin);
  }

  Future<void> _fetchDepartments() async {
    try {
      final depts = await _api.fetchDepartmentObjects();
      if (mounted) {
        setState(() => _departments = depts);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _destCtrl.dispose();
    _descCtrl.dispose();
    _travelerSearchCtrl.dispose();
    _travelerSearchFocus.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  bool get _isValid =>
      _nameCtrl.text.trim().isNotEmpty &&
      _destCtrl.text.trim().isNotEmpty &&
      _startDate != null &&
      _endDate != null &&
      _selectedDepartment != null &&
      (!_isAdmin || _primaryTraveler != null);

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
        'travelers': _selectedTravelers.map((t) => t['email']).join(','),
        'department': _selectedDepartment!.name,
        'department_id': _selectedDepartment!.code,
        if (_isAdmin && _primaryTraveler != null)
          'traveler_email': _primaryTraveler!['email'],
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
                    // Traveler (admin only)
                    if (_isAdmin) ...[
                      _fieldLabel('TRAVELER', required: true),
                      const SizedBox(height: 6),
                      _buildPrimaryTravelerField(),
                      const SizedBox(height: 18),
                    ],
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
                    // Department
                    _fieldLabel('DEPARTMENT', required: true),
                    const SizedBox(height: 6),
                    _buildDepartmentSelector(),
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
                    _fieldLabel('CO-TRAVELERS'),
                    const SizedBox(height: 6),
                    _buildTravelerChipField(),
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

  void _onTravelerSearch(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _travelerSuggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await _api.searchUsers(query.trim());
        // Filter out already-selected travelers
        final selectedEmails = _selectedTravelers.map((t) => t['email']).toSet();
        final filtered = results.where((r) => !selectedEmails.contains(r['email'])).toList();
        if (mounted) {
          setState(() {
            _travelerSuggestions = filtered;
            _showSuggestions = filtered.isNotEmpty;
          });
        }
      } catch (_) {}
    });
  }

  void _addTraveler(Map<String, dynamic> user) {
    setState(() {
      _selectedTravelers.add(user);
      _travelerSearchCtrl.clear();
      _travelerSuggestions = [];
      _showSuggestions = false;
    });
    _travelerSearchFocus.requestFocus();
  }

  void _removeTraveler(String email) {
    setState(() {
      _selectedTravelers.removeWhere((t) => t['email'] == email);
    });
  }

  Widget _buildTravelerChipField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Selected chips
              if (_selectedTravelers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _selectedTravelers.map((t) {
                      return Container(
                        padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF46166B).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              t['name'] ?? t['email'],
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF46166B),
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => _removeTraveler(t['email']),
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF46166B).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, size: 11, color: Color(0xFF46166B)),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              // Search field
              TextField(
                controller: _travelerSearchCtrl,
                focusNode: _travelerSearchFocus,
                style: const TextStyle(fontSize: 15, color: Color(0xFF1F2937)),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  hintText: _selectedTravelers.isEmpty
                      ? 'Search by name...'
                      : 'Add another...',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  isDense: true,
                ),
                onChanged: _onTravelerSearch,
              ),
            ],
          ),
        ),
        // Suggestions dropdown
        if (_showSuggestions)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _travelerSuggestions.map((user) {
                return InkWell(
                  onTap: () => _addTraveler(user),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF46166B).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            (user['name'] ?? '?')[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF46166B),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user['name'] ?? '',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              Text(
                                '${user['email']}${user['department'] != null ? ' · ${user['department']}' : ''}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.add_circle_outline, size: 18, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  void _showDepartmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        String search = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = _departments.where((d) {
              if (search.isEmpty) return true;
              final q = search.toLowerCase();
              return d.name.toLowerCase().contains(q) ||
                  d.code.contains(q);
            }).toList();

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.65,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Select Department',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: TextField(
                        onChanged: (v) => setSheetState(() => search = v),
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          hintText: 'Search by name or code...',
                          hintStyle: TextStyle(
                              fontSize: 13, color: Colors.grey.shade400),
                          prefixIcon: Icon(Icons.search,
                              size: 18, color: Colors.grey.shade400),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final dept = filtered[i];
                        final isSelected = _selectedDepartment == dept;
                        return InkWell(
                          onTap: () {
                            setState(() => _selectedDepartment = dept);
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            color: isSelected
                                ? const Color(0xFF46166B)
                                    .withValues(alpha: 0.05)
                                : null,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    dept.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: isSelected
                                          ? const Color(0xFF46166B)
                                          : const Color(0xFF374151),
                                    ),
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.check,
                                      size: 18, color: Color(0xFF46166B)),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDepartmentSelector() {
    return GestureDetector(
      onTap: _showDepartmentSheet,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(Icons.business_outlined,
                size: 18, color: Colors.grey.shade400),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _selectedDepartment?.name ?? 'Select department',
                style: TextStyle(
                  fontSize: 15,
                  color: _selectedDepartment != null
                      ? const Color(0xFF111827)
                      : Colors.grey.shade400,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down,
                size: 20, color: Colors.grey.shade400),
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

  // ── Primary Traveler (admin only) ──

  void _clearPrimaryTraveler() {
    setState(() => _primaryTraveler = null);
  }

  void _showTravelerPicker() async {
    final allTravelers = await _api.fetchAllTravelers();

    if (!mounted) return;
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TravelerPickerSheet(travelers: allTravelers),
    );
    if (selected != null) {
      setState(() => _primaryTraveler = selected);
    }
  }

  Widget _buildPrimaryTravelerField() {
    return GestureDetector(
      onTap: _showTravelerPicker,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _primaryTraveler != null
                ? const Color(0xFF46166B).withValues(alpha: 0.3)
                : Colors.grey.shade300,
          ),
          color: _primaryTraveler != null
              ? const Color(0xFF46166B).withValues(alpha: 0.04)
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(Icons.person_outline, size: 18, color: _primaryTraveler != null ? const Color(0xFF46166B) : Colors.grey.shade400),
            const SizedBox(width: 10),
            Expanded(
              child: _primaryTraveler != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _primaryTraveler!['name'] ?? '',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF46166B)),
                        ),
                        Text(
                          '${_primaryTraveler!['email']}${_primaryTraveler!['department'] != null ? ' · ${_primaryTraveler!['department']}' : ''}',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    )
                  : Text(
                      'Select traveler',
                      style: TextStyle(fontSize: 15, color: Colors.grey.shade400),
                    ),
            ),
            if (_primaryTraveler != null)
              GestureDetector(
                onTap: () {
                  _clearPrimaryTraveler();
                },
                child: Icon(Icons.close, size: 18, color: Colors.grey.shade400),
              )
            else
              Icon(Icons.keyboard_arrow_down, size: 20, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

// ── Traveler Picker Bottom Sheet ──

class _TravelerPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> travelers;
  const _TravelerPickerSheet({required this.travelers});

  @override
  State<_TravelerPickerSheet> createState() => _TravelerPickerSheetState();
}

class _TravelerPickerSheetState extends State<_TravelerPickerSheet> {
  String _search = '';

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return widget.travelers;
    final q = _search.toLowerCase();
    return widget.travelers.where((u) {
      final name = (u['name'] ?? '').toString().toLowerCase();
      final email = (u['email'] ?? '').toString().toLowerCase();
      final dept = (u['department'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q) || dept.contains(q);
    }).toList();
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Select Traveler', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
          const SizedBox(height: 12),
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _search = v),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  hintText: 'Search by name, email, or department...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                  prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey.shade400),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${filtered.length} traveler${filtered.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // List
          Flexible(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Text('No travelers found', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final user = filtered[i];
                      final name = user['name'] ?? user['email'] ?? '';
                      final email = user['email'] ?? '';
                      final dept = user['department'];
                      return InkWell(
                        onTap: () => Navigator.pop(context, user),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF46166B).withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  _initials(name),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF46166B)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
                                    ),
                                    Text(
                                      '$email${dept != null ? ' · $dept' : ''}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
