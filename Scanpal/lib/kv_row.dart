import 'package:flutter/material.dart';

class KVRow extends StatelessWidget {
  final String label;
  final String value;
  const KVRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final valueStyle = style?.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}
