import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/business_day.dart';

/// The parts the Sales tab's lists share — Orders, Invoices and Cancelled
/// orders (`OrderHistoryScreen`) and Returns (`RefundsScreen`).
///
/// Lifted out of `order_history_screen.dart` when Returns became the second
/// list, rather than copied into it. Two copies of a filter chip are where
/// one list's borders start to differ from the other's, and two pagers are
/// where one of them stops saying "of 213".

/// How far back a list reaches.
///
/// Three fixed windows rather than a date picker. The question at a counter is
/// almost always "earlier today" and occasionally "last week"; a two-field date
/// range makes the common case slower to serve the rare one. An arbitrary range
/// belongs in Reports (Wave G), where somebody is sitting down.
enum HistoryRange { today, week, month }

extension HistoryRangeWindow on HistoryRange {
  String label(AppStrings s) => switch (this) {
    HistoryRange.today => s.orderHistoryToday,
    HistoryRange.week => s.orderHistoryLast7Days,
    HistoryRange.month => s.orderHistoryLast30Days,
  };

  /// Whole business dates, ending with [today]'s.
  ///
  /// [today] is the trading day, not the calendar one: at 1 a.m. with
  /// yesterday's business day still open, "Today" is yesterday's date, and the
  /// list shows the night that is still going rather than the hour since
  /// midnight. See `OrderHistoryQuery.from` for how a sale finds its date.
  (DateTime, DateTime) window(DateTime today) {
    final end = DateTime(today.year, today.month, today.day)
        .add(const Duration(days: 1));
    final days = switch (this) {
      HistoryRange.today => 1,
      HistoryRange.week => 7,
      HistoryRange.month => 30,
    };
    return (end.subtract(Duration(days: days)), end);
  }
}

/// The business date "Today" means: the open day's, when one is open, and
/// the calendar date of [openedAt] otherwise — which is also the date a row
/// with no business day is filed under, so the fallback agrees with itself.
DateTime historyToday(BusinessDay? day, DateTime openedAt) {
  if (day != null && day.isOpen) return day.date;
  return DateTime(openedAt.year, openedAt.month, openedAt.day);
}

String _two(int value) => value.toString().padLeft(2, '0');

/// 24-hour, zero-padded. Not `TimeOfDay.format` — that follows the locale
/// into 12-hour with an am/pm suffix, and a column of times that changes
/// width row by row cannot be scanned.
String historyTime(DateTime at) => '${_two(at.hour)}:${_two(at.minute)}';

/// `2026-09-14 13:05`: the date and the time, for a row the window may have
/// reached back a week for.
String historyStamp(DateTime at) =>
    '${at.year}-${_two(at.month)}-${_two(at.day)} ${historyTime(at)}';

/// A reason in the reader's language, falling back to the other one.
///
/// A restaurant that never filled in the Arabic name should still see the
/// English on an Arabic till — a blank where a reason belongs looks like a
/// void nobody gave a reason for, which is the opposite of the truth.
String? reasonInReaderLanguage(
  BuildContext context, {
  required String? english,
  required String? arabic,
}) {
  final rtl = Directionality.of(context) == TextDirection.rtl;
  final preferred = rtl ? arabic : english;
  final fallback = rtl ? english : arabic;
  final chosen = (preferred?.trim().isNotEmpty ?? false) ? preferred : fallback;
  return (chosen?.trim().isNotEmpty ?? false) ? chosen : null;
}

/// A thin upright rule between groups of filters.
class HistoryFilterDivider extends StatelessWidget {
  const HistoryFilterDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: PosSize.filterChip - 12, color: context.pos.line);
}

class HistoryFilterChip extends StatelessWidget {
  const HistoryFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return Material(
      color: selected ? pos.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: PosSize.filterChip,
          padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
          decoration: BoxDecoration(
            border: Border.fromBorderSide(
              selected ? pos.accentBorder : pos.resting,
            ),
          ),
          // A `Row` sized to its child, not `alignment: Alignment.center`. A
          // `Container` with an alignment expands to fill whatever it is given,
          // and inside a `Wrap` that is the full line width — every chip taking
          // a row of its own, and a filter bar 600px tall squeezing the list it
          // is meant to filter down to nothing. The first widget test written
          // against this screen caught it.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: PosText.ui(
                  size: 12.5,
                  weight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? pos.inkWarm : pos.body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The search box over a list: typed in mono, because what is typed into it
/// is an invoice number read off a receipt.
class HistorySearchField extends StatelessWidget {
  const HistorySearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.hint,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return SizedBox(
      // Wide enough for the longest hint in either language ("Invoice, table or
      // customer" / "رقم الفاتورة أو الطاولة أو العميل") without cutting it.
      width: 280,
      height: PosSize.filterChip,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        // **Fills the box.** A TextField is only as tall as its text unless it
        // is told to expand, so a SizedBox of the chips' height around a bare
        // one still drew a 25 px strip pinned to the top, beside 38 px chips.
        expands: true,
        minLines: null,
        maxLines: null,
        textAlignVertical: TextAlignVertical.center,
        style: PosText.mono(size: 13, color: pos.ink),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: PosText.ui(size: 13, color: pos.muted),
          contentPadding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: pos.resting,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: pos.resting,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: pos.accentBorder,
          ),
        ),
      ),
    );
  }
}

