import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'api.dart';
import 'auth_service.dart';
import 'models/user.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _api = APIService();
  String? _userName;
  String? _email;
  String? _department;
  String? _role;
  bool _hasProfileImage = false;
  int _imageVersion = 0; // bump to force reload

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await AuthService.instance.getUser();
    if (user != null && mounted) {
      setState(() {
        _userName = user.name;
        _email = user.email;
        _department = user.department;
        _role = user.isAdmin ? 'Admin' : 'Traveler';
        _hasProfileImage = user.profileImage != null && user.profileImage!.isNotEmpty;
      });
    }
  }

  Future<void> _updateUserProfileImage(String? filename) async {
    final user = await AuthService.instance.getUser();
    if (user == null) return;
    final updated = AppUser(
      id: user.id,
      email: user.email,
      name: user.name,
      department: user.department,
      role: user.role,
      profileImage: filename,
    );
    await AuthService.instance.updateUser(updated);
  }

  Future<void> _changeProfilePicture() async {
    ImageSource? source;
    bool removeRequested = false;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Change Profile Photo',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF46166B).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_outlined, color: Color(0xFF46166B), size: 20),
                ),
                title: const Text('Take Photo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                onTap: () {
                  source = ImageSource.camera;
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8A824).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library_outlined, color: Color(0xFFE8A824), size: 20),
                ),
                title: const Text('Choose from Gallery', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                onTap: () {
                  source = ImageSource.gallery;
                  Navigator.pop(ctx);
                },
              ),
              if (_hasProfileImage)
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  ),
                  title: const Text('Remove Photo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.red)),
                  onTap: () {
                    removeRequested = true;
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;

    if (removeRequested) {
      try {
        await _api.deleteProfileImage();
        await _updateUserProfileImage(null);
        if (mounted) {
          setState(() {
            _hasProfileImage = false;
            _imageVersion++;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to remove photo: $e'), backgroundColor: Colors.red),
          );
        }
      }
      return;
    }

    if (source != null) {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source!, maxWidth: 512, maxHeight: 512, imageQuality: 80);
      if (picked != null && mounted) {
        try {
          final filename = await _api.uploadProfileImage(File(picked.path));
          await _updateUserProfileImage(filename);
          if (mounted) {
            setState(() {
              _hasProfileImage = true;
              _imageVersion++;
            });
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to upload photo: $e'), backgroundColor: Colors.red),
            );
          }
        }
      }
    }
  }

  String get _initials {
    if (_userName == null || _userName!.isEmpty) return '?';
    final parts = _userName!.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  Widget _buildProfileAvatar({double radius = 45}) {
    if (_hasProfileImage) {
      return FutureBuilder<String?>(
        future: AuthService.instance.getToken(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return _initialsAvatar(radius);
          }
          return CircleAvatar(
            radius: radius,
            backgroundColor: const Color(0xFFE8A824),
            backgroundImage: CachedNetworkImageProvider(
              '${_api.profileImageUrl()}?v=$_imageVersion',
              headers: {'Authorization': 'Bearer ${snap.data}'},
            ),
          );
        },
      );
    }
    return _initialsAvatar(radius);
  }

  Widget _initialsAvatar(double radius) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE8A824),
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: radius * 0.6,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: CustomScrollView(
        slivers: [
          // Purple header
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF46166B), Color(0xFF5C2D91)],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    // Top bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Expanded(
                            child: Text(
                              'My Profile',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 40),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Profile picture
                    GestureDetector(
                      onTap: _changeProfilePicture,
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: _buildProfileAvatar(radius: 45),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8A824),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _userName ?? '',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        _role ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),

          // Info cards
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _sectionLabel('PERSONAL INFORMATION'),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _infoRow(Icons.person_outline, 'Full Name', _userName ?? '-'),
                      _divider(),
                      _infoRow(Icons.email_outlined, 'Email', _email ?? '-'),
                      _divider(),
                      _infoRow(Icons.business_outlined, 'Department', _department ?? '-'),
                      _divider(),
                      _infoRow(Icons.shield_outlined, 'Role', _role ?? '-'),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade500,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF46166B).withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF46166B), size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.only(left: 66),
      child: Divider(height: 1, color: Colors.grey.shade100),
    );
  }
}
