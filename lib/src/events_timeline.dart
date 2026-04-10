import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller/events_controller.dart';
import 'events/event.dart';

/// A "lane" (row) on the gantt-style [EventsTimeline].
///
/// Each lane corresponds to a person, room, resource, project, etc.
/// Events are matched to a lane via [Event.eventType] == [TimelineLane.id].
/// The lane is otherwise opaque — render it however you like via
/// [EventsTimeline.laneLabelBuilder] using its index in the original lanes
/// list.
class TimelineLane {
  const TimelineLane({required this.id});

  /// Unique identifier — must equal the events' `eventType` to be matched.
  final Object id;

  /// Display label. Falls back to `id.toString()`.
  final String? title;

  /// Optional accent color for the lane label / row tint.
  final Color? color;

  /// Arbitrary user payload.
  final Object? data;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'color': color != null
          ? "#${color!.value.toRadixString(16).padLeft(8, '0')}"
          : null,
      'data': data,
    };
  }
}

/// Pinch-to-zoom configuration for [EventsTimeline].
///
/// Mirrors [PinchToZoomParameters] from [EventsPlanner] but with field names
/// appropriate for the horizontal (pixels-per-minute) zoom axis.
class TimelinePinchToZoomParameters {
  const TimelinePinchToZoomParameters({
    this.pinchToZoom = true,
    this.pinchToZoomSpeed = 1,
    this.pinchToZoomMinPixelsPerMinute = 0.05,
    this.pinchToZoomMaxPixelsPerMinute = 8.0,
    this.onZoomChange,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
  });

  /// Whether pinch-to-zoom is enabled.
  final bool pinchToZoom;

  /// Multiplier for zoom speed (1.0 = normal, >1 = faster).
  final double pinchToZoomSpeed;

  /// Minimum allowed pixelsPerMinute during zoom.
  final double pinchToZoomMinPixelsPerMinute;

  /// Maximum allowed pixelsPerMinute during zoom.
  final double pinchToZoomMaxPixelsPerMinute;

  /// Called when a zoom gesture finishes, with the new pixelsPerMinute.
  final void Function(double pixelsPerMinute)? onZoomChange;

  /// Optional override for the scale-start gesture handler.
  final void Function(ScaleStartDetails details)? onScaleStart;

  /// Optional override for the scale-update gesture handler.
  final void Function(ScaleUpdateDetails details)? onScaleUpdate;

  /// Optional override for the scale-end gesture handler.
  final void Function(ScaleEndDetails details)? onScaleEnd;
}

/// Current-hour vertical indicator configuration for [EventsTimeline].
class TimelineCurrentHourIndicatorParam {
  const TimelineCurrentHourIndicatorParam({
    this.visible = true,
    this.color = Colors.red,
    this.strokeWidth = 1.0,
    this.circleRadius = 4.0,
    this.showCircle = true,
  });

  /// Whether the indicator line is shown.
  final bool visible;

  /// Color of the vertical line and circle.
  final Color color;

  /// Stroke width of the vertical line.
  final double strokeWidth;

  /// Radius of the circle drawn at the top of the line.
  final double circleRadius;

  /// Whether to draw a circle at the top of the line.
  final bool showCircle;
}

/// Gantt-style timeline view: time on the X axis (infinitely scrollable),
/// one [TimelineLane] per row on the Y axis.
///
/// - Pinch / horizontal scale to zoom the time axis (`pixelsPerMinute`).
/// - Overlapping events on the same lane stack vertically into sub-rows;
///   the lane row auto-grows to fit them.
/// - Header (time/date) and left lane labels stay sticky while the body
///   scrolls in both axes.
class EventsTimeline extends StatefulWidget {
  const EventsTimeline({
    super.key,
    required this.controller,
    required this.lanes,
    this.initialDate,
    this.maxPreviousDays = 30,
    this.maxNextDays = 365,
    this.pixelsPerMinute = 1.0,
    this.initialHorizontalScrollOffset,
    this.pinchToZoomParam = const TimelinePinchToZoomParameters(),
    this.laneLabelWidth = 140,
    this.laneMinHeight = 60,
    this.eventHeight = 28,
    this.eventSpacing = 2,
    this.headerHeight = 56,
    this.onEventTap,
    this.onSlotTap,
    this.eventBuilder,
    this.laneLabelBuilder,
    this.dateHeaderBuilder,
    this.enableDrag = false,
    this.enableResize = false,
    this.scrollToZoom = false,
    this.dragSnapMinutes = 15,
    this.onEventDragStart,
    this.onEventDragUpdate,
    this.onEventDragEnd,
    this.onEventResizeStart,
    this.onEventResizeUpdate,
    this.onEventResizeEnd,
    this.willAcceptDrop,
    this.currentHourIndicatorParam,
  });

  final EventsController controller;
  final List<TimelineLane> lanes;

  /// The date that should be horizontally centered when first rendered.
  /// Defaults to today / `controller.focusedDay`.
  final DateTime? initialDate;

  /// Number of days rendered before [initialDate].
  final int maxPreviousDays;

  /// Number of days rendered after [initialDate].
  final int maxNextDays;

  /// Initial zoom: pixels per minute on the X axis.
  /// 1.0 → 60 px/hour, 1440 px/day. Adjustable via pinch-to-zoom.
  final double pixelsPerMinute;

  /// Initial horizontal scroll offset in pixels. If null, defaults to
  /// scrolling to [initialDate] (i.e. `maxPreviousDays * 1440 * pixelsPerMinute`).
  final double? initialHorizontalScrollOffset;

  /// Pinch-to-zoom configuration (speed, bounds, callbacks).
  final TimelinePinchToZoomParameters pinchToZoomParam;

  final double laneLabelWidth;
  final double laneMinHeight;
  final double eventHeight;
  final double eventSpacing;
  final double headerHeight;

  final void Function(Event event)? onEventTap;
  final void Function(TimelineLane lane, DateTime time)? onSlotTap;
  final Widget Function(Event event)? eventBuilder;
  final Widget Function(int laneIndex, TimelineLane lane)? laneLabelBuilder;

  /// Whether events can be long-press-dragged to move them between lanes/times.
  final bool enableDrag;

  /// Whether events show resize handles on left/right edges.
  final bool enableResize;

