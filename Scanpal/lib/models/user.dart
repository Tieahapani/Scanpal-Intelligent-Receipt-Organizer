class AppUser {
  final String id;
  final String email;
  final String name;
  final String? department;
  final String role; // "traveler" or "admin"

  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    this.department,
    required this.role,
  });

  bool get isAdmin => role == "admin";
  bool get isTraveler => role == "traveler";

  factory AppUser.fromMap(Map<String, dynamic> m) {
    return AppUser(
      id: m['id']?.toString() ?? '',
      email: m['email']?.toString() ?? '',
      name: m['name']?.toString() ?? '',
      department: m['department']?.toString(),
      role: m['role']?.toString() ?? 'traveler',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'email': email,
        'name': name,
        'department': department,
        'role': role,
      };
}
