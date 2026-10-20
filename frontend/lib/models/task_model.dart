class TaskModel {
  final String client;
  final String tasks;
  final String duration;
  final String submissionDate;
  final String action;
  final String status;
  final String? dateLabel;

  TaskModel({
    required this.client,
    required this.tasks,
    required this.duration,
    required this.submissionDate,
    required this.action,
    required this.status,
    this.dateLabel,
  });
}

final List<TaskModel> demoTasks = [
  TaskModel(
    client: 'GA MALL',
    tasks: '12/12 Poster',
    duration: '1 Month',
    submissionDate: '01 June 2026',
    action: 'SUBMITTED',
    status: 'REVIEW',
  ),
  TaskModel(
    client: 'JYOTHI',
    tasks: '12/12 Poster',
    duration: '1 Month',
    submissionDate: '01 June 2026',
    action: 'SUBMITTED',
    status: 'REVIEW',
  ),
  TaskModel(
    client: 'BRAHMOS',
    tasks: '8/12 Poster',
    duration: '1 Month',
    submissionDate: '02 June 2026',
    dateLabel: '1 Days Left',
    action: 'ON HOLD',
    status: '-',
  ),
  TaskModel(
    client: 'EUROKIDS',
    tasks: '6/12 Poster',
    duration: '1 Month',
    submissionDate: '03 June 2026',
    dateLabel: '2 Days Left',
    action: 'IN PROGRESS',
    status: '-',
  ),
];