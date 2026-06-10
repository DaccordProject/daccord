import 'accord_rest.dart';

/// Base class for namespaced endpoint groups; holds the shared [AccordRest].
abstract class EndpointBase {
  final AccordRest rest;

  EndpointBase(this.rest);
}
