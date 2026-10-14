// Unit tests for the per-deployment web storage name
// (lib/db/web_storage_name.dart).
//
// The canonical deployment set these names must serve:
// https://BenediktBurger.github.io/cycle-app/app/            -> cycle_storage
// https://BenediktBurger.github.io/cycle-app/branches/<slug>/ -> cycle_storage-<slug>
// everything else (flutter run on localhost, generic CI)      -> cycle_storage
import 'package:cycle_app/db/web_storage_name.dart';
import 'package:flutter_test/flutter_test.dart';

Uri pages(String path) => Uri.parse('https://BenediktBurger.github.io$path');

void main() {
  test('the released /app/ tier keeps the plain storage name', () {
    expect(webDatabaseName(pages('/cycle-app/app/')), 'cycle_storage');
  });

  test('app paths return the prefix byte-for-byte (data continuity)', () {
    // Whatever the prefix parameter is, an /app deployment opens exactly it —
    // appending anything here would break every existing user's data.
    expect(
      webDatabaseName(pages('/cycle-app/app/'), releasedPrefix: 'custom_name'),
      'custom_name',
    );
  });

  test('branch deployments get the slug appended to the prefix', () {
    expect(
      webDatabaseName(pages('/cycle-app/branches/main/')),
      'cycle_storage-main',
    );
    expect(
      webDatabaseName(
        pages('/cycle-app/branches/wt3-add-temperature-measurement/'),
      ),
      'cycle_storage-wt3-add-temperature-measurement',
    );
  });

  test('branch slugs are lowercased like the workflow sanitization', () {
    expect(
      webDatabaseName(pages('/cycle-app/branches/Feature-X/')),
      'cycle_storage-feature-x',
    );
  });

  test('trailing slashes do not change the result', () {
    expect(
      webDatabaseName(pages('/cycle-app/app')),
      webDatabaseName(pages('/cycle-app/app/')),
    );
    expect(
      webDatabaseName(pages('/cycle-app/branches/main')),
      webDatabaseName(pages('/cycle-app/branches/main/')),
    );
  });

  test('the local root and unrelated paths get the plain storage name', () {
    expect(
      webDatabaseName(Uri.parse('https://localhost:8000/')),
      'cycle_storage',
    );
    expect(
      webDatabaseName(Uri.parse('https://localhost:8000')),
      'cycle_storage',
    );
    expect(webDatabaseName(pages('/other/thing/')), 'cycle_storage');
  });

  test('a branch deploy never shares the release tier name', () {
    expect(
      webDatabaseName(pages('/cycle-app/branches/app/')),
      'cycle_storage-app',
    );
  });

  test(
    'a non-ASCII branch remainder fails loudly, with no silent fallback',
    () {
      expect(
        () => webDatabaseName(pages('/cycle-app/branches/gespräch/')),
        throwsArgumentError,
      );
      expect(
        () => webDatabaseName(pages('/cycle-app/branches/')),
        throwsArgumentError,
      );
    },
  );
}