  /// Whether scroll wheel zooms without needing Ctrl/Meta held.
  final bool scrollToZoom;

  /// Snap grid for drag/resize in minutes (default 15).
  final int dragSnapMinutes;

  /// Called when an event drag begins (long-press).
  final void Function(Event event)? onEventDragStart;

  /// Called every time the proposed drop cell changes during a drag.
  final void Function(
    Event event,
    TimelineLane newLane,
    DateTime newStart,
    DateTime newEnd,
  )? onEventDragUpdate;

  /// Called when an event is dropped after dragging.
  final Future<void> Function(
    Event event,
    TimelineLane newLane,
    DateTime newStart,
    DateTime newEnd,
  )? onEventDragEnd;

  /// Called when a resize gesture begins.
  final void Function(Event event, bool isLeftEdge)? onEventResizeStart;

  /// Called every time the proposed resize bounds change.
  final void Function(
    Event event,
    DateTime newStart,
    DateTime newEnd,
  )? onEventResizeUpdate;

  /// Called when an event edge is resized.
  final Future<void> Function(
    Event event,
    DateTime newStart,
    DateTime newEnd,
  )? onEventResizeEnd;

  /// Synchronous check whether a dragged event can be dropped on a lane.
  /// Defaults to always-accept if null.
  final bool Function(Event event, TimelineLane targetLane)? willAcceptDrop;

  /// Optional current-hour vertical line indicator. When non-null and visible,
  /// a vertical line is drawn at the current time on today's column.
  final TimelineCurrentHourIndicatorParam? currentHourIndicatorParam;
  final Widget Function(DateTime day)? dateHeaderBuilder;

  @override
  State<EventsTimeline> createState() => EventsTimelineState();
}

// ── Drag / Resize state holders ──────────────────────────────────────────────

class _TimelineHit {
  _TimelineHit(this.laneIndex, this.time);
  final int laneIndex;
  final DateTime time;
}

class _DragState {
  _DragState({
    required this.event,
    required this.originalLaneIndex,
    required this.originalStart,
    required this.originalEnd,
    required this.pointerOffsetFromLeft,
    required this.eventDuration,
    required this.tileWidth,
    required this.tileHeight,
  });

  final Event event;
  final int originalLaneIndex;
  final DateTime originalStart;
  final DateTime originalEnd;
  final double pointerOffsetFromLeft; // px from event's left edge at grab
  final Duration eventDuration;
  final double tileWidth; // actual rendered width in px
  final double tileHeight; // actual rendered height in px

  // Current candidate position (updated during drag)
  int candidateLaneIndex = -1;
  DateTime? candidateStart;
  DateTime? candidateEnd;
  Offset lastGlobalPosition = Offset.zero;
  bool accepted = true;
}

class _ResizeState {
  _ResizeState({
    required this.event,
    required this.laneIndex,
    required this.isLeftEdge,
    required this.originalStart,
    required this.originalEnd,
  });

  final Event event;
  final int laneIndex;
  final bool isLeftEdge; // true = resizing start, false = resizing end
  final DateTime originalStart;
  final DateTime originalEnd;

  DateTime? candidateStart;
  DateTime? candidateEnd;
  double accumulatedDx = 0;
}

class EventsTimelineState extends State<EventsTimeline> {
  /// One sync group for the whole horizontal axis: the top header ListView
  /// plus every per-lane horizontal ListView in the body. Every registered
  /// controller stays at the same offset.
  late final HScrollSync hSync;

  /// Header ListView controller, owned directly (disposed in dispose()).
  late ScrollController hHeader;

  /// Lazily-created per-lane horizontal controllers. Keyed by lane index.
  /// Reused across rebuilds as long as the lane index is still valid.
  final Map<int, ScrollController> hLane = {};

  /// Vertical controllers for the labels column and the body column. Kept
  /// in sync via a listener pair — same pattern as before.
  late ScrollController vLabels;
  late ScrollController vBody;
  bool syncingV = false;

  late double pixelsPerMinute;
  late DateTime origin;

  // pinch / scale state
  double pixelsPerMinuteAtScaleStart = 1.0;
  double _offsetAtScaleStart = 0;
  // multi-pointer tracking (mirrors EventsPlanner._plannerPointerDownCount)
  var pointerDownCount = 0;
  var isKeyboardZoomActive = false;
  bool _isZooming = false;

  // ── drag / resize state ───────────────────────────────────────────────────
  _DragState? _activeDrag;
  _ResizeState? _activeResize;
  OverlayEntry? _dragOverlay;
  _Layout? _currentLayout; // cached for coordinate math during drag

