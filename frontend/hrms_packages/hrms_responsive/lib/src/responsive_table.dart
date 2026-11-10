import 'package:flutter/material.dart';
import 'breakpoints.dart';

/// One column definition for [ResponsiveTable].
class ResponsiveColumn<T> {
  final String label;
  final Widget Function(T item) cellBuilder;

  /// Whether this column still shows on the mobile card (as a labeled row).
  /// Set false for columns better represented by [ResponsiveTable.cardLeading]
  /// or [ResponsiveTable.cardTrailing] instead.
  final bool showOnCard;

  const ResponsiveColumn({
    required this.label,
    required this.cellBuilder,
    this.showOnCard = true,
  });
}

/// Renders [items] as a DataTable on tablet/desktop and as a stack of
/// cards on mobile, per HRMS_PROJECT_BLUEPRINT.md, Section 3:
/// "Ordinary tables become cards below 600px."
///
/// This is for plain listing tables (Employees, Payroll, Approvals rows).
/// The Admin Dashboard attendance grid is a different, always-scrollable
/// grid with frozen columns — see AttendanceGrid instead.
class ResponsiveTable<T> extends StatelessWidget {
  final List<ResponsiveColumn<T>> columns;
  final List<T> items;

  /// Optional widget shown at the top of each mobile card (e.g. avatar +
  /// name), replacing the need to repeat that column in the card body.
  final Widget Function(T item)? cardLeading;

  /// Optional widget shown at the top-right of each mobile card (e.g. a
  /// status badge or action menu).
  final Widget Function(T item)? cardTrailing;

  const ResponsiveTable({
    super.key,
    required this.columns,
    required this.items,
    this.cardLeading,
    this.cardTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = Breakpoints.isMobile(constraints.maxWidth);
        return isMobile ? _buildCards(context) : _buildTable(context);
      },
    );
  }

  Widget _buildTable(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.transparent),
        columns: columns.map((c) => DataColumn(label: Text(c.label))).toList(),
        rows: items
            .map(
              (item) => DataRow(
                cells: columns.map((c) => DataCell(c.cellBuilder(item))).toList(),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildCards(BuildContext context) {
    return Column(
      children: items.map((item) {
        final cardColumns = columns.where((c) => c.showOnCard).toList();
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (cardLeading != null || cardTrailing != null)
                  Row(
                    children: [
                      if (cardLeading != null) Expanded(child: cardLeading!(item)),
                      if (cardTrailing != null) cardTrailing!(item),
                    ],
                  ),
                if (cardLeading != null || cardTrailing != null)
                  const Padding(padding: EdgeInsets.only(top: 12)),
                for (final c in cardColumns)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 110,
                          child: Text(
                            c.label,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Expanded(child: c.cellBuilder(item)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
