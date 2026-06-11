import 'dart:io';

/// Task 4 完整实现；本版本为可编译占位。
class Household {
  Household({required this.id, required this.saltBase64});

  final String id;
  final String saltBase64;
  int snapshotVersion = 0;
}

class HouseholdStore {
  HouseholdStore(this.dataDirectory);

  final Directory dataDirectory;

  Household? household(String? id) => null;

  Future<void> load() async {}

  Future<void> flush() async {}
}
