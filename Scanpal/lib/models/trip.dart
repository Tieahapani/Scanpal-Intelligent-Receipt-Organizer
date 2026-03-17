class Trip {
  final String id;
  final String? notionPageId;
  final String travelerEmail;
  final String travelerName;
  final String? department;
  final String? tripPurpose;
  final String? destination;
  final DateTime? departureDate;
  final DateTime? returnDate;
  final String? status;
  final double accommodationCost;
  final double flightCost;
  final double groundTransportation;
  final double registrationCost;
  final double meals;
  final double otherAsCost;
  final double totalExpenses;
  final double advance;
  final double claim;
  final String? coverImageUrl;
  final double budget;
  final String? travelType;
  final String? category;
  final String? description;
  final String? travelers;

  const Trip({
    required this.id,
    this.notionPageId,
    required this.travelerEmail,
    required this.travelerName,
    this.department,
    this.tripPurpose,
    this.destination,
    this.departureDate,
    this.returnDate,
    this.status,
    this.accommodationCost = 0.0,
    this.flightCost = 0.0,
    this.groundTransportation = 0.0,
    this.registrationCost = 0.0,
    this.meals = 0.0,
    this.otherAsCost = 0.0,
    this.totalExpenses = 0.0,
    this.advance = 0.0,
    this.claim = 0.0,
    this.coverImageUrl,
    this.budget = 0.0,
    this.travelType,
    this.category,
    this.description,
    this.travelers,
  });

  bool get isActive {
    if (departureDate == null || returnDate == null) return false;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final depDay = DateTime(departureDate!.year, departureDate!.month, departureDate!.day);
    final retDay = DateTime(returnDate!.year, returnDate!.month, returnDate!.day);
    // Active: today >= departure AND today <= return
    return !todayStart.isBefore(depDay) && !todayStart.isAfter(retDay);
  }

  bool get isUpcoming {
    if (departureDate == null) return false;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final depDay = DateTime(departureDate!.year, departureDate!.month, departureDate!.day);
    // Upcoming: today < departure
    return todayStart.isBefore(depDay);
  }

  bool get isPast {
    // Use return date if available, otherwise departure date
    final endDate = returnDate ?? departureDate;
    if (endDate == null) return false;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final endDay = DateTime(endDate.year, endDate.month, endDate.day);
    // Past: today > end date
    return todayStart.isAfter(endDay);
  }

  /// No dates set at all
  bool get isUnscheduled => departureDate == null && returnDate == null;

  String get displayTitle => tripPurpose ?? destination ?? 'Trip';
  String get displayDestination => destination ?? '';

  factory Trip.fromMap(Map<String, dynamic> m) {
    return Trip(
      id: m['id']?.toString() ?? '',
      notionPageId: m['notion_page_id']?.toString() ?? '',
      travelerEmail: m['traveler_email']?.toString() ?? '',
      travelerName: m['traveler_name']?.toString() ?? '',
      department: m['department']?.toString(),
      tripPurpose: m['trip_purpose']?.toString(),
      destination: m['destination']?.toString(),
      departureDate: _parseDate(m['departure_date']),
      returnDate: _parseDate(m['return_date']),
      status: m['status']?.toString(),
      accommodationCost: _toDouble(m['accommodation_cost']),
      flightCost: _toDouble(m['flight_cost']),
      groundTransportation: _toDouble(m['ground_transportation']),
      registrationCost: _toDouble(m['registration_cost']),
      meals: _toDouble(m['meals']),
      otherAsCost: _toDouble(m['other_as_cost']),
      totalExpenses: _toDouble(m['total_expenses']),
      advance: _toDouble(m['advance']),
      claim: _toDouble(m['claim']),
      coverImageUrl: m['cover_image_url']?.toString(),
      budget: _toDouble(m['budget']),
      travelType: m['travel_type']?.toString(),
      category: m['category']?.toString(),
      description: m['description']?.toString(),
      travelers: m['travelers']?.toString(),
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'notion_page_id': notionPageId,
        'traveler_email': travelerEmail,
        'traveler_name': travelerName,
        'department': department,
        'trip_purpose': tripPurpose,
        'destination': destination,
        'departure_date': departureDate?.toIso8601String(),
        'return_date': returnDate?.toIso8601String(),
        'status': status,
        'accommodation_cost': accommodationCost,
        'flight_cost': flightCost,
        'ground_transportation': groundTransportation,
        'registration_cost': registrationCost,
        'meals': meals,
        'other_as_cost': otherAsCost,
        'total_expenses': totalExpenses,
        'advance': advance,
        'claim': claim,
        'cover_image_url': coverImageUrl,
        'budget': budget,
        'travel_type': travelType,
        'category': category,
        'description': description,
        'travelers': travelers,
      };
}