/// One figure over a list (BO-3).
///
/// Flat and bordered, not the mockup's tinted cards — the design system rules
/// pastel tiles out by name — and in the shape of the Users section's strip,
/// smaller: this sits over a list somebody at a counter is scanning, and the
/// figures are its caption, not the page.
class HistorySummaryTile extends StatelessWidget {
  const HistorySummaryTile({
    super.key,
    required this.label,
    required this.value,
    this.note,
  });

  final String label;
  final Widget value;
  final String? note;

  /// A figure not yet read, or not readable. The list under it says why when
  /// it cannot be read; the strip repeating it would not help.
  static Widget dash(PosPalette pos, Key key) => Text(
    '—',
    key: key,
    style: PosText.mono(size: 20, color: pos.muted, height: 1),
  );

  /// A count, in the strip's mono and left to right in either language.
  static Widget count(PosPalette pos, Key key, int value) => Text(
    '$value',
    key: key,
    textDirection: TextDirection.ltr,
    style: PosText.mono(
      size: 20,
      weight: FontWeight.w600,
      color: pos.ink,
      height: 1,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.md,
        vertical: PosSpace.sm,
      ),
      decoration: BoxDecoration(
        color: pos.surface,
        border: Border.fromBorderSide(pos.resting),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MicroLabel(label),
          const SizedBox(height: PosSpace.xs),
          // Shrunk to fit rather than cut. At 1100 a tile is about 160 wide
          // and a seven-figure amount in 20pt mono is wider; an ellipsis on a
          // sum of money hides the digits that matter.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: value,
          ),
          const SizedBox(height: PosSpace.xs),
          // Always a line, empty when there is nothing to say, so the tiles
          // stay one height and their figures one baseline.
          Text(
            note ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PosText.ui(size: 11.5, color: pos.muted),
          ),
        ],
      ),
    );
  }
}

/// "Showing 51–100 of 213", and Previous and Next when there is more than one
/// page — the cloud's pager (`OrdersView.vue`), over keyset pages.
///
/// Words and figures are separate widgets, never one interpolated sentence:
/// each figure is its own left-to-right run, so in Arabic the line reads
/// عرض 51–100 من 213 from the right with every number the right way round.
class HistoryPager extends StatelessWidget {
  const HistoryPager({
    super.key,
    required this.first,
    required this.last,
    required this.total,
    required this.page,
    required this.pages,
    required this.onPrevious,
    required this.onNext,
  });

  static const barKey = ValueKey('history-pager');
  static const rangeKey = ValueKey('history-pager-range');
  static const totalKey = ValueKey('history-pager-total');
  static const pageKey = ValueKey('history-pager-page');
  static const previousKey = ValueKey('history-page-previous');
  static const nextKey = ValueKey('history-page-next');

  final int first;
  final int last;

  /// Null until the summary is read.
  final int? total;
  final int page;
  final int? pages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// Rows [limit] at a time: whether there is a page after this one, whose
  /// [length] rows follow [offset] others. A short page is the last whatever
  /// the count says. A full one is the last when [total] says so; with no
  /// count yet, Next is offered and an empty page after it is the honest
  /// answer.
  static bool hasNext({
    required int length,
    required int limit,
    required int offset,
    required int? total,
  }) => length >= limit && (total == null || offset + length < total);

  /// How many pages [total] rows make, [limit] to a page; at least one.
  static int? pagesOf(int? total, int limit) =>
      total == null ? null : math.max(1, (total + limit - 1) ~/ limit);

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    final strings = context.strings;
    final words = PosText.ui(size: 12.5, color: pos.muted);
    final figure = PosText.mono(
      size: 12.5,
      weight: FontWeight.w600,
      color: pos.ink,
    );
    Widget mono(Key key, String text) =>
        Text(text, key: key, textDirection: TextDirection.ltr, style: figure);

