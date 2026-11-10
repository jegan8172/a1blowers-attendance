import 'package:flutter/material.dart';
import '../layouts/admin_layout.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      pageTitle: "Dashboard",
      currentRoute: "/admin",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          const Text(
                      "Welcome Admin",
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),

          const SizedBox(height: 6),

          const Text(
            "Here is an overview of today's GoDigital priorities and performance metrics.",
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
            ),
          ),

          const SizedBox(height: 28),


        // ── Stat Cards ───────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.people_alt_rounded,
                  headerColor: const Color(0xFF2A52BE),
                  label: 'Total Clients',
                  value: '1,284',
                  bottom: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.trending_up, size: 14, color: Color(0xFF22C55E)),
                      SizedBox(width: 4),
                      Text(
                        '12% ',
                        style: TextStyle(fontSize: 12, color: Color(0xFF22C55E), fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'vs last month',
                        style: TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _StatCard(
                  icon: Icons.groups_rounded,
                  headerColor: const Color(0xFF16A34A),
                  label: 'Active Client',
                  value: '432',
                  bottom: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.sync, size: 14, color: Color(0xFF475569)),
                      SizedBox(width: 6),
                      Text(
                        'Running normally',
                        style: TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _StatCard(
                  icon: Icons.assignment_late_outlined,
                  headerColor: const Color(0xFFE67E00), // Clean orange
                  label: 'Client Pending Task',
                  value: '56',
                  bottom: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB91C1C), // Deep crimson red tag
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Requires Attention',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _StatCard(
                  icon: Icons.cancel_outlined,
                  headerColor: const Color(0xFFE10000), // Bright red
                  label: 'In Active Clients',
                  value: '12',
                  bottom: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.arrow_downward, size: 14, color: Color(0xFFB91C1C)),
                      SizedBox(width: 4),
                      Text(
                        'Reduced by 4%',
                        style: TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),



                Container(
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: const Color(0xFFE5E7EB)),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // ── Table Header Banner ──
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        color: const Color(0xFFF1F5F9), // Light background header matching mockup
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Employee Status",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            GestureDetector(
              onTap: () {},
              child: const Text(
                "View All",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
          ],
        ),
      ),

      // ── Precise Styled Data Table ──
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Theme(
          // Adjust layout styling to clean out the default borders and density
          data: Theme.of(context).copyWith(
            dividerColor: const Color(0xFFF1F5F9),
          ),
          child: DataTable(
            headingTextStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF475569),
              letterSpacing: 0.5,
            ),
            dataTextStyle: const TextStyle(
              fontSize: 13,
              color: Color(0xFF334155),
            ),
            columns: const [
              DataColumn(label: Text("CLIENT")),
              DataColumn(label: Text("EMPLOYEE NAME")),
              DataColumn(label: Text("TASKS")),
              DataColumn(label: Text("TIME/DURATION")),
              DataColumn(label: Text("PRIORITY")),
              DataColumn(label: Text("DUE DATE")),
              DataColumn(label: Text("STATUS")),
            ],
            rows: [
              // Row 1: GA MALL
              DataRow(cells: [
                const DataCell(Text("GA MALL")),
                DataCell(_buildEmployeeAvatar("PC", "Pavithra C")),
                const DataCell(Text("Website")),
                const DataCell(Text("1 Week")),
                DataCell(_buildPriorityBadge("HIGH", const Color(0xFFFFE4E6), const Color(0xFFEF4444))),
                DataCell(_buildDueDateCell("27 May 2026", "2 Days Left", const Color(0xFF22C55E))),
                DataCell(_buildStatusBadge("ON HOLD", const Color(0xFFE2E8F0), const Color(0xFF64748B))),
              ]),
              // Row 2: JYOTHI
              DataRow(cells: [
                const DataCell(Text("JYOTHI")),
                DataCell(_buildEmployeeAvatar("SS", "Susan")),
                const DataCell(Text("Instagram Ads")),
                const DataCell(Text("1 Month")),
                DataCell(_buildPriorityBadge("MEDIUM", const Color(0xFFFEF3C7), const Color(0xFFD97706))),
                DataCell(_buildDueDateCell("30 May 2026", "5 Days Left", const Color(0xFF22C55E))),
                DataCell(_buildStatusBadge("IN PROGRESS", const Color(0xFFDBEAFE), const Color(0xFF2563EB))),
              ]),
              // Row 3: BRAHMOS (Arun)
              DataRow(cells: [
                const DataCell(Text("BRAHMOS")),
                DataCell(_buildEmployeeAvatar("AD", "Arun")),
                const DataCell(Text("Meta Ads")),
                const DataCell(Text("1 Month")),
                DataCell(_buildPriorityBadge("URGENT", const Color(0xFFFFE4E6), const Color(0xFFEF4444))),
                DataCell(_buildDueDateCell("27 May 2026", "2 Days Left", const Color(0xFF22C55E))),
                DataCell(_buildStatusBadge("REVIEW", const Color(0xFFF3E8FF), const Color(0xFF9333EA))),
              ]),
              // Row 4: BRAHMOS Duplicate Row
              DataRow(cells: [
                const DataCell(Text("BRAHMOS")),
                DataCell(_buildEmployeeAvatar("AD", "Arun")),
                const DataCell(Text("Meta Ads")),
                const DataCell(Text("1 Month")),
                DataCell(_buildPriorityBadge("URGENT", const Color(0xFFFFE4E6), const Color(0xFFEF4444))),
                DataCell(_buildDueDateCell("27 May 2026", "2 Days Left", const Color(0xFF22C55E))),
                DataCell(_buildStatusBadge("REVIEW", const Color(0xFFF3E8FF), const Color(0xFF9333EA))),
              ]),
            ],
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

Widget _StatCard({
    required IconData icon,
    required Color headerColor,
    required String label,
    required String value,
    required Widget bottom,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFDBE5F5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Padding container separating the colored header from the outer edges
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: Row(
              children: [
                // Icon block container
                Container(
                  width: 44,
                  height: 44,
                  color: headerColor,
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 8),
                // Expanded banner displaying text cleanly centered
                Expanded(
                  child: Container(
                    height: 44,
                    color: headerColor,
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Central numeric data text metrics
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111C24),
                letterSpacing: -0.5,
              ),
            ),
          ),

          // Bottom alignment metadata section
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SizedBox(
              height: 24,
              child: Center(child: bottom),
            ),
          ),
        ],
      ),
    );
  }



  // 1. Builds Avatar initials combined with string labels
Widget _buildEmployeeAvatar(String initials, String name) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircleAvatar(
        radius: 12,
        backgroundColor: const Color(0xFFDBEAFE),
        child: Text(
          initials,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
        ),
      ),
      const SizedBox(width: 8),
      Text(name),
    ],
  );
}

// 2. Builds Flat Priority Text Chips
Widget _buildPriorityBadge(String text, Color bgColor, Color textColor) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor),
    ),
  );
}

// 3. Multi-line Due Date with subtext counters
Widget _buildDueDateCell(String date, String remaining, Color statusColor) {
  return Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(date, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
      const SizedBox(height: 2),
      Text(
        remaining,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
      ),
    ],
  );
}

// 4. Builds Wide Status Text Chips
Widget _buildStatusBadge(String status, Color bgColor, Color textColor) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      status,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor),
    ),
  );
}

}