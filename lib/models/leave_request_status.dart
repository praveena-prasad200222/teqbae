enum LeaveRequestStatus { pending, approved, rejected }

extension LeaveRequestStatusX on LeaveRequestStatus {
  String get label => switch (this) {
        LeaveRequestStatus.pending => 'Pending',
        LeaveRequestStatus.approved => 'Approved',
        LeaveRequestStatus.rejected => 'Rejected',
      };

  String get jsonValue => name;

  static LeaveRequestStatus fromJson(String value) => switch (value) {
        'approved' => LeaveRequestStatus.approved,
        'rejected' => LeaveRequestStatus.rejected,
        _ => LeaveRequestStatus.pending,
      };
}
