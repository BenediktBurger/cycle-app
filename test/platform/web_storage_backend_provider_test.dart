import 'package:cycle_app/platform/web_storage_status.dart';
import 'package:cycle_app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('starts without a recorded backend and accepts the chosen one', () {
    final container = _container();

    expect(container.read(webStorageBackendProvider), isNull);

    container
        .read(webStorageBackendProvider.notifier)
        .set(WebStorageBackend.opfs);

    expect(container.read(webStorageBackendProvider), WebStorageBackend.opfs);
  });

  test(
    'keeps the recorded backend after its last listener goes away',
    () async {
      final container = _container();

      final subscription = container.listen(
        webStorageBackendProvider,
        (_, _) {},
      );
      final notifier = container.read(webStorageBackendProvider.notifier);
      notifier.set(WebStorageBackend.inMemory);
      subscription.close();

      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(webStorageBackendProvider),
        WebStorageBackend.inMemory,
      );
      expect(
        container.read(webStorageBackendProvider.notifier),
        same(notifier),
      );
    },
  );
}
