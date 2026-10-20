import 'package:flutter/material.dart';
import 'package:hrms_design_system/hrms_design_system.dart';

const _gridLine = Color(0xFFE2E8F2);

/// One day's attendance mark, matching the enum values in hrms_models'
/// AttendanceStatus (kept as short display codes here: P/A/L/E/U/HL/OFF).
class AttendanceDayMark {
  final String code; // P, A, L, E, U, LV, HL, OFF
  const AttendanceDayMark(this.code);

  Color get color {
    switch (code) {
      case 'P':
        return HrmsColors.success;
      case 'A':
        return HrmsColors.danger;
      case 'L':
        return HrmsColors.warning;
      case 'E':
        return HrmsColors.info;
      case 'U':
        return HrmsColors.accentPurple;
      case 'HL':
      case 'EL':
      case 'LV':
        return HrmsColors.accentPurple;
      default:
        return HrmsColors.textMuted; // OFF
    }
  }
}

class AttendanceRowData {
  final String name;
  final String designation;
  final List<AttendanceDayMark> days;
  final int present;
  final int absent;
  final String absentDeduction;
  final int late;
  final int excused;
  final int unexcused;
  final int halfLeave;
  final int earnedLeave;
  final int approvedLeave;
  final String salaryPerMonth;
  final String totalSalaryAfterLeaves;
  final String updatedSalary;

  const AttendanceRowData({
    required this.name,
    required this.designation,
    required this.days,
    required this.present,
    required this.absent,
    required this.absentDeduction,
    required this.late,
    required this.excused,
    required this.unexcused,
    required this.halfLeave,
    required this.earnedLeave,
    required this.approvedLeave,
    required this.salaryPerMonth,
    required this.totalSalaryAfterLeaves,
    required this.updatedSalary,
  });
}

/// Attendance grid sized to its available width.
class AttendanceGrid extends StatefulWidget {
  final List<int> days; // e.g. 1..31
  final List<String> dayLabels; // e.g. Fri, Sat, Sun...
  final List<AttendanceRowData> rows;
  final bool showSummary;
  final bool expanded;
  final VoidCallback? onToggleExpanded;
  final Widget? toolbarLeading;

  const AttendanceGrid({
    super.key,
    required this.days,
    required this.dayLabels,
    required this.rows,
    this.showSummary = true,
    this.expanded = false,
    this.onToggleExpanded,
    this.toolbarLeading,
  });

  @override
  State<AttendanceGrid> createState() => _AttendanceGridState();
}

class _AttendanceGridState extends State<AttendanceGrid> {
  static const int _daysPerWindow = 7;
  // The dashboard is intentionally dense. These logical dimensions are
  // calibrated for common 125% desktop scaling while retaining readable rows.
  static const double _rowHeight = 34;
  static const double _headerHeight = 48;
  static const double _dayColWidth = 70;
  // Match the compact three-column lead-in used by the attendance sheet:
  // row number, employee, then designation. The calendar remains the focus.
  static const double _designationWidth = 82;
  static const double _frozenWidth = 40 + 142 + _designationWidth;
  static const _summaryWidths = [
    44.0,
    44.0,
    44.0,
    48.0,
    48.0,
    58.0,
    60.0,
    54.0,
  ];
  int _windowStart = 0;

  int get _windowEnd => widget.showSummary
      ? (_windowStart + _daysPerWindow).clamp(0, widget.days.length)
      : widget.days.length;

  List<int> get _visibleDayIndexes => List<int>.generate(
    _windowEnd - (widget.showSummary ? _windowStart : 0),
    (index) => (widget.showSummary ? _windowStart : 0) + index,
  );

  int get _lastWindowStart => (widget.days.length - _daysPerWindow)
      .clamp(0, widget.days.length)
      .toInt();

  @override
  void didUpdateWidget(covariant AttendanceGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_windowStart > _lastWindowStart) _windowStart = _lastWindowStart;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final summaryWidth = widget.showSummary
            ? _summaryWidths.reduce((a, b) => a + b)
            : 0.0;
        final visibleIndexes = _visibleDayIndexes;
        final minWidth = _frozenWidth + summaryWidth + visibleIndexes.length * _dayColWidth;
        final tableWidth = constraints.maxWidth;
        final scale = minWidth > 0 ? tableWidth / minWidth : 1.0;
        final colWidth = _dayColWidth * scale;
        final calendarHeader = _calendarHeaderRow(colWidth);
        final calendarBody = _calendarBodyColumn(colWidth);

