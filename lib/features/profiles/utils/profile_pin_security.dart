/// User-facing boundary for the optional profile PIN.
///
/// A PIN hides a profile inside Daccord, but it is not a cryptographic storage
/// boundary and must never be described as protecting data at rest.
const profilePinSecurityNotice =
    'Casual app lock only — profile data is not encrypted.';
