import 'package:flutter/material.dart';

const String defaultType = "default";

class Event {
  Event({
    this.columnIndex = 0,
    required this.startTime,
    this.endTime,
    this.isFullDay = false,
    this.title,
    this.description,
    this.data,
    this.eventType = defaultType,
    this.color = Colors.blue,
    this.textColor = Colors.white,
    this.daysIndex,
  }) {
    if (!isFullDay) {
      assert(endTime != null);
      assert(!endTime!.isBefore(startTime));
    } else if (endTime != null) {
      assert(!endTime!.isBefore(startTime));
    }
  }

  // generated unique id
  late UniqueKey uniqueId = UniqueKey();

  // column index in planner mode, 0 if not multiple column
  final int columnIndex;

  // event start time.
  // for full day event, set start of day
  final DateTime startTime;

  // event end time.
  // for full day event, set null
  // for multi days event, set dateTime of other day
  final DateTime? endTime;

  // full day event
  final bool isFullDay;

  // title showed in default event widget (can be overridden)
  final String? title;

  // description showed in default event widget (can be overridden)
  final String? description;

  // background color showed in default event widget (can be overridden)
  final Color color;

  // text color showed in default event widget (can be overridden)
  final Color textColor;

  // transported data for event
  final Object? data;

  // event type : generic object to easy manipulate event (arranger, widget...)
  final Object eventType;

  // multi days index
  final int? daysIndex;

  // effective start time for multi days events (startTime is for one day)
  DateTime? effectiveStartTime;

  // effective end time for multi days events (end is for one day)
  DateTime? effectiveEndTime;

  bool get isMultiDay => daysIndex != null;

  Event copyWith({
    final int? columnIndex,
    final DateTime? startTime,
    final DateTime? endTime,
    final bool? isFullDay,
    final String? title,
    final String? description,
    final Color? color,
    final Color? textColor,
    final Object? data,
    final Object? eventType,
    final int? daysIndex,
    final DateTime? effectiveStartTime,
    final DateTime? effectiveEndTime,
  }) {
    var event = Event(
      columnIndex: columnIndex ?? this.columnIndex,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isFullDay: isFullDay ?? this.isFullDay,
      title: title ?? this.title,
      description: description ?? this.description,
      color: color ?? this.color,
      textColor: textColor ?? this.textColor,
      data: data ?? this.data,
      eventType: eventType ?? this.eventType,
      daysIndex: daysIndex ?? this.daysIndex,
    );
    event.uniqueId = uniqueId;
    event.effectiveStartTime = effectiveStartTime ?? this.effectiveStartTime;
    event.effectiveEndTime = effectiveEndTime ?? this.effectiveEndTime;
    return event;
  }

  Duration? getDuration() {
    if (effectiveStartTime != null && effectiveEndTime != null) {
      return effectiveEndTime!.difference(effectiveStartTime!);
    }
    if (endTime != null) {
      return endTime!.difference(startTime);
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'columnIndex': columnIndex,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'isFullDay': isFullDay,
      'title': title,
      'description': description,
      'color': color.value,
      'textColor': textColor.value,
      'data': data,
      'eventType': eventType,
      'daysIndex': daysIndex,
    };
  }
}
