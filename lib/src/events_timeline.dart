import 'package:flutter/material.dart';

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
    this.minPixelsPerMinute = 0.05,
    this.maxPixelsPerMinute = 8.0,
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
  final double minPixelsPerMinute;
  final double maxPixelsPerMinute;

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
  State<EventsTimeline> createState() => _EventsTimelineState();
}

class _EventsTimelineState extends State<EventsTimeline> {
  late ScrollController _hHeader;
  late ScrollController _hBody;
  late ScrollController _vLeft;
  late ScrollController _vBody;

  late double _ppm;
  late DateTime _origin;

  bool _syncingH = false;
  bool _syncingV = false;

  // pinch / scale state
  double _ppmAtScaleStart = 1.0;
  double _focalContentX = 0;

  @override
  void initState() {
    super.initState();
    _ppm = widget.pixelsPerMinute;
    final initial =
        (widget.initialDate ?? widget.controller.focusedDay);
    final initialDay = DateTime(initial.year, initial.month, initial.day);
    _origin = initialDay.subtract(Duration(days: widget.maxPreviousDays));

    _hHeader = ScrollController();
    _hBody = ScrollController();
    _vLeft = ScrollController();
    _vBody = ScrollController();

    _hHeader.addListener(() => _syncH(_hHeader, _hBody));
    _hBody.addListener(() => _syncH(_hBody, _hHeader));
    _vLeft.addListener(() => _syncV(_vLeft, _vBody));
    _vBody.addListener(() => _syncV(_vBody, _vLeft));

    widget.controller.addListener(_onData);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hBody.hasClients) return;
      final offset = (widget.maxPreviousDays * 1440.0 * _ppm)
          .clamp(_hBody.position.minScrollExtent,
              _hBody.position.maxScrollExtent);
      _hBody.jumpTo(offset);
    });
  }

  void _syncH(ScrollController src, ScrollController dst) {
    if (_syncingH || !dst.hasClients) return;
    _syncingH = true;
    dst.jumpTo(src.offset
        .clamp(dst.position.minScrollExtent, dst.position.maxScrollExtent));
    _syncingH = false;
  }

  void _syncV(ScrollController src, ScrollController dst) {
    if (_syncingV || !dst.hasClients) return;
    _syncingV = true;
    dst.jumpTo(src.offset
        .clamp(dst.position.minScrollExtent, dst.position.maxScrollExtent));
    _syncingV = false;
  }

  void _onData() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onData);
    _hHeader.dispose();
    _hBody.dispose();
    _vLeft.dispose();
    _vBody.dispose();
    super.dispose();
  }

  int get _totalDays =>
      widget.maxPreviousDays + widget.maxNextDays + 1;

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
  ///
  /// Packing is done **globally** (across the whole range), keyed by
  /// `Event.uniqueId`, so multi-day event chunks land on the same vertical
  /// sub-row in every day-column they cross. Day-column item builders look up
  /// their sub-row via `subRowById[event.uniqueId]` — O(1) per event.
  ///
  /// Also looks up the lane index for an event id via `laneOfId` so the
  /// per-day item builder can route a `dayEvents[day]` chunk to the right
  /// lane in O(1).
  _Layout _computeLayout() {
    final byLane = <int, List<Event>>{
      for (var i = 0; i < widget.lanes.length; i++) i: <Event>[],
    };
    final laneOfId = <UniqueKey, int>{};
    final seen = <UniqueKey>{};
    for (final list in widget.controller.calendarData.dayEvents.values) {
      for (final e in list) {
        if (!seen.add(e.uniqueId)) continue;
        final laneIdx =
            widget.lanes.indexWhere((l) => l.id == e.eventType);
        if (laneIdx < 0) continue;
        byLane[laneIdx]!.add(e);
        laneOfId[e.uniqueId] = laneIdx;
      }
    }

    final lanes = <_LaneLayout>[];
    for (var i = 0; i < widget.lanes.length; i++) {
      final sorted = [...byLane[i]!]
        ..sort((a, b) => (a.effectiveStartTime ?? a.startTime)
            .compareTo(b.effectiveStartTime ?? b.startTime));
      final packed = _packEvents(sorted);
      final subRows = packed.isEmpty
          ? 1
          : (packed.reduce((a, b) => a > b ? a : b) + 1);
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

  @override
  Widget build(BuildContext context) {
    final layout = _computeLayout();
    final lanes = layout.lanes;
    final laneTops = <double>[];
    var acc = 0.0;
    for (final l in lanes) {
      laneTops.add(acc);
      acc += l.height;
    }
    final totalHeight = acc;
    final dayWidth = 1440.0 * _ppm;

    return GestureDetector(
      onScaleStart: (d) {
        _ppmAtScaleStart = _ppm;
        if (_hBody.hasClients) {
          _focalContentX = _hBody.offset + d.localFocalPoint.dx;
        }
      },
      onScaleUpdate: (d) {
        if (d.pointerCount < 2) return;
        final newPpm = (_ppmAtScaleStart * d.horizontalScale)
            .clamp(widget.minPixelsPerMinute, widget.maxPixelsPerMinute);
        if (newPpm == _ppm) return;
        final ratio = newPpm / _ppmAtScaleStart;
        setState(() => _ppm = newPpm);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_hBody.hasClients) return;
          final newOffset = (_focalContentX * ratio - d.localFocalPoint.dx)
              .clamp(_hBody.position.minScrollExtent,
                  _hBody.position.maxScrollExtent);
          _hBody.jumpTo(newOffset);
        });
      },
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
                    controller: _hHeader,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemExtent: dayWidth,
                    itemCount: _totalDays,
                    itemBuilder: (context, index) =>
                        _buildHeaderItem(_origin.add(Duration(days: index))),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                // Sticky left lane labels (lazy, vertical scroll synced
                // with the body via _vLeft ↔ _vBody listeners).
                SizedBox(
                  width: widget.laneLabelWidth,
                  child: ListView.builder(
                    controller: _vLeft,
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: widget.lanes.length,
                    itemBuilder: (context, i) => SizedBox(
                      height: lanes[i].height,
                      child: widget.laneLabelBuilder
                              ?.call(widget.lanes[i]) ??
                          _defaultLaneLabel(widget.lanes[i]),
                    ),
                  ),
                ),
                // 2D body: vertical scroll wraps a lazy horizontal ListView.
                // Align(topLeft) is required: when totalHeight < viewport
                // height the inner SingleChildScrollView slot would otherwise
                // vertically center the SizedBox, pushing all lane rows down
                // out of alignment with the sticky lane labels on the left.
                Expanded(
                  child: SingleChildScrollView(
                    controller: _vBody,
                    physics: const ClampingScrollPhysics(),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        height: totalHeight,
                        width: double.infinity,
                        child: ListView.builder(
                          controller: _hBody,
                          scrollDirection: Axis.horizontal,
                          physics: const ClampingScrollPhysics(),
                          padding: EdgeInsets.zero,
                          itemExtent: dayWidth,
                          itemCount: _totalDays,
                          itemBuilder: (context, index) {
                            final day = _origin.add(Duration(days: index));
                            return _buildBodyItem(
                              day: day,
                              dayWidth: dayWidth,
                              totalHeight: totalHeight,
                              layout: layout,
                              laneTops: laneTops,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── header ────────────────────────────────────────────────────────────────

  int get _hourStep {
    final pxPerHour = 60.0 * _ppm;
    if (pxPerHour >= 60) return 1;
    if (pxPerHour * 3 >= 60) return 3;
    if (pxPerHour * 6 >= 60) return 6;
    return 24; // only days fit
  }

  /// One header column for a single day. Built lazily by the header
  /// `ListView.builder`.
  Widget _buildHeaderItem(DateTime day) {
    final dayWidth = 1440.0 * _ppm;
    final dateRowH = widget.headerHeight * 0.5;
    final hourRowH = widget.headerHeight - dateRowH;
    final hourStep = _hourStep;

    final hourCells = <Widget>[];
    if (hourStep < 24) {
      for (var h = 0; h < 24; h += hourStep) {
        hourCells.add(Container(
          width: hourStep * 60 * _ppm,
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
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
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
                  right:
                      BorderSide(color: Colors.grey.shade400, width: 0.5),
                  bottom:
                      BorderSide(color: Colors.grey.shade400, width: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d, double dayWidth) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    if (dayWidth < 30) return '${d.day}';
    if (dayWidth < 80) return '${d.day} ${months[d.month - 1]}';
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  // ── body ──────────────────────────────────────────────────────────────────

  /// One body column for a single day. Built lazily by the body
  /// `ListView.builder`.
  Widget _buildBodyItem({
    required DateTime day,
    required double dayWidth,
    required double totalHeight,
    required _Layout layout,
    required List<double> laneTops,
  }) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayKey = dayStart;
    final dayEvents =
        widget.controller.calendarData.dayEvents[dayKey] ?? const <Event>[];

    final children = <Widget>[];

    // Lane row backgrounds + bottom borders (small, bounded by lane count)
    for (var i = 0; i < layout.lanes.length; i++) {
      children.add(Positioned(
        left: 0,
        right: 0,
        top: laneTops[i],
        height: layout.lanes[i].height,
        child: Container(
          decoration: BoxDecoration(
            color: i.isEven
                ? Colors.grey.withValues(alpha: 0.04)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
            ),
          ),
        ),
      ));
    }

    // Right-edge vertical day grid line
    children.add(Positioned(
      right: 0,
      top: 0,
      width: 1,
      height: totalHeight,
      child: Container(color: Colors.grey.shade300),
    ));

    // Slot tap layer (one per lane row)
    if (widget.onSlotTap != null) {
      for (var i = 0; i < layout.lanes.length; i++) {
        final laneIdx = i;
        children.add(Positioned(
          left: 0,
          right: 0,
          top: laneTops[laneIdx],
          height: layout.lanes[laneIdx].height,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (details) {
              final minutes = (details.localPosition.dx / _ppm).round();
              final time = dayStart.add(Duration(minutes: minutes));
              widget.onSlotTap!(widget.lanes[laneIdx], time);
            },
          ),
        ));
      }
    }

    // Events for this day. The controller pre-cuts multi-day events into
    // per-day chunks (CalendarData.addEvents), so each chunk's start/end
    // is already clipped to the day. Sub-row is looked up by uniqueId for
    // visual continuity across days.
    for (final e in dayEvents) {
      final laneIdx = layout.laneOfId[e.uniqueId];
      if (laneIdx == null) continue; // event has no matching lane
      final lane = layout.lanes[laneIdx];
      final subRow = lane.subRowById[e.uniqueId] ?? 0;
      final tileHeight = lane.eventTileHeight(widget.eventSpacing);

      final start = e.startTime;
      final end =
          e.endTime ?? start.add(const Duration(hours: 1));
      final left =
          start.difference(dayStart).inMinutes.clamp(0, 1440) * _ppm;
      var widthMin =
          end.difference(start).inMinutes.toDouble();
      // Guard against zero/negative durations (e.g. malformed full-day rows).
      if (widthMin <= 0) widthMin = e.isFullDay ? 1440.0 : 60.0;
      final width = widthMin * _ppm;
      final top = laneTops[laneIdx] +
          widget.eventSpacing +
          subRow * (tileHeight + widget.eventSpacing);

      children.add(Positioned(
        left: left.toDouble(),
        top: top,
        width: width < 2 ? 2 : width,
        height: tileHeight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onEventTap == null
              ? null
              : () => widget.onEventTap!(e),
          child: widget.eventBuilder?.call(e) ?? _defaultEventTile(e),
        ),
      ));
    }

    return SizedBox(
      width: dayWidth,
      height: totalHeight,
      child: Stack(children: children),
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
