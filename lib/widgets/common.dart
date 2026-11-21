
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/format.dart';

/// Dispose controller setelah animasi dialog selesai (hindari error "used after disposed")
void disposeLater(TextEditingController c) {
  Future.delayed(const Duration(milliseconds: 600), c.dispose);
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String okText = 'Ya',
  bool danger = false,
  IconData? icon,
}) async {
  final cs = Theme.of(context).colorScheme;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(icon ?? (danger ? Icons.warning_amber_rounded : Icons.help_outline_rounded),
          color: danger ? cs.error : cs.primary, size: 36),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(okText),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> inputDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String? label,
  TextInputType keyboard = TextInputType.text,
  List<TextInputFormatter>? formatters,
  int maxLines = 1,
  bool obscure = false,
}) async {
  final c = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: keyboard,
        inputFormatters: formatters,
        maxLines: obscure ? 1 : maxLines,
        obscureText: obscure,
        decoration: InputDecoration(hintText: hint, labelText: label, border: const OutlineInputBorder()),
        onSubmitted: maxLines == 1 ? (v) => Navigator.pop(ctx, v) : null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Simpan')),
      ],
    ),
  );
  disposeLater(c);
  return r;
}

InputDecoration inputDeco(String label, {IconData? icon, String? hint, String? prefix, String? suffix}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
      suffixText: suffix,
      prefixIcon: icon == null ? null : Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      isDense: true,
    );

/// Gambar menu, atau placeholder berwarna dengan inisial.
class MenuThumb extends StatelessWidget {
  final Uint8List? image;
  final String name;
  final double radius;
  final int cacheWidth;

  const MenuThumb({super.key, required this.image, required this.name, this.radius = 12, this.cacheWidth = 320});

  static const _palette = [
    Color(0xFFEF6C00),
    Color(0xFF00897B),
    Color(0xFF5E35B1),
    Color(0xFFD81B60),
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFF6D4C41),
    Color(0xFFF4511E),
  ];

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Widget _placeholder() {
    final c = _palette[name.hashCode.abs() % _palette.length];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c, Color.lerp(c, Colors.black, 0.25)!],
        ),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(_initials,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 28, letterSpacing: 1)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final img = image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.expand(
        child: img == null
            ? _placeholder()
            : Image.memory(
                img,
                fit: BoxFit.cover,
                cacheWidth: cacheWidth,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _placeholder(),
              ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: cs.primaryContainer.withOpacity(0.5), shape: BoxShape.circle),
              child: Icon(icon, size: 44, color: cs.primary),
            ),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: TextStyle(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? sub;

  const StatCard({super.key, required this.title, required this.value, required this.icon, required this.color, this.sub});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.15), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                if (sub != null)
                  Text(sub!, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Theme.of(context).colorScheme.primary, letterSpacing: 0.4)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Kartu bergaya modern
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const SoftCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Pilihan periode tanggal yang sering dipakai
class PeriodPicker extends StatelessWidget {
  final DateTime from;
  final DateTime to;
  final void Function(DateTime from, DateTime to) onChanged;

  const PeriodPicker({super.key, required this.from, required this.to, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = dayStart(now);
    final presets = <String, List<DateTime>>{
      'Hari ini': [today, today],
      'Kemarin': [today.subtract(const Duration(days: 1)), today.subtract(const Duration(days: 1))],
      '7 Hari': [today.subtract(const Duration(days: 6)), today],
      'Bulan ini': [DateTime(now.year, now.month, 1), today],
      'Bulan lalu': [DateTime(now.year, now.month - 1, 1), DateTime(now.year, now.month, 0)],
    };
    bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    String? active;
    presets.forEach((k, v) {
      if (sameDay(v[0], from) && sameDay(v[1], to)) active ??= k;
    });
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final e in presets.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(e.key),
                selected: active == e.key,
                onSelected: (_) => onChanged(e.value[0], e.value[1]),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.date_range_rounded, size: 18),
            label: Text(active == null
                ? (sameDay(from, to) ? fmtDate(from) : '${fmtDateShort(from)} - ${fmtDateShort(to)}')
                : 'Pilih Tanggal'),
            onPressed: () async {
              final r = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(now.year + 1, 12, 31),
                initialDateRange: DateTimeRange(start: from, end: to),
              );
              if (r != null) onChanged(dayStart(r.start), dayStart(r.end));
            },
          ),
        ],
      ),
    );
  }
}

/// Avatar barang (inisial berwarna)
class ProductAvatar extends StatelessWidget {
  final String name;
  final double size;
  const ProductAvatar(this.name, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: MenuThumb(image: null, name: name, radius: size * 0.28));
}

/// Label kecil berwarna
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 3)],
          Text(text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Warna status stok
Color stockColor(BuildContext context, double stock, double min) {
  if (stock <= 0) return Colors.red.shade600;
  if (min > 0 && stock <= min) return Colors.orange.shade700;
  return Colors.green.shade600;
}

/// Bungkus konten agar tidak terlalu lebar di tablet
class MaxWidth extends StatelessWidget {
  final double width;
  final Widget child;
  const MaxWidth({super.key, this.width = 720, required this.child});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width), child: child),
      );
}

/// Dialog isian angka (jumlah)
Future<double?> qtyDialog(BuildContext context, {required String title, double initial = 1, String unit = ''}) async {
  final c = TextEditingController(text: qtyText(initial));
  c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
  final r = await showDialog<double>(
    context: context,
    builder: (ctx) {
      void done() => Navigator.pop(ctx, parseQty(c.text));
      return AlertDialog(
        title: Text(title),
        content: Row(children: [
          IconButton.filledTonal(
            onPressed: () {
              final v = parseQty(c.text) - 1;
              c.text = qtyText(v < 0 ? 0 : v);
            },
            icon: const Icon(Icons.remove_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: c,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: qtyFormatters,
              decoration: InputDecoration(suffixText: unit, border: const OutlineInputBorder()),
              onSubmitted: (_) => done(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: () => c.text = qtyText(parseQty(c.text) + 1),
            icon: const Icon(Icons.add_rounded),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: done, child: const Text('OK')),
        ],
      );
    },
  );
  disposeLater(c);
  return r;
}

/// Kolom isian Rupiah
class MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final IconData? icon;
  final bool enabled;
  const MoneyField(
      {super.key,
      required this.controller,
      required this.label,
      this.autofocus = false,
      this.onChanged,
      this.onSubmitted,
      this.icon,
      this.enabled = true});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        enabled: enabled,
        autofocus: autofocus,
        keyboardType: TextInputType.number,
        inputFormatters: [RupiahFormatter()],
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        decoration: inputDeco(label, icon: icon, prefix: 'Rp '),
      );
}

/// Grafik batang sederhana (tanpa paket tambahan)
class MiniBarChart extends StatelessWidget {
  final List<String> labels;
  final List<int> values;
  final double height;
  const MiniBarChart({super.key, required this.labels, required this.values, this.height = 160});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxV = values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b);
    final n = values.length;
    final step = n <= 10 ? 1 : (n / 8).ceil();
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < n; i++)
            Expanded(
              child: Tooltip(
                message: '${labels[i]}\n${rp(values[i])}',
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: n > 20 ? 1 : 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: FractionallySizedBox(
                          heightFactor: maxV == 0 ? 0.02 : (values[i] / maxV).clamp(0.02, 1.0).toDouble(),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [cs.primary, Color.lerp(cs.primary, cs.tertiary, 0.6)!],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 14,
                        child: (i % step == 0)
                            ? FittedBox(child: Text(labels[i], style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)))
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
