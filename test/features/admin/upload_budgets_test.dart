import 'package:bonfire/features/admin/utils/upload_budgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The admin panel's upload budget fields (#330): the accepted ranges from
/// accordserver `docs/automod.md` and the MB <-> bytes conversion.
void main() {
  group('parseUploadRequestsPerMinute', () {
    test('accepts whole numbers from 1 to 600', () {
      expect(parseUploadRequestsPerMinute('1'), 1);
      expect(parseUploadRequestsPerMinute(' 6 '), 6);
      expect(parseUploadRequestsPerMinute('600'), 600);
    });

    test('rejects blank, non-numeric and out-of-range values', () {
      expect(parseUploadRequestsPerMinute(''), isNull);
      expect(parseUploadRequestsPerMinute('six'), isNull);
      expect(parseUploadRequestsPerMinute('6.5'), isNull);
      expect(parseUploadRequestsPerMinute('0'), isNull);
      expect(parseUploadRequestsPerMinute('-1'), isNull);
      expect(parseUploadRequestsPerMinute('601'), isNull);
    });

    test('the range matches the server contract', () {
      expect(kMinUploadRequestsPerMinute, 1);
      expect(kMaxUploadRequestsPerMinute, 600);
    });
  });

  group('parseUploadMbPerMinute', () {
    test('converts MB to bytes, decimals included', () {
      expect(parseUploadMbPerMinute('50'), 50 * 1024 * 1024);
      expect(parseUploadMbPerMinute('0.5'), 512 * 1024);
      expect(parseUploadMbPerMinute(' 1 '), 1024 * 1024);
    });

    test('accepts the whole server range, 1 byte to 1 TiB', () {
      // The smallest MB value that rounds to at least one byte.
      expect(parseUploadMbPerMinute('0.000001'), 1);
      expect(parseUploadMbPerMinute('1048576'), kMaxUploadBytesPerMinute);
      expect(kMaxUploadBytesPerMinute, 1099511627776);
    });

    test('rejects blank, non-numeric, zero, negative and oversize values', () {
      expect(parseUploadMbPerMinute(''), isNull);
      expect(parseUploadMbPerMinute('lots'), isNull);
      expect(parseUploadMbPerMinute('0'), isNull);
      expect(parseUploadMbPerMinute('-5'), isNull);
      expect(parseUploadMbPerMinute('NaN'), isNull);
      expect(parseUploadMbPerMinute('Infinity'), isNull);
      expect(parseUploadMbPerMinute('1048577'), isNull);
      expect(parseUploadMbPerMinute('1e30'), isNull);
    });
  });

  group('shouldSendUploadBudgets', () {
    test('false when the server never reported the keys', () {
      expect(
        shouldSendUploadBudgets(
          hasUploadBudgets: false,
          requestsText: '6',
          mbText: '50',
        ),
        isFalse,
      );
    });

    test(
        'false when the server reported the keys but neither is configured '
        'yet (e.g. sent as null)', () {
      expect(
        shouldSendUploadBudgets(
          hasUploadBudgets: true,
          requestsText: '',
          mbText: '  ',
        ),
        isFalse,
      );
    });

    test('true once either field has been given a value', () {
      expect(
        shouldSendUploadBudgets(
          hasUploadBudgets: true,
          requestsText: '6',
          mbText: '',
        ),
        isTrue,
      );
      expect(
        shouldSendUploadBudgets(
          hasUploadBudgets: true,
          requestsText: '',
          mbText: '50',
        ),
        isTrue,
      );
      expect(
        shouldSendUploadBudgets(
          hasUploadBudgets: true,
          requestsText: '6',
          mbText: '50',
        ),
        isTrue,
      );
    });
  });

  group('formatUploadMbPerMinute', () {
    test('round-trips the server default and fractions', () {
      expect(formatUploadMbPerMinute(52428800), '50');
      expect(formatUploadMbPerMinute(512 * 1024), '0.5');
      expect(formatUploadMbPerMinute(kMaxUploadBytesPerMinute), '1048576');
      expect(
        parseUploadMbPerMinute(formatUploadMbPerMinute(52428800)),
        52428800,
      );
    });

    test('keeps at most six decimals and round-trips a single byte', () {
      expect(formatUploadMbPerMinute(1), '0.000001');
      expect(parseUploadMbPerMinute(formatUploadMbPerMinute(1)), 1);
      expect(formatUploadMbPerMinute(12 * 1024 * 1024 + 256 * 1024), '12.25');
      expect(formatUploadMbPerMinute(1536 * 1024), '1.5');
    });
  });
}
