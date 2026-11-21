import 'dart:async';

import 'package:flutter/material.dart';

enum NotifyType { success, error, info, warning }

/// Notifikasi modern (toast melayang di atas layar).
class Notify {
  static final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
  static OverlayEntry? _entry;

  static void success(String m) => show(m, NotifyType.success);
  static void error(String m) => show(m, NotifyType.error);
  static void info(String m) => show(m, NotifyType.info);
  static void warning(String m) => show(m, NotifyType.warning);

  static void show(String message, NotifyType type) {
    final overlay = navKey.currentState?.overlay;
    if (overlay == null) return;
    final old = _entry;
    _entry = null;
    old?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        message: message,
        type: type,
        onClose: () {
          if (identical(_entry, entry)) {
            _entry = null;
            entry.remove();
          }
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _ToastView extends StatefulWidget {
  final String message;
  final NotifyType type;
  final VoidCallback onClose;

  const _ToastView({required this.message, required this.type, required this.onClose});

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
    final ms = widget.type == NotifyType.error ? 3800 : 2600;
    _timer = Timer(Duration(milliseconds: ms), _close);
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    await _c.reverse();
    if (mounted) widget.onClose();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late IconData icon;
    switch (widget.type) {
      case NotifyType.success:
        bg = const Color(0xFF16A34A);
        icon = Icons.check_circle_rounded;
        break;
      case NotifyType.error:
        bg = const Color(0xFFDC2626);
        icon = Icons.error_rounded;
        break;
      case NotifyType.warning:
        bg = const Color(0xFFD97706);
        icon = Icons.warning_amber_rounded;
        break;
      case NotifyType.info:
        bg = const Color(0xFF2563EB);
        icon = Icons.info_rounded;
        break;
    }
    final top = MediaQuery.of(context).padding.top + 10;
    return Positioned(
      top: top,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1.4), end: Offset.zero)
            .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
        child: FadeTransition(
          opacity: _c,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: _close,
                  onVerticalDragEnd: (_) => _close(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: Color(0x33FFFFFF), shape: BoxShape.circle),
                          child: Icon(icon, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.message,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
