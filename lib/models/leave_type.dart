enum LeaveType { casual, sick }

extension LeaveTypeX on LeaveType {
  String get label => this == LeaveType.casual ? 'Casual' : 'Sick';

  String get jsonValue => name;

  static LeaveType fromJson(String value) =>
      value == 'sick' ? LeaveType.sick : LeaveType.casual;
}
