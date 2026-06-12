import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/developer/services/mcp_tools.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Provider that exposes a McpTools backed by a real ProviderContainer Ref.
/// Handlers that call the network will return {'error': 'Not connected'} because
/// no AccordAuthLoggedIn state is present; pure handlers work without setup.
final _toolsProvider = Provider<McpTools>((ref) => McpTools(ref));

void main() {
  late ProviderContainer container;
  late McpTools tools;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    tools = container.read(_toolsProvider);
  });

  // ── tool registration ────────────────────────────────────────────────────

  group('tool registration', () {
    test('list_roles is registered in the read group', () {
      final t = tools.tools['list_roles'];
      expect(t, isNotNull);
      expect(t!.group, 'read');
    });

    test('list_permissions is registered in the read group', () {
      final t = tools.tools['list_permissions'];
      expect(t, isNotNull);
      expect(t!.group, 'read');
    });

    test('create_role is registered in the manage group', () {
      final t = tools.tools['create_role'];
      expect(t, isNotNull);
      expect(t!.group, 'manage');
    });

    test('update_role is registered in the manage group', () {
      final t = tools.tools['update_role'];
      expect(t, isNotNull);
      expect(t!.group, 'manage');
    });

    test('delete_role is registered in the manage group', () {
      final t = tools.tools['delete_role'];
      expect(t, isNotNull);
      expect(t!.group, 'manage');
    });

    test('add_member_role is registered in the manage group', () {
      final t = tools.tools['add_member_role'];
      expect(t, isNotNull);
      expect(t!.group, 'manage');
    });

    test('remove_member_role is registered in the manage group', () {
      final t = tools.tools['remove_member_role'];
      expect(t, isNotNull);
      expect(t!.group, 'manage');
    });

    test('list_channel_permissions is registered in the manage group', () {
      final t = tools.tools['list_channel_permissions'];
      expect(t, isNotNull);
      expect(t!.group, 'manage');
    });

    test('set_channel_permission is registered in the manage group', () {
      final t = tools.tools['set_channel_permission'];
      expect(t, isNotNull);
      expect(t!.group, 'manage');
    });

    test('delete_channel_permission is registered in the manage group', () {
      final t = tools.tools['delete_channel_permission'];
      expect(t, isNotNull);
      expect(t!.group, 'manage');
    });

    test('list_roles schema requires space_id', () {
      final schema = tools.tools['list_roles']!.inputSchema;
      expect((schema['required'] as List), contains('space_id'));
    });

    test('set_channel_permission schema requires channel_id, target_id, target_type', () {
      final schema = tools.tools['set_channel_permission']!.inputSchema;
      final required = schema['required'] as List;
      expect(required, containsAll(['channel_id', 'target_id', 'target_type']));
    });
  });

  // ── list_permissions handler ──────────────────────────────────────────────

  group('list_permissions', () {
    late Map<String, dynamic> result;

    setUp(() async {
      result = await tools.tools['list_permissions']!.handler({});
    });

    test('returns ok: true', () {
      expect(result['ok'], isTrue);
    });

    test('returns a non-empty permissions list', () {
      final perms = result['permissions'] as List;
      expect(perms, isNotEmpty);
    });

    test('every entry has an id and description', () {
      final perms = result['permissions'] as List;
      for (final p in perms) {
        final m = p as Map;
        expect(m['id'], isA<String>());
        expect((m['id'] as String), isNotEmpty);
        expect(m['description'], isA<String>());
        expect((m['description'] as String), isNotEmpty);
      }
    });

    test('includes known permissions', () {
      final perms = result['permissions'] as List;
      final ids = perms.map((p) => (p as Map)['id'] as String).toSet();
      expect(ids, containsAll([
        AccordPermission.administrator,
        AccordPermission.sendMessages,
        AccordPermission.manageRoles,
        AccordPermission.viewChannel,
      ]));
    });

    test('count matches AccordPermission.all()', () {
      final perms = result['permissions'] as List;
      expect(perms.length, AccordPermission.all().length);
    });
  });

  // ── update_role validation ────────────────────────────────────────────────

  group('update_role validation', () {
    test('returns error when name is empty string', () async {
      final result = await tools.tools['update_role']!.handler({
        'space_id': 'space-1',
        'role_id': 'role-1',
        'name': '',
      });
      expect(result['error'], contains('empty'));
      expect(result.containsKey('ok'), isFalse);
    });

    test('returns no-fields error without hitting client', () async {
      // With no optional fields, returns 'No fields to update' before
      // touching the client.
      final result = await tools.tools['update_role']!.handler({
        'space_id': 'space-1',
        'role_id': 'role-1',
      });
      expect(result['error'], 'No fields to update');
    });
  });

  // ── set_channel_permission validation ────────────────────────────────────

  group('set_channel_permission', () {
    test('rejects invalid target_type', () async {
      final result = await tools.tools['set_channel_permission']!.handler({
        'channel_id': 'chan-1',
        'target_id': 'target-1',
        'target_type': 'user',
      });
      expect(result['error'], contains('"role" or "member"'));
    });

    test('rejects empty target_type', () async {
      final result = await tools.tools['set_channel_permission']!.handler({
        'channel_id': 'chan-1',
        'target_id': 'target-1',
        'target_type': '',
      });
      expect(result['error'], isNotNull);
    });
  });

  // ── manage tools return not-connected without a client ───────────────────

  group('network tools without a client', () {
    for (final toolName in [
      'list_roles',
      'create_role',
      'delete_role',
      'add_member_role',
      'remove_member_role',
      'list_channel_permissions',
      'delete_channel_permission',
    ]) {
      test('$toolName returns not-connected', () async {
        final args = <String, dynamic>{
          'space_id': 's',
          'role_id': 'r',
          'user_id': 'u',
          'channel_id': 'c',
          'target_id': 't',
        };
        final result = await tools.tools[toolName]!.handler(args);
        expect(result['error'], 'Not connected');
      });
    }
  });
}
