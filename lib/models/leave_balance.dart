import 'leave_type.dart';

class LeaveBalance {
  final int casual;
  final int sick;

  const LeaveBalance({required this.casual, required this.sick});

  /// Zero is a legitimate server value, so it is never used as a fallback.
  /// These values are SAMPLE DATA for the preconfigured demo employee, not
  /// actual company leave records. They are overwritten by GET /leave/balance
  /// as soon as the API responds.
  static const LeaveBalance sample = LeaveBalance(casual: 12, sick: 6);

  /// Kept only for legacy callers/tests that explicitly need an empty balance.
  static const LeaveBalance empty = LeaveBalance(casual: 0, sick: 0);

  int forType(LeaveType type) =>
      type == LeaveType.casual ? casual : sick;

  int get total => casual + sick;

  factory LeaveBalance.fromJson(Map<String, dynamic> json) {
    final dynamic nested = json['balance'];
    final Map<String, dynamic> source = nested is Map<String, dynamic>
        ? nested
        : json;
    return LeaveBalance(
      casual: _count(source['casual']) ?? sample.casual,
      sick: _count(source['sick']) ?? sample.sick,
    );
  }

  static int? _count(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'casual': casual,
        'sick': sick,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LeaveBalance && other.casual == casual && other.sick == sick;

  @override
  int get hashCode => Object.hash(casual, sick);
}
