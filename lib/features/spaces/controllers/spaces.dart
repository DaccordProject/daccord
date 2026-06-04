import 'package:accordkit/accordkit.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'spaces.g.dart';

/// Holds the current user's space list — the left rail. Populated on gateway
/// ready (via `users.listSpaces()`) and kept in sync by space
/// create/update/delete gateway events. The Accord analogue of Bonfire's
/// `GuildsController`.
@Riverpod(keepAlive: true)
class SpacesController extends _$SpacesController {
  @override
  List<AccordSpace>? build() => null;

  void setSpaces(List<AccordSpace> spaces) => state = spaces;

  /// Inserts [space], or replaces it in place if already present.
  void upsertSpace(AccordSpace space) {
    final current = [...(state ?? const <AccordSpace>[])];
    final index = current.indexWhere((s) => s.id == space.id);
    if (index >= 0) {
      current[index] = space;
    } else {
      current.add(space);
    }
    state = current;
  }

  void removeSpace(String spaceId) {
    final current = state;
    if (current == null) return;
    state = current.where((s) => s.id != spaceId).toList();
  }
}
