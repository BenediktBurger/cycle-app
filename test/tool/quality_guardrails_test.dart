// The guard-rail tools are pure decision logic, so their tests are plain
// fixtures: file text in, edge or status out.
import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_file_sizes.dart' as sizes;
import '../../tool/check_layering.dart' as layers;

void main() {
  group('layering resolution', () {
    test('relative imports resolve against the file', () {
      expect(
        layers.resolveTarget('lib/ui/diary.dart', '../db/mappers.dart'),
        'db',
      );
      expect(
        layers.resolveTarget('lib/domain/models.dart', 'models.dart'),
        'domain',
      );
    });

    test('package imports resolve into their layer', () {
      expect(
        layers.resolveTarget(
          'lib/domain/models.dart',
          'package:cycle_app/db/tables.dart',
        ),
        'db',
      );
      expect(
        layers.resolveTarget(
          'lib/domain/models.dart',
          'package:flutter/widgets.dart',
        ),
        'flutter',
      );
      expect(
        layers.resolveTarget('lib/domain/models.dart', 'dart:ui'),
        'dart:ui',
      );
    });

    test('a top-level lib file is the composition root', () {
      expect(
        layers.resolveTarget('lib/providers.dart', 'domain/models.dart'),
        'domain',
      );
      expect(
        layers.resolveTarget('lib/domain/models.dart', '../providers.dart'),
        'root',
      );
    });

    test('external packages are not app edges', () {
      expect(layers.resolveTarget('lib/domain/x.dart', 'dart:async'), isNull);
      expect(
        layers.resolveTarget('lib/domain/x.dart', 'package:drift/drift.dart'),
        isNull,
      );
    });
  });

  group('layering edges', () {
    test('every directive form is read with its line', () {
      final edges = layers.edgesIn('lib/ui/x.dart', [
        "import '../domain/a.dart';",
        'export "../db/b.dart";',
        "part 'cycle_chart.dart';",
        "// import '../pdf/ignored.dart';",
      ]);

      expect(edges.map((e) => e.to), ['domain', 'db', 'ui']);
      expect(edges.map((e) => e.line), [1, 2, 3]);
    });

    test('an upward edge fails unless allowlisted', () {
      final edges = [
        const layers.Edge('lib/domain/x.dart', 'db', 1),
        const layers.Edge('lib/ui/x.dart', 'db', 2),
        const layers.Edge('lib/ui/x.dart', 'domain', 3),
      ];

      expect(layers.violationsIn(edges, allowed: {}).map((e) => e.line), [
        1,
        2,
      ]);
      expect(
        layers
            .violationsIn(edges, allowed: {'lib/domain/x.dart|db'})
            .map((e) => e.line),
        [2],
      );
    });

    test('the composition root may import any layer', () {
      final edges = [const layers.Edge('lib/providers.dart', 'ui', 1)];
      expect(layers.violationsIn(edges, allowed: {}), isEmpty);
    });

    test('an allowlisted edge that disappeared is stale', () {
      final edges = [const layers.Edge('lib/domain/x.dart', 'db', 1)];
      expect(
        layers.staleAllowancesIn(
          edges,
          allowed: {'lib/domain/x.dart|db', 'lib/ui/gone.dart|db'},
        ),
        {'lib/ui/gone.dart|db'},
      );
    });
  });

  group('file size budget', () {
    test('below the warn line is clean', () {
      expect(
        sizes.classifySize('lib/x.dart', 700, allowance: {}),
        sizes.SizeStatus.ok,
      );
    });

    test('between warn and error warns only', () {
      expect(
        sizes.classifySize('lib/x.dart', 900, allowance: {}),
        sizes.SizeStatus.warning,
      );
    });

    test('past the error line fails', () {
      expect(
        sizes.classifySize('lib/x.dart', 1300, allowance: {}),
        sizes.SizeStatus.error,
      );
    });

    test('a grandfathered file may not grow past its allowance', () {
      expect(
        sizes.classifySize(
          'lib/big.dart',
          1500,
          allowance: {'lib/big.dart': 1500},
        ),
        sizes.SizeStatus.ok,
      );
      expect(
        sizes.classifySize(
          'lib/big.dart',
          1501,
          allowance: {'lib/big.dart': 1500},
        ),
        sizes.SizeStatus.error,
      );
    });

    test('an allowance under the warn line is stale', () {
      expect(
        sizes.classifySize(
          'lib/small.dart',
          700,
          allowance: {'lib/small.dart': 1500},
        ),
        sizes.SizeStatus.warning,
      );
    });

    test('an allowance far above the current size is stale', () {
      expect(
        sizes.classifySize(
          'lib/big.dart',
          1300,
          allowance: {'lib/big.dart': 1500},
        ),
        sizes.SizeStatus.warning,
      );
    });
  });
}
