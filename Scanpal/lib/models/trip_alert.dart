import 'package:flutter/material.dart';
import 'trip.dart';

enum AlertType {
  preTravelReminder,
  postTravelReminder,
}

enum AlertUrgency {
  info,    // 10+ days
  warning, // 3-5 days
  urgent,  // 1-2 days
}

class TripAlert {
  final AlertType type;
  final Trip trip;
  final String message;
  final AlertUrgency urgency;
  final int daysRemaining;

  const TripAlert({
    required this.type,
    required this.trip,
    required this.message,
    required this.urgency,
    required this.daysRemaining,
  });

  IconData get icon {
    switch (urgency) {
      case AlertUrgency.urgent:
        return Icons.error_outline;
      case AlertUrgency.warning:
        return Icons.warning_amber_rounded;
      case AlertUrgency.info:
        return Icons.info_outline;
    }
  }

  Color get color {
    switch (urgency) {
      case AlertUrgency.urgent:
        return const Color(0xFFEF4444);
      case AlertUrgency.warning:
        return const Color(0xFFF59E0B);
      case AlertUrgency.info:
        return const Color(0xFF6366F1);
    }
  }
}
