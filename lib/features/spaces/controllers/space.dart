import 'package:accordkit/accordkit.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'space.g.dart';

/// Per-space cache, keyed by space ID. The Accord analogue of Bonfire's
/// `GuildController`. Populated alongside [SpacesController] and updated by
/// space update gateway events.
@Riverpod(keepAlive: true)
class SpaceController extends _$SpaceController {
  @override
  AccordSpace? build(String spaceId) => null;

  void setSpace(AccordSpace space) => state = space;
}
