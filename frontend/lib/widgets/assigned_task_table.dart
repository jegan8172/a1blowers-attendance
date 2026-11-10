import 'package:flutter/material.dart';

import 'package:godigital_portal/core/constants/app_colors.dart';
import 'package:godigital_portal/core/constants/app_text_styles.dart';
import 'package:godigital_portal/core/widgets/status_badge.dart';
import 'package:godigital_portal/models/task_model.dart';

class AssignedTaskTable extends StatelessWidget {
  const AssignedTaskTable({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            height: 50,
            color: AppColors.lightBlue,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: const Row(
              children: [
                Text(
                  'Task Status',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                Spacer(),
                Text(
                  'View All',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _tableHeader(),
          ...demoTasks.map((task) => _taskRow(task)),
        ],
      ),
    );
  }

  Widget _tableHeader() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: const Row(
        children: [
          Expanded(
            flex: 2,
            child: Text('CLIENT', style: AppTextStyles.tableHeader),
          ),
          Expanded(
            flex: 2,
            child: Text('TASKS', style: AppTextStyles.tableHeader),
          ),
          Expanded(
            flex: 2,
            child: Text('TIME/DURATION', style: AppTextStyles.tableHeader),
          ),
          Expanded(
            flex: 2,
            child: Text('SUBMISSION\nDATE', style: AppTextStyles.tableHeader),
          ),
          Expanded(
            flex: 2,
            child: Text('ACTION', style: AppTextStyles.tableHeader),
          ),
          Expanded(
            flex: 1,
            child: Text('STATUS', style: AppTextStyles.tableHeader),
          ),
          SizedBox(width: 30),
        ],
      ),
    );
  }

  Widget _taskRow(TaskModel task) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(task.client, style: AppTextStyles.tableText),
          ),
          Expanded(
            flex: 2,
            child: Text(task.tasks, style: AppTextStyles.tableText),
          ),
          Expanded(
            flex: 2,
            child: Text(task.duration, style: AppTextStyles.tableText),
          ),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.submissionDate, style: AppTextStyles.tableText),
                if (task.dateLabel != null)
                  Text(
                    task.dateLabel!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: task.dateLabel!.contains('1')
                          ? AppColors.orange
                          : AppColors.green,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(text: task.action),
            ),
          ),
          Expanded(
            flex: 1,
            child: StatusBadge(text: task.status),
          ),
          const SizedBox(
            width: 30,
            child: Icon(
              Icons.more_vert,
              size: 16,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }
}