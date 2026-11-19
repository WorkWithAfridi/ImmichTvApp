import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/core/models/asset_summary.dart';
import 'package:immichtv/src/core/models/memory_summary.dart';

void main() {
  test('maps a yearly memory into a readable title and age', () {
    final memory = MemorySummary.fromJson(
      const {
        'id': 'memory-1',
        'type': 'ON_THIS_DAY',
        'memoryAt': '2023-11-19T10:00:00.000Z',
        'data': {'year': 2023},
      },
      assets: [_asset('a')],
      now: DateTime.utc(2026, 11, 19),
    );

    expect(memory.title, '2023');
    expect(memory.subtitle, '3 years ago');
    expect(memory.isBirthday, isFalse);
  });

  test('maps birthday memories using the person name', () {
    final memory = MemorySummary.fromJson(
      const {
        'id': 'memory-2',
        'type': 'BIRTHDAY',
        'memoryAt': '2025-11-19T10:00:00.000Z',
        'data': {'year': 2025, 'personName': 'Avery'},
      },
      assets: [_asset('a'), _asset('b')],
      now: DateTime.utc(2026, 11, 19),
    );

    expect(memory.title, "Avery's birthday");
    expect(memory.subtitle, 'One year ago');
    expect(memory.isBirthday, isTrue);
    expect(memory.assets, hasLength(2));
  });

  test('tolerates partial payloads', () {
    final memory = MemorySummary.fromJson(
      const {'id': 'memory-3'},
      assets: const [],
      now: DateTime.utc(2026),
    );

    expect(memory.title, 'On this day');
    expect(memory.subtitle, 'A moment to remember');
    expect(memory.assets, isEmpty);
  });
}

AssetSummary _asset(String id) {
  return AssetSummary(
    id: id,
    thumbnailUrls: ['https://example.test/$id/thumbnail'],
    displayUrls: ['https://example.test/$id/original'],
    type: 'IMAGE',
    createdAt: DateTime.utc(2023, 11, 19),
  );
}
