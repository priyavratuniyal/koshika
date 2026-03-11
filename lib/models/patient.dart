import 'package:objectbox/objectbox.dart';

/// Represents a patient/user profile.
/// For MVP, we support a single default patient,
/// but the schema is ready for multi-profile support.
@Entity()
class Patient {
  @Id()
  int id;

  String name;

  @Property(type: PropertyType.date)
  DateTime? dateOfBirth;

  /// 'M', 'F', or 'O' (other)
  String? sex;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  Patient({
    this.id = 0,
    required this.name,
    this.dateOfBirth,
    this.sex,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
