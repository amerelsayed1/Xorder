import '../../core/money/money.dart';

enum TableState {
  /// No open visit. Tile is `surface` with a 1px lineStrong border.
  free,

  /// An open bill. Tile is `accentSoft` with a 2px accent border.
  open,

  /// The diner asked for the bill. Tile is `dangerSoft` with a 2px danger border.
  billAsked,
}

/// A table on the floor screen.
class DiningTable {
  const DiningTable({
    required this.id,
    required this.label,
    required this.seats,
    this.state = TableState.free,
    this.openLineCount = 0,
    this.openTotal,
    this.areaName,
  });

  final int id;
  final String label;
  final int seats;
  final TableState state;
  final int openLineCount;
  final Money? openTotal;
  final String? areaName;

  bool get isFree => state == TableState.free;
}
