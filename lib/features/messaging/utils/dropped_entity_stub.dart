/// Web has no filesystem to inspect, and its `desktop_drop` implementation
/// already reports a dropped folder as a `DropItemDirectory`, so the caller's
/// type check catches it before this is consulted.
bool isDroppedDirectory(String path) => false;