        final tableBody = IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _frozenBodyColumn(scale),
              calendarBody,
              if (widget.showSummary) _summaryBodyColumn(scale),
            ],
          ),
        );

        final table = SizedBox(
          width: tableWidth,
          child: Column(
            mainAxisSize: widget.expanded ? MainAxisSize.min : MainAxisSize.max,
            children: [
              SizedBox(
                height: _headerHeight,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _frozenHeaderRow(scale), calendarHeader,
                  if (widget.showSummary) _summaryHeaderRow(scale),
                ]),
              ),
              if (widget.expanded) tableBody else Expanded(child: SingleChildScrollView(child: tableBody)),
            ],
          ),
        );
        return Column(
          mainAxisSize: widget.expanded ? MainAxisSize.min : MainAxisSize.max,
          children: [
            _dayWindowNavigator(),
            if (widget.expanded) table else Expanded(child: table),
          ],
        );
      },
    );
  }

  Widget _dayWindowNavigator() {
    if (!widget.showSummary) {
      return Container(
        height: 44,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: const Border(bottom: BorderSide(color: _gridLine)),
        ),
        child: _scrollableToolbar(Row(children: [
          if (widget.toolbarLeading != null) widget.toolbarLeading!,
          const Spacer(),
          Text('All ${widget.days.length} days', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w800)),
          const Spacer(),
        ])),
      );
    }
    final hasPrevious = _windowStart > 0;
    final hasNext = _windowEnd < widget.days.length;
    final firstDay = widget.days.isEmpty ? 0 : widget.days[_windowStart];
    final lastDay = widget.days.isEmpty ? 0 : widget.days[_windowEnd - 1];
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: const Border(bottom: BorderSide(color: _gridLine)),
      ),
      child: _scrollableToolbar(Row(
        children: [
          if (widget.toolbarLeading != null) widget.toolbarLeading!,
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous 7 days',
                onPressed: hasPrevious
                    ? () => setState(() {
                        _windowStart = (_windowStart - _daysPerWindow).clamp(
                          0,
                          widget.days.length,
                        );
                      })
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text(
                'Days $firstDay–$lastDay of ${widget.days.length}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              IconButton(
                tooltip: 'Next 7 days',
                onPressed: hasNext
                    ? () => setState(() {
                        _windowStart = (_windowStart + _daysPerWindow)
                            .clamp(0, _lastWindowStart)
                            .toInt();
                      })
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const Spacer(),
          if (widget.onToggleExpanded != null)
            TextButton.icon(
              onPressed: widget.onToggleExpanded,
              icon: Icon(
                widget.expanded
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
                size: 17,
              ),
              label: Text(widget.expanded ? 'Collapse list' : 'Expand list'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1769E0),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      )),
    );
  }

  Widget _scrollableToolbar(Widget child) => LayoutBuilder(
    builder: (context, constraints) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: SizedBox(width: constraints.maxWidth < 760 && widget.toolbarLeading != null ? 760 : constraints.maxWidth, child: child),
    ),
  );

  Widget _frozenHeaderRow(double scale) => SizedBox(
    width: _frozenWidth * scale,
    child: Row(
      children: [
        _HeaderCell(text: '#', width: 40 * scale),
        _HeaderCell(text: 'Employee Name', width: 142 * scale),
        _HeaderCell(text: 'Designation', width: _designationWidth * scale),
      ],
    ),
  );

  Widget _frozenBodyColumn(double scale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in widget.rows.indexed)
          SizedBox(
            height: _rowHeight,
            width: _frozenWidth * scale,
            child: Row(
              children: [
                _BodyCell(
                  width: 40 * scale,
                  child: Text(
                    '${entry.$1 + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                _BodyCell(
                  width: 142 * scale,
                  child: Text(
                    entry.$2.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 12,
                    ),
                  ),
                ),
                _BodyCell(
                  width: _designationWidth * scale,
                  child: Text(
                    entry.$2.designation,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _calendarHeaderRow(double colWidth) {
    final visibleIndexes = _visibleDayIndexes;
    final dayColsWidth = visibleIndexes.length * colWidth;
    return SizedBox(
      width: dayColsWidth,
      child: Row(
        children: [
          for (final index in visibleIndexes)
            _HeaderCell(
              width: colWidth,
              text: '${widget.days[index]}\n${widget.dayLabels[index]}',
              dense: true,
            ),
        ],
      ),
    );
  }

  Widget _calendarBodyColumn(double colWidth) {
    final visibleIndexes = _visibleDayIndexes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in widget.rows)
          SizedBox(
            height: _rowHeight,
            child: Row(
              children: [
                for (final index in visibleIndexes)
                  _BodyCell(
                    width: colWidth,
                    child: _MarkChip(
                      mark: index < row.days.length
                          ? row.days[index]
                          : const AttendanceDayMark(''),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  static const _summaryLabels = [
    'Present',
    'Late',
    'Leave',
    'Half\nLeave',
    'Earned\nLeave',
    'Salary\nPer\nMonth',
    'Absent\nDeduction',
    'Updated\nSalary',
  ];
  static const _summaryColors = [
    HrmsColors.success,
    HrmsColors.warning,
    HrmsColors.accentPurple,
    HrmsColors.accentPurple,
    HrmsColors.info,
    Color(0xFF07186F),
    HrmsColors.danger,
    Color(0xFF07186F),
  ];
  static const _summaryPanelWidth = 400.0;

  Widget _summaryHeaderRow(double scale) => SizedBox(
    width: _summaryPanelWidth * scale,
    child: Row(
      children: [
        for (var i = 0; i < _summaryLabels.length; i++)
          _HeaderCell(
            width: _summaryWidths[i] * scale,
            text: _summaryLabels[i],
            dense: true,
            color: i == 5 || i == 7 ? Theme.of(context).colorScheme.onSurface : _summaryColors[i],
          ),
      ],
    ),
  );

  Widget _summaryBodyColumn(double scale) {
    return Column(
      children: [
        for (final row in widget.rows)
          SizedBox(
            height: _rowHeight,
            width: _summaryPanelWidth * scale,
            child: Row(
              children: [
                _BodyCell(
                  width: _summaryWidths[0] * scale,
                  child: Center(
                    child: _statText('${row.present}', HrmsColors.success),
                  ),
                ),
                _BodyCell(
                  width: _summaryWidths[1] * scale,
                  child: Center(
                    child: _statText('${row.late}', HrmsColors.warning),
                  ),
                ),
                _BodyCell(
                  width: _summaryWidths[2] * scale,
                  child: Center(
                    child: _statText(
                      '${row.approvedLeave}',
                      HrmsColors.accentPurple,
                    ),
                  ),
                ),
                _BodyCell(
                  width: _summaryWidths[3] * scale,
                  child: Center(
                    child: _statText(
                      '${row.halfLeave}',
                      HrmsColors.accentPurple,
                    ),
                  ),
                ),
                _BodyCell(
                  width: _summaryWidths[4] * scale,
                  child: Center(
                    child: _statText('${row.earnedLeave}', HrmsColors.info),
                  ),
                ),
                _BodyCell(
                  width: _summaryWidths[5] * scale,
                  child: Center(
                    child: Text(
                      row.salaryPerMonth,
                      maxLines: 1,
                      style: _moneyStyle.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                ),
                _BodyCell(
                  width: _summaryWidths[6] * scale,
                  child: Center(
                    child: Text(
                      '${row.absent} ${row.absentDeduction}',
                      maxLines: 1,
                      style: _moneyStyle.copyWith(color: HrmsColors.danger),
                    ),
                  ),
                ),
                _BodyCell(
                  width: _summaryWidths[7] * scale,
                  child: Center(
                    child: Text(
                      row.updatedSalary,
                      maxLines: 1,
                      style: _moneyStyle.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _statText(String value, Color color) {
    return Text(
      value,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    );
  }

  static const _moneyStyle = TextStyle(
    color: Color(0xFF07186F),
    fontSize: 10,
    fontWeight: FontWeight.w600,
  );
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final double width;
  final bool dense;
  final Color? color;

  const _HeaderCell({
    required this.text,
    required this.width,
    this.dense = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          right: BorderSide(color: Theme.of(context).colorScheme.outline, width: .7),
          bottom: BorderSide(color: Theme.of(context).colorScheme.outline, width: .7),
        ),
      ),
      child: FittedBox(fit: BoxFit.scaleDown, child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: dense ? 9 : 10,
          color: color ?? Theme.of(context).colorScheme.onSurface,
        ),
      )),
    );
  }
}

class _BodyCell extends StatelessWidget {
  final Widget child;
  final double width;

  const _BodyCell({required this.child, required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).colorScheme.outline, width: .7),
          bottom: BorderSide(color: Theme.of(context).colorScheme.outline, width: .7),
        ),
      ),
      child: child is _MarkChip
          ? child
          : FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.center, child: child),
    );
  }
}

class _MarkChip extends StatelessWidget {
  final AttendanceDayMark mark;
  const _MarkChip({required this.mark});

  @override
  Widget build(BuildContext context) {
    final code = mark.code;
    final label = switch (code) {
      'LV' => 'L',
      'OFF' => 'WO',
      _ => code,
    };
    final baseColor = mark.color;
    final hasMark = code.isNotEmpty;

    return Center(
      child: Container(
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hasMark
              ? baseColor.withValues(alpha: code == 'OFF' ? .16 : .18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: hasMark ? baseColor : Colors.transparent,
            fontWeight: FontWeight.w800,
            fontSize: code == 'OFF' ? 9 : 10,
          ),
        ),
      ),
    );
  }
}
