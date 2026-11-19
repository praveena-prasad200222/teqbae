import '../constants/app_config.dart';
import 'office_location.dart';

class Employee {
  final String id;
  final String name;
  final String department;
  final String designation;
  final String email;
  final OfficeLocation office;

  const Employee({
    required this.id,
    required this.name,
    required this.department,
    required this.designation,
    required this.email,
    required this.office,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    final dynamic officeJson = json['office'];
    return Employee(
      id: (json['id'] as String?) ?? AppConfig.employeeId,
      name: (json['name'] as String?) ?? 'Employee',
      department: (json['department'] as String?) ?? 'Not specified',
      designation: (json['designation'] as String?) ?? 'Employee',
      email: (json['email'] as String?) ?? 'employee@example.com',
      office: officeJson is Map<String, dynamic>
          ? OfficeLocation.fromJson(officeJson)
          : OfficeLocation.fallback(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'department': department,
        'designation': designation,
        'email': email,
        'office': office.toJson(),
      };

  static Employee fallback() => Employee(
        id: AppConfig.employeeId,
        name: 'Aarav Sharma',
        department: 'Human Resources',
        designation: 'HR Executive',
        email: 'aarav.sharma@rebs.example',
        office: OfficeLocation.fallback(),
      );
}
