import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Two panes stacked vertically with a draggable divider between them.
///
/// The top pane hugs its content, so a short list is never sliced by the
/// divider. As soon as the user drags the handle, the chosen height wins and the
/// pane scrolls when its content does not fit.
class VerticalSplitView extends StatefulWidget {
  const VerticalSplitView({
    super.key,
    required this.top,
    required this.bottom,
    required this.fraction,
    required this.onChanged,
    this.onReset,
    this.minTop = 120,
    this.minBottom = 160,
  });

  final Widget top;
  final Widget bottom;

  /// Height the user gave to [top] as a share of the column, or null while the
  /// divider has not been dragged and the pane should fit its content.
  final double? fraction;
  final ValueChanged<double> onChanged;

  /// Called on a double click to drop the stored height and fit the content.
  final VoidCallback? onReset;
  final double minTop;
  final double minBottom;

  @override
  State<VerticalSplitView> createState() => _VerticalSplitViewState();
}

class _VerticalSplitViewState extends State<VerticalSplitView> {
  /// The strip between the panes. Most of it is transparent padding: the
  /// visible line is 1 px, but the whole strip is easy to grab.
  static const double _handleThickness = 16;

  bool _hovering = false;

  final GlobalKey _topKey = GlobalKey();

  /// Height of the top pane when the current drag started.
  double? _dragBase;

  /// Total distance dragged so far. Pointer moves arrive in many small
  /// increments, so they have to accumulate instead of replacing each other.
  double _dragDelta = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final usable = constraints.maxHeight.isFinite
            ? constraints.maxHeight - _handleThickness
            // A bounded fallback keeps the pane usable inside a scroll view
            // that offers unbounded height.
            : 560.0;
        final minTop = widget.minTop.clamp(0.0, usable);
        final room = (usable - widget.minBottom.clamp(0.0, usable - minTop))
            .clamp(minTop, usable);
        final dragged = widget.fraction;
        // Nothing chosen yet: the pane may take everything the inspector can
        // spare. After a drag the user's share becomes the limit.
        final maxTop = dragged == null
            ? room
            : (usable * dragged.clamp(0.0, 1.0)).clamp(minTop, room);

        return Column(
          children: <Widget>[
            // Sized to its content and clipped, so neither scrolled rows nor
            // ripple effects can paint across the divider. The cap has to
            // wrap the intrinsic measurement, not the other way round.
            ConstrainedBox(
              key: _topKey,
              constraints: BoxConstraints(maxHeight: maxTop),
              child: IntrinsicHeight(
                // The Material has to live inside the clip: ink highlights and
                // splashes are painted on the closest Material, and the one from
                // the Scaffold sits above the panes, which let a fading
                // highlight bleed over the inspector.
                child: Material(
                  type: MaterialType.transparency,
                  child: ClipRect(child: widget.top),
                ),
              ),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.resizeRow,
              onEnter: (_) => setState(() => _hovering = true),
              onExit: (_) => setState(() => _hovering = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: widget.onReset,
                onVerticalDragStart: (_) {
                  final box = _topKey.currentContext?.size;
                  _dragBase = box?.height;
                  _dragDelta = 0;
                },
                onVerticalDragUpdate: usable <= 0
                    ? null
                    : (details) {
                        _dragDelta += details.delta.dy;
                        widget.onChanged(
                          (((_dragBase ?? maxTop) + _dragDelta) / usable)
                              .clamp(0.0, 1.0),
                        );
                      },
                // The grip in the middle of the line tells where the divider
                // can be taken; without it the strip is easy to miss.
                child: Tooltip(
                  message: context.tr(
                      'Drag to resize. Double click to fit the content.'),
                  child: Container(
                    height: _handleThickness,
                    alignment: Alignment.center,
                    color: _hovering
                        ? theme.colorScheme.primary.withValues(alpha: 0.10)
                        : null,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        Container(
                          height: 1,
                          color: theme.dividerColor,
                        ),
                        AnimatedOpacity(
                          opacity: _hovering ? 1 : 0.55,
                          duration: const Duration(milliseconds: 120),
                          child: Container(
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(
                              color: _hovering
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                child: ClipRect(child: widget.bottom),
              ),
            ),
          ],
        );
      },
    );
  }
}