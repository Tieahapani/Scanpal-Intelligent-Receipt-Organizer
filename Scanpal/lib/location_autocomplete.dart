import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// A destination text field with autocomplete suggestions from Photon (OpenStreetMap).
/// Free, no API key required.
class LocationAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSelected;

  const LocationAutocomplete({
    super.key,
    required this.controller,
    this.hint = 'e.g. Los Angeles, CA',
    this.onSelected,
  });

  @override
  State<LocationAutocomplete> createState() => _LocationAutocompleteState();
}

class _LocationAutocompleteState extends State<LocationAutocomplete> {
  List<_Place> _suggestions = [];
  Timer? _debounce;
  bool _justSelected = false;
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _removeOverlay();
      });
    }
  }

  void _onChanged(String query) {
    if (_justSelected) {
      _justSelected = false;
      return;
    }
    _debounce?.cancel();
    if (query.trim().length < 2) {
      _removeOverlay();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query.trim()));
  }

  Future<void> _search(String query) async {
    try {
      final uri = Uri.parse(
        'https://photon.komoot.io/api/?q=${Uri.encodeComponent(query)}&limit=5&lang=en',
      );
      final res = await http.get(uri, headers: {
        'User-Agent': 'Finpal/1.0',
      }).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200 || !mounted) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final features = data['features'] as List? ?? [];

      final places = <_Place>[];
      final seen = <String>{};
      for (final f in features) {
        final props = f['properties'] as Map<String, dynamic>? ?? {};
        final place = _Place.fromPhoton(props);
        if (place.display.isNotEmpty && seen.add(place.display)) {
          places.add(place);
        }
      }

      if (mounted) {
        _suggestions = places;
        if (places.isNotEmpty) {
          _showOverlay();
        } else {
          _removeOverlay();
        }
      }
    } catch (e) {
      debugPrint('Location search error: $e');
    }
  }

  void _onSelect(_Place place) {
    _justSelected = true;
    widget.controller.text = place.display;
    widget.controller.selection = TextSelection.collapsed(offset: place.display.length);
    widget.onSelected?.call(place.display);
    _removeOverlay();
  }

  double _getFieldWidth() {
    final box = context.findRenderObject() as RenderBox?;
    return box?.size.width ?? 300;
  }

  void _showOverlay() {
    _removeOverlay();
    final width = _getFieldWidth();
    _overlayEntry = OverlayEntry(builder: (_) {
      return Positioned(
        width: width,
        child: CompositedTransformFollower(
          link: _layerLink,
          offset: const Offset(0, 52),
          showWhenUnlinked: false,
          child: Material(
            elevation: 0,
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                itemBuilder: (_, i) {
                  final place = _suggestions[i];
                  return InkWell(
                    onTap: () => _onSelect(place),
                    borderRadius: BorderRadius.circular(i == 0 ? 12 : (i == _suggestions.length - 1 ? 12 : 0)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Icon(Icons.location_on_outlined, size: 18, color: Colors.grey.shade400),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  place.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
                                if (place.subtitle.isNotEmpty)
                                  Text(
                                    place.subtitle,
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
          ),
        ),
      );
    });
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          style: const TextStyle(fontSize: 15, color: Color(0xFF1F2937)),
          decoration: InputDecoration(
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            hintText: widget.hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
            isDense: true,
            suffixIcon: Icon(Icons.search, size: 18, color: Colors.grey.shade400),
          ),
          onChanged: _onChanged,
        ),
      ),
    );
  }
}

class _Place {
  final String name;
  final String subtitle;
  final String display;

  _Place({required this.name, required this.subtitle, required this.display});

  factory _Place.fromPhoton(Map<String, dynamic> props) {
    final name = props['name'] ?? '';
    final city = props['city'] ?? '';
    final state = props['state'] ?? '';
    final country = props['country'] ?? '';

    // Subtitle: city, state, country (excluding name duplicates)
    final subtitleParts = <String>[];
    if (city.isNotEmpty && city != name) subtitleParts.add(city);
    if (state.isNotEmpty && state != name && state != city) subtitleParts.add(state);
    if (country.isNotEmpty) subtitleParts.add(country);
    final subtitle = subtitleParts.join(', ');

    // Full display for the text field
    final displayParts = <String>[];
    if (name.isNotEmpty) displayParts.add(name);
    if (state.isNotEmpty && state != name) displayParts.add(state);
    if (country.isNotEmpty) displayParts.add(country);
    final display = displayParts.join(', ');

    return _Place(name: name, subtitle: subtitle, display: display);
  }
}
