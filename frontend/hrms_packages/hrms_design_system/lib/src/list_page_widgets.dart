import 'package:flutter/material.dart';
import 'colors.dart';

/// Avatar + name + id stack, used as the leading cell of Approvals,
/// Payroll and Employees tables (and as mobile-card leading content).
class PersonCell extends StatelessWidget {
  final String name;
  final String id;
  final String? photoUrl;

  const PersonCell({super.key, required this.name, required this.id, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: HrmsColors.infoBg,
          backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
          child: photoUrl == null
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: HrmsColors.primary, fontWeight: FontWeight.w700),
                )
              : null,
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700, color: HrmsColors.primary)),
            Text(id, style: const TextStyle(fontSize: 12, color: HrmsColors.textMuted)),
          ],
        ),
      ],
    );
  }
}

/// "Showing X to Y of Z" + numbered page controls, used at the bottom of
/// Approvals/Payroll/Employees tables.
class PaginationBar extends StatelessWidget {
  final int shownFrom;
  final int shownTo;
  final int total;
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  const PaginationBar({
    super.key,
    required this.shownFrom,
    required this.shownTo,
    required this.total,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        Text(
          'Showing $shownFrom to $shownTo of $total',
          style: const TextStyle(color: HrmsColors.textSecondary, fontSize: 13),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _navButton(Icons.chevron_left, currentPage > 1, () => onPageChanged(currentPage - 1)),
            const SizedBox(width: 8),
            for (final p in _visiblePages()) ...[
              if (p == -1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('…', style: TextStyle(color: HrmsColors.textMuted)),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _pageChip(p),
                ),
            ],
            const SizedBox(width: 8),
            _navButton(Icons.chevron_right, currentPage < totalPages, () => onPageChanged(currentPage + 1)),
          ],
        ),
      ],
    );
  }

  List<int> _visiblePages() {
    if (totalPages <= 5) return List.generate(totalPages, (i) => i + 1);
    if (currentPage <= 3) return [1, 2, 3, -1, totalPages];
    if (currentPage >= totalPages - 2) {
      return [1, -1, totalPages - 2, totalPages - 1, totalPages];
    }
    return [1, -1, currentPage, -1, totalPages];
  }

  Widget _pageChip(int page) {
    final isActive = page == currentPage;
    return Material(
      color: isActive ? HrmsColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onPageChanged(page),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isActive ? HrmsColors.primary : HrmsColors.border),
          ),
          child: Text(
            '$page',
            style: TextStyle(
              color: isActive ? Colors.white : HrmsColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _navButton(IconData icon, bool enabled, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: HrmsColors.border),
          ),
          child: Icon(icon, size: 18, color: enabled ? HrmsColors.textPrimary : HrmsColors.textMuted),
        ),
      ),
    );
  }
}
