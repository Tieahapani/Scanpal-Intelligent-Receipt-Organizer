import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const Color _kPrimary = Color(0xFF4A2080);
const Color _kAccentYellow = Color(0xFFFBBF24);
const Color _kRangeBg = Color(0xFFDDD0F0);
const Color _kBorder = Color(0xFFE5E7EB);
const Color _kTextDefault = Color(0xFF111827);
const Color _kTextSubdued = Color(0xFF6B7281);

/// Shows a custom travel calendar dialog that lets the user pick a date range.
/// Returns a record of (start, end) dates, or null if cancelled.
Future<({DateTime start, DateTime end})?> showTravelCalendar(
  BuildContext context, {
  DateTime? initialStart,
  DateTime? initialEnd,
}) {
  return showDialog<({DateTime start, DateTime end})>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.4),
    builder: (_) => _TravelCalendarDialog(
      initialStart: initialStart,
      initialEnd: initialEnd,
    ),
  );
}

class _TravelCalendarDialog extends StatefulWidget {
  final DateTime? initialStart;
  final DateTime? initialEnd;

  const _TravelCalendarDialog({this.initialStart, this.initialEnd});

  @override
  State<_TravelCalendarDialog> createState() => _TravelCalendarDialogState();
}

class _TravelCalendarDialogState extends State<_TravelCalendarDialog> {
  late DateTime _currentMonth;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialStart;
    _endDate = widget.initialEnd;
    _currentMonth = DateTime(
      (_startDate ?? DateTime.now()).year,
      (_startDate ?? DateTime.now()).month,
    );
  }

  void _onDaySelected(DateTime day) {
    setState(() {
      if (_startDate == null || _endDate != null) {
        _startDate = day;
        _endDate = null;
      } else if (day.isBefore(_startDate!)) {
        _startDate = day;
      } else {
        _endDate = day;
      }
    });
  }

  void _clearDates() => setState(() {
        _startDate = null;
        _endDate = null;
      });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width - 40,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                decoration: const BoxDecoration(
                  color: _kPrimary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: _kAccentYellow,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.flight, size: 18, color: _kTextDefault),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'ASGo Travel',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Select your travel dates',
                            style: TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 22, color: Colors.white),
                    ),
                  ],
                ),
              ),

              // Date display boxes
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    _buildDateBox('Start Date', _startDate),
                    const SizedBox(width: 10),
                    _buildDateBox('End Date', _endDate),
                  ],
                ),
              ),

              // Month navigation
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: _kTextSubdued),
                      onPressed: () => setState(() {
                        _currentMonth = DateTime(
                          _currentMonth.year,
                          _currentMonth.month - 1,
                        );
                      }),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, color: _kTextSubdued),
                      onPressed: () => setState(() {
                        _currentMonth = DateTime(
                          _currentMonth.year,
                          _currentMonth.month + 1,
                        );
                      }),
                    ),
                  ],
                ),
              ),

              // Calendar grid
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _MonthGrid(
                  month: _currentMonth,
                  startDate: _startDate,
                  endDate: _endDate,
                  onSelect: _onDaySelected,
                ),
              ),

              // Footer
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _clearDates,
                      child: const Text(
                        'Clear dates',
                        style: TextStyle(color: _kTextSubdued, fontSize: 13),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: (_startDate != null && _endDate != null)
                          ? () => Navigator.pop(
                                context,
                                (start: _startDate!, end: _endDate!),
                              )
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccentYellow,
                        foregroundColor: _kTextDefault,
                        disabledBackgroundColor: Colors.grey.shade200,
                        disabledForegroundColor: Colors.grey.shade400,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      child: const Text('Confirm Dates'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateBox(String label, DateTime? date) {
    final hasDate = date != null;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasDate ? _kPrimary : _kBorder,
            width: hasDate ? 2 : 1.5,
          ),
          color: hasDate ? _kRangeBg : Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: _kTextSubdued,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              hasDate ? DateFormat('MMM d, yyyy').format(date) : '—',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: _kTextDefault,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final DateTime? startDate, endDate;
  final ValueChanged<DateTime> onSelect;

  const _MonthGrid({
    required this.month,
    this.startDate,
    this.endDate,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7;
    final today = DateTime.now();
    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Column(
      children: [
        Text(
          DateFormat('MMMM yyyy').format(month),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 10),
        Row(
          children: weekdays
              .map((d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: const TextStyle(
                          fontSize: 10,
                          color: _kTextSubdued,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),
        ...List.generate(6, (week) {
          return Row(
            children: List.generate(7, (col) {
              final dayIndex = week * 7 + col - startWeekday + 1;
              if (dayIndex < 1 || dayIndex > daysInMonth) {
                return const Expanded(child: SizedBox(height: 38));
              }
              final day = DateTime(month.year, month.month, dayIndex);
              final isStart =
                  startDate != null && _sameDay(day, startDate!);
              final isEnd = endDate != null && _sameDay(day, endDate!);
              final selected = isStart || isEnd;
              final inRange = startDate != null &&
                  endDate != null &&
                  day.isAfter(startDate!) &&
                  day.isBefore(endDate!);
              final isToday = _sameDay(day, today);

              return Expanded(
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: inRange || isStart || isEnd ? _kRangeBg : null,
                    borderRadius: BorderRadius.horizontal(
                      left: isStart
                          ? const Radius.circular(20)
                          : Radius.zero,
                      right: isEnd
                          ? const Radius.circular(20)
                          : Radius.zero,
                    ),
                  ),
                  child: Center(
                    child: GestureDetector(
                      onTap: () => onSelect(day),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? _kPrimary : null,
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Text(
                              '$dayIndex',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: selected
                                    ? Colors.white
                                    : _kTextDefault,
                              ),
                            ),
                            if (isToday && !selected)
                              Positioned(
                                bottom: 2,
                                child: Container(
                                  width: 4,
                                  height: 4,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _kAccentYellow,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        }),
      ],
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
