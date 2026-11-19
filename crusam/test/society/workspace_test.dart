import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crusam/features/society/core/workspace_memory.dart';
import 'package:crusam/features/society/society_routes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isSocietyLocation', () {
    test('identifies society root and subpaths', () {
      expect(isSocietyLocation('/society'), isTrue);
      expect(isSocietyLocation('/society/overview'), isTrue);
      expect(isSocietyLocation('/society/bills'), isTrue);
      expect(isSocietyLocation('/society/deep/nested/path'), isTrue);
    });

    test('rejects non-society locations and empty/null', () {
      expect(isSocietyLocation('/dashboard'), isFalse);
      expect(isSocietyLocation('/employees'), isFalse);
      expect(isSocietyLocation('/vouchers'), isFalse);
      expect(isSocietyLocation('/settings'), isFalse);
      expect(isSocietyLocation(''), isFalse);
      expect(isSocietyLocation(null), isFalse);
      expect(isSocietyLocation('/society-other'), isFalse);
    });
  });

  group('WorkspaceMemory', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      WorkspaceMemory.instance.resetForTest();
    });

    test('defaults to standard workspace landing paths', () {
      expect(
        WorkspaceMemory.instance.lastCrusamPath,
        WorkspaceMemory.defaultCrusamPath,
      );
      expect(
        WorkspaceMemory.instance.lastSocietyPath,
        WorkspaceMemory.defaultSocietyPath,
      );
    });

    test('records CruSam and Society locations independently', () {
      final memory = WorkspaceMemory.instance;

      memory.recordLocation('/employees');
      expect(memory.lastCrusamPath, '/employees');
      expect(memory.lastSocietyPath, WorkspaceMemory.defaultSocietyPath);

      memory.recordLocation('/society/units');
      expect(memory.lastCrusamPath, '/employees');
      expect(memory.lastSocietyPath, '/society/units');

      memory.recordLocation('/vouchers');
      expect(memory.lastCrusamPath, '/vouchers');
      expect(memory.lastSocietyPath, '/society/units');
    });

    test('strips query parameters from saved paths', () {
      final memory = WorkspaceMemory.instance;

      memory.recordLocation('/society/bills?filter=pending&sort=asc');
      expect(memory.lastSocietyPath, '/society/bills');

      memory.recordLocation('/dashboard?tab=analytics');
      expect(memory.lastCrusamPath, '/dashboard');
    });
  });

  group('societyRoutes & societyNavPaths', () {
    test('societyNavPaths contains all 35 sidebar routes', () {
      expect(societyNavPaths.length, 35);
      for (final path in societyNavPaths) {
        expect(isSocietyLocation(path), isTrue);
      }
    });

    test('every societyNavPath has a matching GoRoute in societyRoutes', () {
      final configuredPaths = <String>{};
      for (final route in societyRoutes) {
        if (route is GoRoute) {
          configuredPaths.add(route.path);
        }
      }

      for (final navPath in societyNavPaths) {
        expect(
          configuredPaths.contains(navPath),
          isTrue,
          reason: 'Missing route for sidebar path: $navPath',
        );
      }
    });
  });
}