    return Container(
      key: barKey,
      height: PosSize.filterChip + PosSpace.md,
      padding: const EdgeInsetsDirectional.only(
        start: PosSpace.s18,
        end: PosSpace.md,
      ),
      decoration: BoxDecoration(
        color: pos.surface,
        border: BorderDirectional(top: pos.resting),
      ),
      child: Row(
        children: [
          Text(strings.orderPagerShowing, style: words),
          const SizedBox(width: PosSpace.xs),
          mono(rangeKey, last == 0 ? '0' : '$first–$last'),
          const SizedBox(width: PosSpace.xs),
          Text(strings.orderPagerOf, style: words),
          const SizedBox(width: PosSpace.xs),
          mono(totalKey, total == null ? '—' : '$total'),
          const Spacer(),
          // Only with somewhere to go, as on the cloud. Two dead buttons
          // under a list of twelve read as a list that failed to load more.
          if (onPrevious != null || onNext != null) ...[
            PosButton(
              key: previousKey,
              label: strings.orderPagerPrevious,
              height: PosSize.filterChip,
              border: Border.fromBorderSide(pos.resting),
              onPressed: onPrevious,
            ),
            const SizedBox(width: PosSpace.sm),
            mono(pageKey, pages == null ? '$page' : '$page / $pages'),
            const SizedBox(width: PosSpace.sm),
            PosButton(
              key: nextKey,
              label: strings.orderPagerNext,
              height: PosSize.filterChip,
              border: Border.fromBorderSide(pos.resting),
              onPressed: onNext,
            ),
          ],
        ],
      ),
    );
  }
}

/// The headings and the rows, as one block that scrolls sideways when the
/// list is too narrow for it rather than squeezing.
///
/// At the window's minimum (1024, `main.dart`) the list beside the detail
/// pane is about 600 wide and its fixed columns alone are wider: a Row that
/// ran out of room, on `/orders` as much as in the back office. Rejected:
/// dropping columns below a width. The column somebody needs is the one
/// that was dropped, and a table whose columns come and go with the window
/// is two tables to learn.
class HistoryTable extends StatelessWidget {
  const HistoryTable({
    super.key,
    required this.minWidth,
    required this.sideways,
    required this.sidewaysKey,
    required this.headings,
    required this.rows,
  });

  /// The row at its narrowest — each list's own arithmetic over its widths.
  final double minWidth;

  /// Owned by the screen, which disposes it.
  final ScrollController sideways;
  final Key sidewaysKey;
  final Widget headings;
  final Widget rows;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = math.max(box.maxWidth, minWidth);
      final table = SizedBox(
        width: width,
        height: box.maxHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [headings, Expanded(child: rows)],
        ),
      );
      if (width <= box.maxWidth) return table;
      // A bar that is always drawn, because a desktop scroll view shows none
      // sideways of its own, and a table with columns past the edge and
      // nothing saying so reads as a table with fewer columns.
      return Scrollbar(
        controller: sideways,
        thumbVisibility: true,
        radius: Radius.zero,
        child: SingleChildScrollView(
          key: sidewaysKey,
          controller: sideways,
          scrollDirection: Axis.horizontal,
          child: table,
        ),
      );
    },
  );
}

/// The band of column headings over a list's rows, padded as the rows are so
/// each heading stands over its column.
class HistoryHeadings extends StatelessWidget {
  const HistoryHeadings({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    height: 28,
    padding: const EdgeInsetsDirectional.only(
      start: PosSpace.s18,
      end: PosSpace.md,
    ),
    decoration: BoxDecoration(
      border: BorderDirectional(
        top: context.pos.hairline,
        bottom: context.pos.hairline,
      ),
    ),
    child: Row(children: children),
  );
}

/// One row of a list: the height, the rule under it, and selection drawn as
/// the accent on its start edge.
class HistoryListRow extends StatelessWidget {
  const HistoryListRow({
    super.key,
    required this.selected,
    required this.onTap,
    required this.children,
  });

  final bool selected;
  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final pos = context.pos;
    return Material(
      color: selected ? pos.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: PosSize.reportRow,
          padding: const EdgeInsetsDirectional.only(
            start: PosSpace.s18,
            end: PosSpace.md,
          ),
          decoration: BoxDecoration(
            border: BorderDirectional(
              bottom: pos.hairline,
              start: selected
                  ? BorderSide(color: pos.accent, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: Row(children: children),
        ),
      ),
    );
  }
}

/// What a list says instead of rows: empty, or unreadable with the reason.
class HistoryMessage extends StatelessWidget {
  const HistoryMessage({
    super.key,
    required this.message,
    this.detail,
    this.action,
  });

  final String message;

  /// The error itself, not a generic apology. "History could not be read"
  /// with the reason underneath is what lets somebody tell a dead network
  /// apart from a permissions problem without opening a log.
  final String? detail;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(PosSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: PosText.ui(size: 14, color: context.pos.muted),
          ),
          if (detail case final detail?) ...[
            const SizedBox(height: PosSpace.sm),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: PosText.ui(size: 12.5, color: context.pos.muted),
            ),
          ],
          if (action case (final label, final onPressed)?) ...[
            const SizedBox(height: PosSpace.md),
            PosButton(
              label: label,
              border: Border.fromBorderSide(context.pos.resting),
              onPressed: onPressed,
            ),
          ],
        ],
      ),
    ),
  );
}
