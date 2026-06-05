// Display-only username formatting. The stored/sent value always stays bare;
// this only prefixes an '@' for rendering in Text labels.

// Sentinel / system strings that represent something other than a real
// username (placeholders, the current user, etc.) and must NOT get an '@'.
const _atNameSentinels = {
  'you',
  'anonymous',
  '???',
  'someone',
  'a friend',
  'a runner',
  'the leader',
};

/// Returns the username prefixed with '@' for display.
///
/// Leaves the value unchanged when [name] is null/empty or when it is a
/// known sentinel/system string (case-insensitive). Pure and side-effect free.
String atName(String? name) {
  if (name == null) return '';
  final trimmed = name.trim();
  if (trimmed.isEmpty) return name;
  if (trimmed.startsWith('@')) return name;
  if (_atNameSentinels.contains(trimmed.toLowerCase())) return name;
  return '@$name';
}
