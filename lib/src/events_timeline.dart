import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller/events_controller.dart';
import 'events/event.dart';

/// A "lane" (row) on the gantt-style [EventsTimeline].
///
/// Each lane corresponds to a person, room, resource, project, etc.
/// Events are matched to a lane via [Event.eventType] == [TimelineLane.id].
class TimelineLane {
  const TimelineLane({
    required this.id,
    this.title,
    this.color,
    this.data,
  });

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
  final Widget Function(TimelineLane lane)? laneLabelBuilder;

  @override
  State<EventsTimeline> createState() => EventsTimelineState();
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

  @override
  void initState() {
    super.initState();
    pixelsPerMinute = widget.pixelsPerMinute;
    final initial = (widget.initialDate ?? widget.controller.focusedDay);
    // final initialDay = DateTime(initial.year, initial.month, initial.day);
    origin = initial.subtract(Duration(days: widget.maxPreviousDays));

    // Start the horizontal axis pre-scrolled to the supplied offset, or
    // default to scrolling to "today".
    final initialHOffset = widget.initialHorizontalScrollOffset ??
        widget.maxPreviousDays * 1440.0 * pixelsPerMinute;
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

  void _onScaleStart(ScaleStartDetails details) {
    if (details.pointerCount == 2) {
      pixelsPerMinuteAtScaleStart = pixelsPerMinute;
      _offsetAtScaleStart = hSync.currentOffset;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount != 2) return;
    final zoom = widget.pinchToZoomParam;
    final speed = zoom.pinchToZoomSpeed;
    final scale = (((details.horizontalScale - 1) * speed) + 1);
    final newPpm = pixelsPerMinuteAtScaleStart * scale;
    final minZoom = zoom.pinchToZoomMinPixelsPerMinute;
    final maxZoom = zoom.pinchToZoomMaxPixelsPerMinute;

    if (minZoom <= newPpm && newPpm <= maxZoom) {
      setState(() {
        pixelsPerMinute = newPpm;
        hSync.jumpTo(_offsetAtScaleStart * scale);
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
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
      final newPpm = pixelsPerMinute + delta;

      if (minZoom <= newPpm && newPpm <= maxZoom) {
        final scale = newPpm / pixelsPerMinute;
        setState(() {
          pixelsPerMinute = newPpm;
          zoom.onZoomChange?.call(pixelsPerMinute);
          hSync.jumpTo(hSync.currentOffset * scale);
        });
      }
    }
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
    final lanes = layout.lanes;
    final dayWidth = 1440.0 * pixelsPerMinute;
    final zoom = widget.pinchToZoomParam;
    final canZoom = zoom.pinchToZoom;
    final disableScroll = pointerDownCount > 1 || isKeyboardZoomActive;

    return GestureDetector(
      onScaleStart: canZoom ? zoom.onScaleStart ?? _onScaleStart : null,
      onScaleUpdate: canZoom ? zoom.onScaleUpdate ?? _onScaleUpdate : null,
      onScaleEnd: canZoom ? zoom.onScaleEnd ?? _onScaleEnd : null,
      child: Listener(
        onPointerSignal: isKeyboardZoomActive ? _onPointerSignal : null,
        onPointerDown: canZoom ? (_) => _onPointerDown() : null,
        onPointerCancel: canZoom ? (_) => _onPointerUp() : null,
        onPointerUp: canZoom ? (_) => _onPointerUp() : null,
        child: IgnorePointer(
          ignoring: canZoom ? pointerDownCount > 1 : false,
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
                        physics: const ClampingScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: widget.lanes.length,
                        itemBuilder: (context, i) => SizedBox(
                          height: lanes[i].height,
                          child:
                              widget.laneLabelBuilder?.call(widget.lanes[i]) ??
                                  _defaultLaneLabel(widget.lanes[i]),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: vBody,
                        physics: const ClampingScrollPhysics(),
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
            child: Text(
              _formatDate(day, dayWidth),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
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
      children.add(Positioned(
        left: leftMin * pixelsPerMinute,
        top: top,
        width: width < 2 ? 2 : width,
        height: tileHeight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onEventTap == null ? null : () => widget.onEventTap!(e),
          child: widget.eventBuilder?.call(e) ?? _defaultEventTile(e),
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
        color: lane.color?.withValues(alpha: 0.12),
        border: Border(
          right: BorderSide(color: Colors.grey.shade400, width: 0.5),
          bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
        ),
      ),
      child: Text(
        lane.title ?? lane.id.toString(),
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