  @override
  void initState() {
    super.initState();
    pixelsPerMinute = widget.pixelsPerMinute;
    final initial = (widget.initialDate ?? widget.controller.focusedDay);
    final initialMidnight = DateTime(initial.year, initial.month, initial.day);
    origin = initialMidnight.subtract(Duration(days: widget.maxPreviousDays));

    final minutesSinceMidnight =
        initial.hour * 60 + initial.minute + initial.second / 60.0;
    final initialHOffset = widget.initialHorizontalScrollOffset ??
        (widget.maxPreviousDays * 1440.0 + minutesSinceMidnight) *
            pixelsPerMinute;
    hSync = HScrollSync(
      initialOffset: initialHOffset,
    );
    hHeader = ScrollController(initialScrollOffset: hSync.currentOffset);
    hSync.register(hHeader);

    vLabels = ScrollController();
    vBody = ScrollController();
    vLabels.addListener(() => _syncV(vLabels, vBody));
    vBody.addListener(() => _syncV(vBody, vLabels));

    widget.controller.addListener(_onData);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    });
  }

  /// Returns (creating if needed) the horizontal controller for a given
  /// lane row. New controllers start at the group's current offset so a
  /// freshly-built lane row snaps into alignment with every other row.
  ScrollController _hCtrlFor(int laneIdx) {
    return hLane.putIfAbsent(laneIdx, () {
      final c = ScrollController(initialScrollOffset: hSync.currentOffset);
      hSync.register(c);
      return c;
    });
  }

  void _syncV(ScrollController src, ScrollController dst) {
    if (syncingV || !dst.hasClients) return;
    syncingV = true;
    dst.jumpTo(src.offset
        .clamp(dst.position.minScrollExtent, dst.position.maxScrollExtent));
    syncingV = false;
  }

  void _onData() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _removeDragOverlay();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    widget.controller.removeListener(_onData);
    hHeader.dispose();
    for (final c in hLane.values) {
      c.dispose();
    }
    hLane.clear();
    vLabels.dispose();
    vBody.dispose();
    super.dispose();
  }

  // ── public methods (mirrors EventsPlannerState) ──────────────────────────

  /// Programmatically update the zoom level.
  /// Mirrors [EventsPlannerState.updateHeightPerMinute].
  void updatePixelsPerMinute(double ppm) {
    setState(() {
      pixelsPerMinute = ppm;
    });
  }

  /// Programmatically update the horizontal scroll offset.
  /// Mirrors [EventsPlannerState.updateVerticalScrollOffset].
  void updateHorizontalScrollOffset(double offset) {
    hSync.jumpTo(offset);
  }

  /// Horizontally scroll so that [date] is at the left edge.
  /// Mirrors [EventsPlannerState.jumpToDate].
  void jumpToDate(DateTime date) {
    if (!mounted) return;
    final dayDiff =
        DateTime(date.year, date.month, date.day).difference(origin).inDays;
    hSync.jumpTo(dayDiff * 1440.0 * pixelsPerMinute);
  }

  // ── scale / zoom (mirrors EventsPlanner pattern) ─────────────────────────

  double _focalLocalX = 0;
  double _minuteAtFocal = 0;

  void _onScaleStart(ScaleStartDetails details) {
    _isZooming = true;
    pixelsPerMinuteAtScaleStart = pixelsPerMinute;
    _offsetAtScaleStart = hSync.currentOffset;
    // Capture the focal point relative to the timeline body.
    final rb = context.findRenderObject() as RenderBox?;
    _focalLocalX = rb != null
        ? rb.globalToLocal(details.focalPoint).dx - widget.laneLabelWidth
        : 0.0;
    _minuteAtFocal = (_offsetAtScaleStart + _focalLocalX) / pixelsPerMinute;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final zoom = widget.pinchToZoomParam;
    final speed = zoom.pinchToZoomSpeed;
    final minZoom = zoom.pinchToZoomMinPixelsPerMinute;
    final maxZoom = zoom.pinchToZoomMaxPixelsPerMinute;

    // Pinch-to-zoom (two pointers or trackpad pinch with scale != 1.0)
    if (details.pointerCount >= 2 || (details.scale - 1.0).abs() > 0.01) {
      final scale = (((details.horizontalScale - 1) * speed) + 1);
      final newPpm =
          (pixelsPerMinuteAtScaleStart * scale).clamp(minZoom, maxZoom);
      if (newPpm == pixelsPerMinute) return;

      final newOffset = _minuteAtFocal * newPpm - _focalLocalX;
      setState(() {
        pixelsPerMinute = newPpm;
        hSync.jumpTo(newOffset.clamp(0, double.infinity));
      });
      return;
    }

    // Scroll-to-zoom: trackpad two-finger vertical scroll (scale ≈ 1.0)
    if (widget.scrollToZoom) {
      final dy = details.focalPointDelta.dy;
      if (dy.abs() < 0.5) return;
      final delta = dy * -0.005 * speed;
      final newPpm = (pixelsPerMinute + delta).clamp(minZoom, maxZoom);
      if (newPpm == pixelsPerMinute) return;

      // Zoom relative to the focal point.
      final rb = context.findRenderObject() as RenderBox?;
      final localX = rb != null
          ? rb.globalToLocal(details.focalPoint).dx - widget.laneLabelWidth
          : 0.0;
      final minuteUnderFocal = (hSync.currentOffset + localX) / pixelsPerMinute;
      final newOffset = minuteUnderFocal * newPpm - localX;

      setState(() {
        pixelsPerMinute = newPpm;
        zoom.onZoomChange?.call(pixelsPerMinute);
        hSync.jumpTo(newOffset.clamp(0, double.infinity));
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    setState(() => _isZooming = false);
    widget.controller.notifyListeners();
    widget.pinchToZoomParam.onZoomChange?.call(pixelsPerMinute);
  }

  // ── pointer / keyboard zoom (mirrors EventsPlanner) ──────────────────────

  void _onPointerDown() {
    setState(() => pointerDownCount++);
  }

  void _onPointerUp() {
    setState(() => pointerDownCount--);
  }

  bool _handleKeyEvent(KeyEvent event) {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;

    if (widget.pinchToZoomParam.pinchToZoom) {
      final isModifierPressed =
          pressed.contains(LogicalKeyboardKey.controlLeft) ||
              pressed.contains(LogicalKeyboardKey.controlRight) ||
              pressed.contains(LogicalKeyboardKey.metaLeft) ||
              pressed.contains(LogicalKeyboardKey.metaRight);
      if (isModifierPressed != isKeyboardZoomActive) {
        setState(() => isKeyboardZoomActive = isModifierPressed);
      }
    }
    return false;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final zoom = widget.pinchToZoomParam;
      final minZoom = zoom.pinchToZoomMinPixelsPerMinute;
      final maxZoom = zoom.pinchToZoomMaxPixelsPerMinute;
      final speed = zoom.pinchToZoomSpeed;
      final delta = event.scrollDelta.dy * -0.001 * speed;
      final newPpm = (pixelsPerMinute + delta).clamp(minZoom, maxZoom);
      if (newPpm == pixelsPerMinute) return;

      // Zoom relative to cursor: the minute under the cursor stays fixed.
      final rb = context.findRenderObject() as RenderBox?;
      final localX = rb != null
          ? rb.globalToLocal(event.position).dx - widget.laneLabelWidth
          : 0.0;
      final minuteUnderCursor =
          (hSync.currentOffset + localX) / pixelsPerMinute;
      final newOffset = minuteUnderCursor * newPpm - localX;

      setState(() {
        _isZooming = true;
        pixelsPerMinute = newPpm;
        zoom.onZoomChange?.call(pixelsPerMinute);
        hSync.jumpTo(newOffset.clamp(0, double.infinity));
      });
      // Reset after this frame so the next non-zoom rebuild animates normally.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isZooming) setState(() => _isZooming = false);
      });
    }
  }

  // ── drag / resize helpers ────────────────────────────────────────────────

  /// Convert a global pointer position to (laneIndex, snapped DateTime).
  /// Returns null if the pointer is outside the body area.
  _TimelineHit? _globalToTimeline(Offset globalPosition) {
    final rb = context.findRenderObject() as RenderBox?;
    if (rb == null) return null;
    final local = rb.globalToLocal(globalPosition);

    // X: subtract lane label width to get into body area
    final bodyX = local.dx - widget.laneLabelWidth;
    if (bodyX < 0) return null;

    // Add horizontal scroll offset to get absolute position in content
    final absX = bodyX + hSync.currentOffset;
    final dayWidth = 1440.0 * pixelsPerMinute;
    final dayIndex = (absX / dayWidth).floor();
    final minuteInDay =
        ((absX % dayWidth) / pixelsPerMinute).round().clamp(0, 1440);

    // Snap to grid
    final snap = widget.dragSnapMinutes;
    final snappedMinute =
        snap > 0 ? (minuteInDay / snap).round() * snap : minuteInDay;

    final day = origin.add(Duration(days: dayIndex));
    final time = DateTime(day.year, day.month, day.day)
        .add(Duration(minutes: snappedMinute));

    // Y: subtract header height, add vertical scroll offset
    final bodyY = local.dy - widget.headerHeight;
    if (bodyY < 0) return null;
    final absY = bodyY + (vBody.hasClients ? vBody.offset : 0);

    // Walk cumulative lane heights to find lane index
    final layout = _currentLayout;
    if (layout == null) return null;
    double cumH = 0;
    for (var i = 0; i < layout.lanes.length; i++) {
      cumH += layout.lanes[i].height;
      if (absY < cumH) return _TimelineHit(i, time);
    }
    // Below all lanes → clamp to last lane
    return _TimelineHit(layout.lanes.length - 1, time);
  }

  /// Compute the local position (relative to the timeline widget) for a given
  /// lane index and time. Used for positioning the ghost overlay.
  Offset? _timelineToLocal(int laneIndex, DateTime time) {
    final layout = _currentLayout;
    if (layout == null || laneIndex < 0 || laneIndex >= layout.lanes.length) {
      return null;
    }

    // X position
    final dayStart = DateTime(time.year, time.month, time.day);
    final dayDiff = dayStart.difference(origin).inDays;
    final minuteInDay = time.difference(dayStart).inMinutes;
    final absX = (dayDiff * 1440.0 + minuteInDay) * pixelsPerMinute;
    final localX = widget.laneLabelWidth + absX - hSync.currentOffset;

    // Y position
    double cumH = 0;
    for (var i = 0; i < laneIndex; i++) {
      cumH += layout.lanes[i].height;
    }
    final localY =
        widget.headerHeight + cumH - (vBody.hasClients ? vBody.offset : 0);

    return Offset(localX, localY);
  }

  void _removeDragOverlay() {
    _dragOverlay?.remove();
    _dragOverlay = null;
  }

  void _updateDragOverlay() {
    _dragOverlay?.markNeedsBuild();
  }

  // ── event drag (long-press) ─────────────────────────────────────────────

  void _onEventLongPressStart(LongPressStartDetails details, Event event,
      int laneIndex, double tileWidth, double tileHeight) {
    if (event.isMultiDay || event.isFullDay) return;

    final end = event.endTime ?? event.startTime.add(const Duration(hours: 1));
    final pointerOffsetFromLeft =
        details.globalPosition.dx - _eventGlobalLeft(event, laneIndex);

    _activeDrag = _DragState(
      event: event,
      originalLaneIndex: laneIndex,
      originalStart: event.startTime,
      originalEnd: end,
      pointerOffsetFromLeft: pointerOffsetFromLeft.clamp(0, double.infinity),
      eventDuration: end.difference(event.startTime),
      tileWidth: tileWidth,
      tileHeight: tileHeight,
    );
    _activeDrag!.candidateLaneIndex = laneIndex;
    _activeDrag!.candidateStart = event.startTime;
    _activeDrag!.candidateEnd = end;
    _activeDrag!.lastGlobalPosition = details.globalPosition;

    widget.onEventDragStart?.call(event);
    _insertDragOverlay();
    setState(() {});
  }

  /// Approximate global left edge of an event tile (for offset calculation).
  double _eventGlobalLeft(Event event, int laneIndex) {
    final rb = context.findRenderObject() as RenderBox?;
    if (rb == null) return 0;
    final tlOrigin = rb.localToGlobal(Offset.zero);
    final dayStart = DateTime(
        event.startTime.year, event.startTime.month, event.startTime.day);
    final dayDiff = dayStart.difference(origin).inDays;
    final minuteInDay = event.startTime.difference(dayStart).inMinutes;
    final absX = (dayDiff * 1440.0 + minuteInDay) * pixelsPerMinute;
    return tlOrigin.dx + widget.laneLabelWidth + absX - hSync.currentOffset;
  }

  void _onEventLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final drag = _activeDrag;
    if (drag == null) return;

    drag.lastGlobalPosition = details.globalPosition;

    // Compute candidate lane+time, accounting for where the user grabbed
    final adjustedGlobal = Offset(
      details.globalPosition.dx - drag.pointerOffsetFromLeft,
      details.globalPosition.dy,
    );

    final hit = _globalToTimeline(adjustedGlobal);
    if (hit != null) {
      final changed = drag.candidateLaneIndex != hit.laneIndex ||
          drag.candidateStart != hit.time;
      drag.candidateLaneIndex = hit.laneIndex;
      drag.candidateStart = hit.time;
      drag.candidateEnd = hit.time.add(drag.eventDuration);

      // Check willAcceptDrop
      if (widget.willAcceptDrop != null &&
          hit.laneIndex < widget.lanes.length) {
        drag.accepted =
            widget.willAcceptDrop!(drag.event, widget.lanes[hit.laneIndex]);
      } else {
        drag.accepted = true;
      }

      if (changed && hit.laneIndex < widget.lanes.length) {
        widget.onEventDragUpdate?.call(
          drag.event,
          widget.lanes[hit.laneIndex],
          drag.candidateStart!,
          drag.candidateEnd!,
        );
      }
    }

    // Auto-scroll near edges
    _autoScrollDuringDrag(details.globalPosition);

    _updateDragOverlay();
  }

  void _onEventLongPressEnd(LongPressEndDetails details) async {
    final drag = _activeDrag;
    if (drag == null) return;

    if (drag.accepted &&
        drag.candidateStart != null &&
        drag.candidateEnd != null &&
        drag.candidateLaneIndex >= 0 &&
        drag.candidateLaneIndex < widget.lanes.length) {
      await widget.onEventDragEnd?.call(
        drag.event,
        widget.lanes[drag.candidateLaneIndex],
        drag.candidateStart!,
        drag.candidateEnd!,
      );
    }

    _removeDragOverlay();
    _activeDrag = null;
    if (mounted) setState(() {});
  }

  void _autoScrollDuringDrag(Offset globalPosition) {
    final rb = context.findRenderObject() as RenderBox?;
    if (rb == null) return;
    final local = rb.globalToLocal(globalPosition);
    final size = rb.size;

    // Horizontal auto-scroll only — within 40px of left/right edge
    const edgeZone = 40.0;
    const scrollSpeed = 8.0;
    if (local.dx > size.width - edgeZone) {
      hSync.jumpTo(hSync.currentOffset + scrollSpeed);
    } else if (local.dx < widget.laneLabelWidth + edgeZone) {
      hSync.jumpTo(hSync.currentOffset - scrollSpeed);
    }
    // No vertical auto-scroll — dragging between lanes causes the pointer
    // to move vertically which would trigger scroll and make it unusable.
  }

  void _insertDragOverlay() {
    _removeDragOverlay();
    _dragOverlay = OverlayEntry(builder: (_) => _buildDragOverlay());
    Overlay.of(context).insert(_dragOverlay!);
  }

  Widget _buildDragOverlay() {
    final drag = _activeDrag;
    final resize = _activeResize;

    if (drag != null) return _buildDragFeedback(drag);
    if (resize != null) return _buildResizeFeedback(resize);
    return const SizedBox.shrink();
  }

  Widget _buildDragFeedback(_DragState drag) {
    final candidateStart = drag.candidateStart;
    final candidateEnd = drag.candidateEnd;
    if (candidateStart == null || candidateEnd == null) {
      return const SizedBox.shrink();
    }

    // Use the actual captured tile dimensions from the rendered event
    final widthPx = drag.tileWidth;
    final heightPx = drag.tileHeight;

    // Ghost at snapped position
    final ghostPos = _timelineToLocal(drag.candidateLaneIndex, candidateStart);

    final rb = context.findRenderObject() as RenderBox?;
    final timelineOrigin = rb?.localToGlobal(Offset.zero) ?? Offset.zero;

    return Stack(
      children: [
        // Ghost preview at snap position
        if (ghostPos != null)
          Positioned(
            left: timelineOrigin.dx + ghostPos.dx,
            top: timelineOrigin.dy + ghostPos.dy + widget.eventSpacing,
            child: IgnorePointer(
              child: Container(
                width: widthPx < 2 ? 2 : widthPx,
                height: heightPx,
                decoration: BoxDecoration(
                  color: (drag.accepted ? drag.event.color : Colors.red)
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: drag.accepted ? drag.event.color : Colors.red,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        // Dragged tile following pointer — same size and content as the original
        Positioned(
          left: drag.lastGlobalPosition.dx - drag.pointerOffsetFromLeft,
          top: drag.lastGlobalPosition.dy - heightPx / 2,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.7,
              child: SizedBox(
                width: widthPx < 2 ? 2 : widthPx,
                height: heightPx,
                child: widget.eventBuilder?.call(drag.event) ??
                    _defaultEventTile(drag.event),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResizeFeedback(_ResizeState resize) {
    final start = resize.candidateStart ?? resize.originalStart;
    final end = resize.candidateEnd ?? resize.originalEnd;
    final durationMinutes = end.difference(start).inMinutes;
    if (durationMinutes <= 0) return const SizedBox.shrink();

    final widthPx = durationMinutes * pixelsPerMinute;
    // Use actual tile height from lane layout
    final layout = _currentLayout;
    final laneLayout =
        (layout != null && resize.laneIndex < layout.lanes.length)
            ? layout.lanes[resize.laneIndex]
            : null;
    final heightPx = laneLayout?.eventTileHeight(widget.eventSpacing) ??
        widget.eventHeight.toDouble();
    final ghostPos = _timelineToLocal(resize.laneIndex, start);

    final rb = context.findRenderObject() as RenderBox?;
    final timelineOrigin = rb?.localToGlobal(Offset.zero) ?? Offset.zero;

    if (ghostPos == null) return const SizedBox.shrink();

    return Stack(
      children: [
        Positioned(
          left: timelineOrigin.dx + ghostPos.dx,
          top: timelineOrigin.dy + ghostPos.dy + widget.eventSpacing,
          child: IgnorePointer(
            child: SizedBox(
              width: widthPx < 2 ? 2 : widthPx,
              height: heightPx,
              child: widget.eventBuilder?.call(resize.event) ??
                  _defaultEventTile(resize.event),
            ),
          ),
        ),
      ],
    );
  }

  // ── event resize ────────────────────────────────────────────────────────

  GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>
      _resizeHandleGesture(Event event, int laneIndex, bool isLeftEdge) {
    return GestureRecognizerFactoryWithHandlers<
        HorizontalDragGestureRecognizer>(
      () => HorizontalDragGestureRecognizer(),
      (instance) {
        instance.onStart = (details) {
          if (event.isMultiDay || event.isFullDay) return;
          final end =
              event.endTime ?? event.startTime.add(const Duration(hours: 1));
          _activeResize = _ResizeState(
            event: event,
            laneIndex: laneIndex,
            isLeftEdge: isLeftEdge,
            originalStart: event.startTime,
            originalEnd: end,
          );
          _activeResize!.candidateStart = event.startTime;
          _activeResize!.candidateEnd = end;
          widget.onEventResizeStart?.call(event, isLeftEdge);
          _insertDragOverlay();
          setState(() {});
        };
        instance.onUpdate = (details) {
          final resize = _activeResize;
          if (resize == null) return;
          final snap = widget.dragSnapMinutes;
          resize.accumulatedDx += details.delta.dx;
          final deltaMinutes = (resize.accumulatedDx / pixelsPerMinute).round();
          final snappedDelta =
              snap > 0 ? (deltaMinutes / snap).round() * snap : deltaMinutes;

          final prevStart = resize.candidateStart;
          final prevEnd = resize.candidateEnd;
          if (resize.isLeftEdge) {
            final newStart =
                resize.originalStart.add(Duration(minutes: snappedDelta));
            final endBound = resize.candidateEnd ?? resize.originalEnd;
            if (newStart.isBefore(endBound) &&
                endBound.difference(newStart).inMinutes >= snap) {
              resize.candidateStart = newStart;
            }
          } else {
            final newEnd =
                resize.originalEnd.add(Duration(minutes: snappedDelta));
            final startBound = resize.candidateStart ?? resize.originalStart;
            if (newEnd.isAfter(startBound) &&
                newEnd.difference(startBound).inMinutes >= snap) {
              resize.candidateEnd = newEnd;
            }
          }
          if (prevStart != resize.candidateStart ||
              prevEnd != resize.candidateEnd) {
            widget.onEventResizeUpdate?.call(
              resize.event,
              resize.candidateStart ?? resize.originalStart,
              resize.candidateEnd ?? resize.originalEnd,
            );
          }
          _updateDragOverlay();
          setState(() {});
        };
        instance.onEnd = (details) async {
          final resize = _activeResize;
          if (resize == null) return;
          await widget.onEventResizeEnd?.call(
            resize.event,
            resize.candidateStart ?? resize.originalStart,
            resize.candidateEnd ?? resize.originalEnd,
          );
          _removeDragOverlay();
          _activeResize = null;
          if (mounted) setState(() {});
        };
      },
    );
  }

  // ── layout ───────────────────────────────────────────────────────────────

  int get _totalDays => widget.maxPreviousDays + widget.maxNextDays + 1;

  /// Greedy packing: assign each event to the lowest sub-row whose previous
  /// event has already ended.
  List<int> _packEvents(List<Event> sorted) {
    final rowEnds = <DateTime>[];
    final result = List<int>.filled(sorted.length, 0);
    for (var i = 0; i < sorted.length; i++) {
      final e = sorted[i];
      final start = e.effectiveStartTime ?? e.startTime;
      final end = e.effectiveEndTime ??
          e.endTime ??
          start.add(const Duration(hours: 1));
      var placed = -1;
      for (var r = 0; r < rowEnds.length; r++) {
        if (!rowEnds[r].isAfter(start)) {
          rowEnds[r] = end;
          placed = r;
          break;
        }
      }
      if (placed < 0) {
        rowEnds.add(end);
        placed = rowEnds.length - 1;
      }
      result[i] = placed;
    }
    return result;
  }

  /// Returns sorted+packed events grouped by lane index.
  _Layout _computeLayout() {
    final byLane = <int, List<Event>>{
      for (var i = 0; i < widget.lanes.length; i++) i: <Event>[],
    };
    final laneOfId = <UniqueKey, int>{};
    final seen = <UniqueKey>{};
    for (final list in widget.controller.calendarData.dayEvents.values) {
      for (final e in list) {
        if (!seen.add(e.uniqueId)) continue;
        final laneIdx = widget.lanes.indexWhere((l) => l.id == e.eventType);
        if (laneIdx < 0) continue;
        byLane[laneIdx]!.add(e);
        laneOfId[e.uniqueId] = laneIdx;
      }
    }

    final lanes = <_LaneLayout>[];
    for (var i = 0; i < widget.lanes.length; i++) {
      final sorted = [...byLane[i]!]..sort((a, b) =>
          (a.effectiveStartTime ?? a.startTime)
              .compareTo(b.effectiveStartTime ?? b.startTime));
      final packed = _packEvents(sorted);
      final subRows =
          packed.isEmpty ? 1 : (packed.reduce((a, b) => a > b ? a : b) + 1);
      final h = (subRows * (widget.eventHeight + widget.eventSpacing) +
              widget.eventSpacing)
          .toDouble();
      final subRowById = <UniqueKey, int>{
        for (var k = 0; k < sorted.length; k++) sorted[k].uniqueId: packed[k],
      };
      lanes.add(_LaneLayout(
        events: sorted,
        subRowOf: packed,
        subRowById: subRowById,
        subRows: subRows,
        height: h < widget.laneMinHeight ? widget.laneMinHeight : h,
      ));
    }
    return _Layout(lanes: lanes, laneOfId: laneOfId);
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final layout = _computeLayout();
    _currentLayout = layout; // cache for drag coordinate math
    final lanes = layout.lanes;
    final dayWidth = 1440.0 * pixelsPerMinute;
    final zoom = widget.pinchToZoomParam;
    final isDraggingOrResizing = _activeDrag != null || _activeResize != null;
    final canZoom = zoom.pinchToZoom && !isDraggingOrResizing;
    final scrollZoomActive =
        (widget.scrollToZoom || isKeyboardZoomActive) && !isDraggingOrResizing;
    final disableScroll =
        pointerDownCount > 1 || isKeyboardZoomActive || isDraggingOrResizing;

    return GestureDetector(
      onScaleStart: canZoom ? zoom.onScaleStart ?? _onScaleStart : null,
      onScaleUpdate: canZoom ? zoom.onScaleUpdate ?? _onScaleUpdate : null,
      onScaleEnd: canZoom ? zoom.onScaleEnd ?? _onScaleEnd : null,
      child: Listener(
        onPointerSignal: scrollZoomActive ? _onPointerSignal : null,
        // Always track pointer up/down so the count can't get stuck when
        // drag/resize toggles `canZoom` mid-gesture.
        onPointerDown: zoom.pinchToZoom ? (_) => _onPointerDown() : null,
        onPointerCancel: zoom.pinchToZoom ? (_) => _onPointerUp() : null,
        onPointerUp: zoom.pinchToZoom ? (_) => _onPointerUp() : null,
        child: IgnorePointer(
          ignoring: zoom.pinchToZoom && !isDraggingOrResizing
              ? pointerDownCount > 1
              : false,
          child: Column(
            children: [
              // Top header row (corner + lazy scrolling time header)
              SizedBox(
                height: widget.headerHeight,
                child: Row(
                  children: [
                    Container(
                      width: widget.laneLabelWidth,
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                              color: Colors.grey.shade400, width: 0.5),
                          bottom: BorderSide(
                              color: Colors.grey.shade400, width: 0.5),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: hHeader,
                        scrollDirection: Axis.horizontal,
                        physics: disableScroll
                            ? const NeverScrollableScrollPhysics()
                            : const ClampingScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemExtent: dayWidth,
                        itemCount: _totalDays,
                        itemBuilder: (context, index) =>
                            _buildHeaderItem(origin.add(Duration(days: index))),
                      ),
                    ),
                  ],
                ),
              ),
              // Body: labels list + lane-rows list share the vertical scroll
              // via vLabels ↔ vBody listeners. Each lane row owns its own
              // horizontal ListView; all of them + the header share the same
              // horizontal offset via hSync so they scroll as one.
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: widget.laneLabelWidth,
                      child: ListView.builder(
                        controller: vLabels,
                        physics: widget.scrollToZoom
                            ? const NeverScrollableScrollPhysics()
                            : const ClampingScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: widget.lanes.length,
                        itemBuilder: (context, i) => SizedBox(
                          height: lanes[i].height,
                          child: widget.laneLabelBuilder
                                  ?.call(i, widget.lanes[i]) ??
                              _defaultLaneLabel(widget.lanes[i]),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: vBody,
                        physics: widget.scrollToZoom
                            ? const NeverScrollableScrollPhysics()
                            : const ClampingScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: widget.lanes.length,
                        itemBuilder: (context, i) {
                          return SizedBox(
                            height: lanes[i].height,
                            child: ListView.builder(
                              controller: _hCtrlFor(i),
                              scrollDirection: Axis.horizontal,
                              physics: disableScroll
                                  ? const NeverScrollableScrollPhysics()
                                  : const ClampingScrollPhysics(),
                              padding: EdgeInsets.zero,
                              itemExtent: dayWidth,
                              itemCount: _totalDays,
                              itemBuilder: (context, d) => _buildLaneDayCell(
                                laneIndex: i,
                                lane: lanes[i],
                                day: origin.add(Duration(days: d)),
                                dayWidth: dayWidth,
                                laneHeight: lanes[i].height,
                                stripe: i.isEven,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── header ────────────────────────────────────────────────────────────────

  int get _hourStep {
    final pxPerHour = 60.0 * pixelsPerMinute;
    if (pxPerHour >= 60) return 1;
    if (pxPerHour * 3 >= 60) return 3;
    if (pxPerHour * 6 >= 60) return 6;
    return 24; // only days fit
  }

  /// One header column for a single day. Built lazily by the header
  /// `ListView.builder`.
  Widget _buildHeaderItem(DateTime day) {
    final dayWidth = 1440.0 * pixelsPerMinute;
    final dateRowH = widget.headerHeight * 0.5;
    final hourRowH = widget.headerHeight - dateRowH;
    final hourStep = _hourStep;

    final hourCells = <Widget>[];
    if (hourStep < 24) {
      for (var h = 0; h < 24; h += hourStep) {
        hourCells.add(Container(
          width: hourStep * 60 * pixelsPerMinute,
          height: hourRowH,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: Colors.grey.shade300, width: 0.5),
              bottom: BorderSide(color: Colors.grey.shade400, width: 0.5),
            ),
          ),
          child: Text(
            '${h.toString().padLeft(2, '0')}:00',
            style: const TextStyle(fontSize: 10),
          ),
        ));
      }
    }

    return SizedBox(
      width: dayWidth,
      height: widget.headerHeight,
      child: Column(
        children: [
          Container(
            width: dayWidth,
            height: dateRowH,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.grey.shade400, width: 0.5),
                bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
              ),
            ),
            child: widget.dateHeaderBuilder?.call(day) ??
                Text(
                  _formatDate(day, dayWidth),
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
          ),
          if (hourStep < 24)
            SizedBox(
              width: dayWidth,
              height: hourRowH,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: hourCells,
              ),
            )
          else
            Container(
              width: dayWidth,
              height: hourRowH,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: Colors.grey.shade400, width: 0.5),
                  bottom: BorderSide(color: Colors.grey.shade400, width: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d, double dayWidth) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    if (dayWidth < 30) return '${d.day}';
    if (dayWidth < 80) return '${d.day} ${months[d.month - 1]}';
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  // ── body ──────────────────────────────────────────────────────────────────

  /// One cell = (lane row) × (single day). Built lazily by the per-lane
  /// horizontal `ListView.builder`.
  Widget _buildLaneDayCell({
    required int laneIndex,
    required _LaneLayout lane,
    required DateTime day,
    required double dayWidth,
    required double laneHeight,
    required bool stripe,
  }) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEvents =
        widget.controller.calendarData.dayEvents[dayStart] ?? const <Event>[];
    final tileHeight = lane.eventTileHeight(widget.eventSpacing);

    final children = <Widget>[
      // background stripe + bottom border for the lane row
      Positioned.fill(
        child: Container(
          decoration: BoxDecoration(
            color: stripe
                ? Colors.grey.withValues(alpha: 0.04)
                : Colors.transparent,
            border: Border(
              right: BorderSide(color: Colors.grey.shade300, width: 0.5),
              bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
            ),
          ),
        ),
      ),
    ];

    // Slot tap layer for this lane on this day.
    if (widget.onSlotTap != null) {
      children.add(Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (details) {
            final minutes = (details.localPosition.dx / pixelsPerMinute)
                .round()
                .clamp(0, 1440);
            final time = dayStart.add(Duration(minutes: minutes));
            widget.onSlotTap!(widget.lanes[laneIndex], time);
          },
        ),
      ));
    }

    // Events on this lane, this day.
    for (final e in dayEvents) {
      if (e.eventType != widget.lanes[laneIndex].id) continue;
      final subRow = lane.subRowById[e.uniqueId] ?? 0;
      final start = e.startTime;
      final end = e.endTime ?? start.add(const Duration(hours: 1));
      final leftMin =
          start.difference(dayStart).inMinutes.clamp(0, 1440).toDouble();
      var widthMin = end.difference(start).inMinutes.toDouble();
      if (widthMin <= 0) widthMin = e.isFullDay ? 1440.0 : 60.0;
      final width = widthMin * pixelsPerMinute;
      final top =
          widget.eventSpacing + subRow * (tileHeight + widget.eventSpacing);

      final isDragging = _activeDrag?.event.uniqueId == e.uniqueId;
      final isResizing = _activeResize?.event.uniqueId == e.uniqueId;
      final canInteract = !e.isMultiDay && !e.isFullDay;
      final eventContent = widget.eventBuilder?.call(e) ?? _defaultEventTile(e);

      Widget tile;
      if (canInteract && (widget.enableDrag || widget.enableResize)) {
        tile = Stack(
          children: [
            // Main body — handles tap + long-press drag
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onEventTap == null
                    ? null
                    : () => widget.onEventTap!(e),
                onLongPressStart: widget.enableDrag
                    ? (details) => _onEventLongPressStart(details, e, laneIndex,
                        width < 2 ? 2 : width, tileHeight)
                    : null,
                onLongPressMoveUpdate:
                    widget.enableDrag ? _onEventLongPressMoveUpdate : null,
                onLongPressEnd: widget.enableDrag ? _onEventLongPressEnd : null,
                child: eventContent,
              ),
            ),
            // Left resize handle
            if (widget.enableResize)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 8,
                child: RawGestureDetector(
                  gestures: {
                    HorizontalDragGestureRecognizer:
                        _resizeHandleGesture(e, laneIndex, true),
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeft,
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ),
            // Right resize handle
            if (widget.enableResize)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 8,
                child: RawGestureDetector(
                  gestures: {
                    HorizontalDragGestureRecognizer:
                        _resizeHandleGesture(e, laneIndex, false),
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeRight,
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ),
          ],
        );
      } else {
        tile = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onEventTap == null ? null : () => widget.onEventTap!(e),
          child: eventContent,
        );
      }

      children.add(AnimatedPositioned(
        key: e.isMultiDay ? ValueKey(e.uniqueId) : GlobalObjectKey(e.uniqueId),
        duration: (isDragging || isResizing || _isZooming)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        left: leftMin * pixelsPerMinute,
        top: top,
        width: width < 2 ? 2 : width,
        height: tileHeight,
        child: Opacity(
          opacity: (isDragging || isResizing) ? 0.3 : 1.0,
          child: tile,
        ),
      ));
    }

    // Current hour indicator (vertical line at "now" on today's cell)
    final indicator = widget.currentHourIndicatorParam;
    if (indicator != null &&
        indicator.visible &&
        DateUtils.isSameDay(day, DateTime.now())) {
      final now = DateTime.now();
      final minutesSinceMidnight =
          now.hour * 60 + now.minute + now.second / 60.0;
      final xPos = minutesSinceMidnight * pixelsPerMinute;
      children.add(Positioned(
        left: xPos - indicator.strokeWidth / 2,
        top: 0,
        bottom: 0,
        width: indicator.strokeWidth,
        child: IgnorePointer(
          child: CustomPaint(
            painter: _TimelineCurrentHourPainter(
              color: indicator.color,
              strokeWidth: indicator.strokeWidth,
              circleRadius: indicator.circleRadius,
              showCircle: indicator.showCircle,
            ),
          ),
        ),
      ));
    }

    return SizedBox(
      width: dayWidth,
      height: laneHeight,
      child: Stack(clipBehavior: Clip.hardEdge, children: children),
    );
  }

  Widget _defaultLaneLabel(TimelineLane lane) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      alignment: Alignment.topLeft,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.grey.shade400, width: 0.5),
          bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
        ),
      ),
      child: Text(
        lane.id.toString(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }

  Widget _defaultEventTile(Event event) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: event.color,
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        event.title ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: event.textColor, fontSize: 11),
      ),
    );
  }
}

class _LaneLayout {
  _LaneLayout({
    required this.events,
    required this.subRowOf,
    required this.subRowById,
    required this.subRows,
    required this.height,
  });

  final List<Event> events;
  final List<int> subRowOf;
  final Map<UniqueKey, int> subRowById;
  final int subRows;
  final double height;

  /// Pixel height of an event tile so that [subRows] tiles plus inter-row
  /// spacing exactly fill [height].
  double eventTileHeight(double spacing) {
    final h = (height - spacing * (subRows + 1)) / subRows;
    return h < 1 ? 1 : h;
  }
}

class _TimelineCurrentHourPainter extends CustomPainter {
  const _TimelineCurrentHourPainter({
    required this.color,
    required this.strokeWidth,
    required this.circleRadius,
    required this.showCircle,
  });

  final Color color;
  final double strokeWidth;
  final double circleRadius;
  final bool showCircle;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth;
    // Vertical line spanning the full height of the cell.
    final x = size.width / 2;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    if (showCircle) {
      canvas.drawCircle(Offset(x, circleRadius), circleRadius, paint);
    }
  }

  @override
  bool shouldRepaint(_TimelineCurrentHourPainter oldDelegate) =>
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      circleRadius != oldDelegate.circleRadius ||
      showCircle != oldDelegate.showCircle;
}

class _Layout {
  _Layout({required this.lanes, required this.laneOfId});

  final List<_LaneLayout> lanes;
  final Map<UniqueKey, int> laneOfId;
}

/// Keeps any number of horizontal [ScrollController]s locked to the same
/// offset. Used so the top header and every per-lane body row scroll as one
/// on the X axis.
class HScrollSync {
  HScrollSync({required double initialOffset}) : currentOffset = initialOffset;

  double currentOffset;
  final List<ScrollController> _controllers = [];
  bool _syncing = false;

  void register(ScrollController c) {
    _controllers.add(c);
    c.addListener(() {
      if (_syncing || !c.hasClients) return;
      currentOffset = c.offset;
      _syncing = true;
      for (final other in _controllers) {
        if (identical(other, c) || !other.hasClients) continue;
        other.jumpTo(currentOffset.clamp(
          other.position.minScrollExtent,
          other.position.maxScrollExtent,
        ));
      }
      _syncing = false;
    });
  }

  void jumpTo(double offset) {
    currentOffset = offset;
    _syncing = true;
    for (final c in _controllers) {
      if (!c.hasClients) continue;
      c.jumpTo(offset.clamp(
        c.position.minScrollExtent,
        c.position.maxScrollExtent,
      ));
    }
    _syncing = false;
  }
}
