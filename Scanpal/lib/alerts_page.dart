import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/trip.dart';
import 'models/trip_alert.dart';
import 'receipt.dart';
import 'trip_detail_page.dart';

class AlertsPage extends StatelessWidget {
  final List<Trip> trips;
  final List<Receipt> receipts;
  final String userName;
  final VoidCallback onTripTap;

  const AlertsPage({
    super.key,
    required this.trips,
    required this.receipts,
    required this.userName,
    required this.onTripTap,
  });

  String get _firstName => userName.split(' ').first;

  List<TripAlert> _generateAlerts() {
    final alerts = <TripAlert>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final trip in trips) {
      final tripReceipts = receipts.where((r) => r.tripId == trip.id).toList();
      final dest = trip.destination ?? trip.tripPurpose ?? 'your trip';
      final depDate = trip.departureDate;
      final retDate = trip.returnDate;

      // ── PRE-TRAVEL ALERT ──
      // 10 days before departure, if no receipts submitted
      if (depDate != null) {
        final depDay = DateTime(depDate.year, depDate.month, depDate.day);
        final daysUntilTravel = depDay.difference(today).inDays;

        if (daysUntilTravel >= 0 && daysUntilTravel <= 10 && tripReceipts.isEmpty) {
          final urgency = daysUntilTravel <= 2
              ? AlertUrgency.urgent
              : daysUntilTravel <= 5
                  ? AlertUrgency.warning
                  : AlertUrgency.info;

          final message = _preTravelMessage(dest, depDate, daysUntilTravel);

          alerts.add(TripAlert(
            type: AlertType.preTravelReminder,
            trip: trip,
            message: message,
            urgency: urgency,
            daysRemaining: daysUntilTravel,
          ));
        }
      }

      // ── POST-TRAVEL ALERT ──
      // After travel ends, within 15 days, remind to submit receipts for TC
      if (retDate != null) {
        final retDay = DateTime(retDate.year, retDate.month, retDate.day);
        final daysSinceReturn = today.difference(retDay).inDays;

        if (daysSinceReturn > 0 && daysSinceReturn <= 15) {
          final daysLeft = 15 - daysSinceReturn;
          final urgency = daysLeft <= 2
              ? AlertUrgency.urgent
              : daysLeft <= 5
                  ? AlertUrgency.warning
                  : AlertUrgency.info;

          final message = _postTravelMessage(dest, daysLeft, daysSinceReturn);

          alerts.add(TripAlert(
            type: AlertType.postTravelReminder,
            trip: trip,
            message: message,
            urgency: urgency,
            daysRemaining: daysLeft,
          ));
        }
      }
    }

    // Sort: urgent first, then warning, then info
    alerts.sort((a, b) => a.urgency.index.compareTo(b.urgency.index));

    return alerts;
  }

  String _preTravelMessage(String dest, DateTime depDate, int daysUntil) {
    final dateStr = DateFormat('MMMM d').format(depDate);

    if (daysUntil == 0) {
      return "Hey $_firstName, your trip to $dest starts today! Please submit your receipts now so your TAAR can be processed without any delays.";
    } else if (daysUntil == 1) {
      return "$_firstName, your $dest trip starts tomorrow! Please submit your receipts today to keep your TAAR on track.";
    } else if (daysUntil <= 3) {
      return "Just a heads up, $_firstName — your $dest trip is only $daysUntil days away and we haven't received any receipts yet. Submit them soon so your TAAR doesn't get delayed.";
    } else if (daysUntil <= 5) {
      return "Hi $_firstName, your trip to $dest is coming up on $dateStr. Now would be a great time to start submitting your receipts so we can get your TAAR processed before you head out.";
    } else {
      return "Hi $_firstName, your trip to $dest kicks off on $dateStr. It's a good time to start submitting your receipts so your TAAR can be processed in time.";
    }
  }

  String _postTravelMessage(String dest, int daysLeft, int daysSince) {
    if (daysLeft <= 1) {
      return "Last call, $_firstName — tomorrow is the deadline to submit your $dest receipts for TC processing. Don't miss out on your reimbursement.";
    } else if (daysLeft <= 3) {
      return "$_firstName, the deadline to submit receipts from your $dest trip is coming up in $daysLeft days. Send them over so your reimbursement isn't held up.";
    } else if (daysLeft <= 5) {
      return "Friendly reminder, $_firstName — you have $daysLeft days left to submit any remaining receipts from your $dest trip so we can process your TC and get your reimbursement started.";
    } else if (daysSince <= 3) {
      return "Welcome back from $dest, $_firstName! You have $daysLeft days to submit any remaining receipts so we can process your TC and get your reimbursement moving.";
    } else {
      return "Hi $_firstName, just a reminder that you have $daysLeft days left to submit your receipts from $dest. Get them in soon so your TC can be processed and reimbursement can begin.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final alerts = _generateAlerts();

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Column(
        children: [
          // Header
          Container(
            color: Colors.white,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.arrow_back_ios, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Alerts',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: alerts.isEmpty
                            ? const Color(0xFF10B981).withOpacity(0.1)
                            : const Color(0xFFEF4444).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${alerts.length}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: alerts.isEmpty
                              ? const Color(0xFF059669)
                              : const Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Body
          Expanded(
            child: alerts.isEmpty
                ? _buildEmptyState()
                : _buildAlertsList(context, alerts),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.check_circle_outline,
              size: 36,
              color: Color(0xFF10B981),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'All clear!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'No alerts at the moment',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsList(BuildContext context, List<TripAlert> alerts) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
      itemCount: alerts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _buildAlertCard(context, alerts[i]),
    );
  }

  Widget _buildAlertCard(BuildContext context, TripAlert alert) {
    final dest = alert.trip.destination ?? alert.trip.tripPurpose ?? 'Trip';
    final typeLabel = alert.type == AlertType.preTravelReminder
        ? 'TAAR Reminder'
        : 'TC Reminder';

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TripDetailPage(trip: alert.trip),
          ),
        );
        onTripTap();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border(
            left: BorderSide(color: alert.color, width: 4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: icon + trip name + urgency label
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: alert.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(alert.icon, size: 18, color: alert.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dest,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        typeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: alert.color,
                        ),
                      ),
                    ],
                  ),
                ),
                // Days badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: alert.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    alert.daysRemaining == 0
                        ? 'Today'
                        : alert.daysRemaining == 1
                            ? '1 day'
                            : '${alert.daysRemaining} days',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: alert.color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Natural language message
            Text(
              alert.message,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
