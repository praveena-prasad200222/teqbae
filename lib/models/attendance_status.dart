enum AttendanceStatus { notCheckedIn, checkedIn, checkedOut }

extension AttendanceStatusX on AttendanceStatus {
  String get label => switch (this) {
        AttendanceStatus.notCheckedIn => 'Not Checked In',
        AttendanceStatus.checkedIn => 'Checked In',
        AttendanceStatus.checkedOut => 'Checked Out',
      };
}
