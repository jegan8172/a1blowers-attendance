enum EmployeeRole {
  designer,
  pageHandler, 
  adsHandler,
  videographer,
}

extension EmployeeRoleExtension on EmployeeRole {
  String get title {
    switch (this) {
      case EmployeeRole.designer:
        return 'Designer';
      case EmployeeRole.pageHandler:
        return 'Page Handler';
      case EmployeeRole.adsHandler:
        return 'Ads Handler';
      case EmployeeRole.videographer:
        return 'Videographer';
    }
  }

  String get employeeName {
    switch (this) {
      case EmployeeRole.designer:
        return 'Designer';
      case EmployeeRole.pageHandler:
        return 'Arun';
      case EmployeeRole.adsHandler:
        return 'Susan';
      case EmployeeRole.videographer:
        return 'Susheel';
    }
  }

  String get shortName {
    switch (this) {
      case EmployeeRole.designer:
        return 'D';
      case EmployeeRole.pageHandler:
        return 'PH';
      case EmployeeRole.adsHandler:
        return 'AH';
      case EmployeeRole.videographer:
        return 'VG';
    }
  }

  // List<String> get menuItems {
  //   switch (this) {
  //     case EmployeeRole.designer:
  //       return [
  //         'Dashboard',
  //         'Day Planner',
  //         'Assigned Task',
  //         'Live Tracking Tasks',
  //         'Task Status',
  //         'Notifications',
  //       ];

  //     case EmployeeRole.pageHandler:
  //       return [
  //         'Dashboard',
  //         'Day Planner',
  //         // 'Daily Reports',
  //         'Assigned Task',
  //         'Live Tracking Tasks',
  //         'Task Planner',
  //         'Task Review',
  //         'Notifications',
  //         'Feedback',
  //       ];

  //     case EmployeeRole.adsHandler:
  //       return [
  //         'Dashboard',
  //         'Day Planner',
  //         // 'Daily Reports',
  //         'Assigned Task',
  //         'Live Tracking Tasks',
  //         'Task Planner',
  //         'Task Review',
  //         'Notifications',
  //         'Feedback',
  //       ];

  //     case EmployeeRole.videographer:
  //       return [
  //         'Dashboard',
  //         'Day Planner',
  //         'Assigned Task',
  //         'Live Tracking Tasks',
  //         'Task Status',
  //         'Video Task Planner',
  //         'Notifications',
  //       ];
  //   }
  // }

  // employee_role.dart file-la menuItems extension-ai ipadi update pannikonga:
  List<String> get menuItems {
    return [
      'Dashboard',
      'Day Planner',
      'Assigned Task',
      'Live Tracking Tasks',
      'Daily Reports',
      'Task Planner',
      'Task Planner History',
      'Video Task Planner',
      'Video Task Planner History',
      'Task Review',
      'Task Status',
      'Chat',
      'Feedback',
      'Feedback History',
    ];
  }

}