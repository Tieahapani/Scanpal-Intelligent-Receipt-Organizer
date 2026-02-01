import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CustomDateRangePicker extends StatefulWidget {
  final DateTimeRange? initialDateRange;
  final Function(DateTimeRange) onDateRangeSelected;

  const CustomDateRangePicker({
    super.key,
    this.initialDateRange,
    required this.onDateRangeSelected,
  });

  @override
  State<CustomDateRangePicker> createState() => _CustomDateRangePickerState();
}

class _CustomDateRangePickerState extends State<CustomDateRangePicker> {
  DateTime? _startDate;
  DateTime? _endDate;
  bool _showCalendar = false;
  bool _selectingStart = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialDateRange != null) {
      _startDate = widget.initialDateRange!.start;
      _endDate = widget.initialDateRange!.end;
    }
  }

  void _onDateSelected(DateTime date) {
    setState(() {
      if (_selectingStart) {
        _startDate = date;
        _selectingStart = false;
      } else {
        if (date.isBefore(_startDate!)) {
          // If end date is before start, swap them
          _endDate = _startDate;
          _startDate = date;
        } else {
          _endDate = date;
        }
      }
    });
  }

  void _applyDateRange() {
    if (_startDate != null && _endDate != null) {
      widget.onDateRangeSelected(
        DateTimeRange(start: _startDate!, end: _endDate!),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Date Display Section
          _buildDateDisplaySection(),
          
          const SizedBox(height: 20),
          
          // Hide/Show Calendar Button
          if (!_showCalendar)
            _buildShowCalendarButton()
          else
            _buildCalendarSection(),
          
          const SizedBox(height: 20),
          
          // Apply Button
          if (_startDate != null && _endDate != null)
            _buildApplyButton(),
        ],
      ),
    );
  }

  Widget _buildDateDisplaySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildDateRow(
            'From',
            _startDate,
            () {
              setState(() {
                _selectingStart = true;
                _showCalendar = true;
              });
            },
            _selectingStart && _showCalendar,
          ),
          const SizedBox(height: 12),
          _buildDateRow(
            'To',
            _endDate,
            () {
              setState(() {
                _selectingStart = false;
                _showCalendar = true;
              });
            },
            !_selectingStart && _showCalendar,
          ),
        ],
      ),
    );
  }

  Widget _buildDateRow(String label, DateTime? date, VoidCallback onTap, bool isSelected) {
    final dateFormatter = DateFormat('MMM d, y');
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE3F2FD) : const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF2196F3) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isSelected ? const Color(0xFF2196F3) : const Color(0xFF8E8E93),
              ),
            ),
            Text(
              date != null ? dateFormatter.format(date) : 'Select date',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: date != null ? const Color(0xFF1C1C1E) : const Color(0xFFAEAEB2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShowCalendarButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          setState(() {
            _showCalendar = true;
          });
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF007AFF),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: const Text(
          'Select Dates',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _selectingStart ? 'Select Start Date' : 'Select End Date',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1C1C1E),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _showCalendar = false;
                  });
                },
                child: const Text(
                  'Hide',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF007AFF),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CalendarDatePicker(
            initialDate: _selectingStart 
                ? (_startDate ?? DateTime.now()) 
                : (_endDate ?? DateTime.now()),
            firstDate: DateTime(DateTime.now().year - 2),
            lastDate: DateTime.now(),
            onDateChanged: _onDateSelected,
          ),
        ],
      ),
    );
  }

  Widget _buildApplyButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _applyDateRange,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF007AFF),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: const Text(
          'Apply Date Range',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// Function to show the custom date picker
Future<DateTimeRange?> showCustomDateRangePicker({
  required BuildContext context,
  DateTimeRange? initialDateRange,
}) async {
  DateTimeRange? selectedRange;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: CustomDateRangePicker(
          initialDateRange: initialDateRange,
          onDateRangeSelected: (range) {
            selectedRange = range;
          },
        ),
      );
    },
  );

  return selectedRange;
}