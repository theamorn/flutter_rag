import 'package:flutter/material.dart';

/// Submits only on the keyboard action or the icon, never per keystroke.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.onSubmit,
    this.onClear,
    this.hint = 'Search transactions',
    this.icon = Icons.search,
  });

  final ValueChanged<String> onSubmit;
  final VoidCallback? onClear;
  final String hint;
  final IconData icon;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Material(
        color: scheme.surface,
        elevation: 2,
        shadowColor: scheme.primary.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
        child: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          onSubmitted: widget.onSubmit,
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: IconButton(
              color: scheme.primary,
              icon: Icon(widget.icon),
              onPressed: () => widget.onSubmit(_controller.text),
            ),
            suffixIcon: widget.onClear == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear',
                    onPressed: () {
                      _controller.clear();
                      widget.onClear!();
                    },
                  ),
            filled: true,
            fillColor: scheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: scheme.primary.withValues(alpha: 0.18),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: scheme.primary, width: 1.5),
            ),
            isDense: true,
          ),
        ),
      ),
    );
  }
}
