import '../utils/json_utils.dart';

/// An error returned by the Accord API (or generated client-side for transport
/// failures, where [code] is "INTERNAL").
class AccordError {
  String code;
  String message;

  AccordError({this.code = '', this.message = ''});

  factory AccordError.fromJson(Map<String, dynamic> d) {
    return AccordError(
      code: asString(d['code']),
      message: asString(d['message']),
    );
  }

  @override
  String toString() => 'AccordError(code: $code, message: $message)';
}
