import 'package:flutter/material.dart';

import '../styles.dart';
import '../utils/at_name.dart';

/// Number of friends a list must EXCEED before the search field appears.
///
/// A three-friend list is faster to scan than to type into, and a permanently
/// docked field costs a row of vertical space on every visit. Above this the
/// scroll becomes the slow path and the field earns its place.
const int kFriendSearchThreshold = 8;

/// Case-insensitive substring match on the discoverable real name, display
/// name, and its rendered '@handle', so typing what you can SEE on the row
/// works. A leading '@' the
/// user types is not meaningful on its own, so it is stripped before matching
/// (otherwise '@' alone would match everyone and '@ann' nothing).
///
/// An empty/whitespace query returns the list unchanged — the caller never has
/// to special-case "not searching".
List<Map<String, dynamic>> filterFriends(
  List<Map<String, dynamic>> friends,
  String query,
) {
  final needle = query.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();
  if (needle.isEmpty) return friends;
  return friends.where((f) {
    final discoverableName = f['discoverableName'];
    final displayName = f['displayName'];
    final realName = discoverableName is String
        ? discoverableName.toLowerCase()
        : '';
    final name = displayName is String ? displayName.toLowerCase() : '';
    final handle = atName(displayName is String ? displayName : null)
        .toLowerCase();
    return realName.contains(needle) ||
        name.contains(needle) ||
        handle.contains(needle);
  }).toList();
}

/// Parchment search field for friend lists — the same game-piece surface as
/// [RetroCard] (parchment fill, hard 2px border, offset drop shadow) so it
/// reads as another tile on the board rather than a form control dropped in
/// from Material.
///
/// Owns its [TextEditingController] and reports every keystroke through
/// [onChanged]; the parent keeps only the query string. Clearing is a real
/// button (not a hint) because the filtered state is otherwise indistinguishable
/// from a short friend list.
class FriendSearchField extends StatefulWidget {
  const FriendSearchField({
    super.key,
    required this.onChanged,
    this.hintText = 'Search friends',
  });

  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  State<FriendSearchField> createState() => _FriendSearchFieldState();
}

class _FriendSearchFieldState extends State<FriendSearchField> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    final has = value.isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
    widget.onChanged(value);
  }

  void _clear() {
    _controller.clear();
    _handleChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.parchment,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.roofDark.withValues(alpha: 0.55),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            offset: Offset(0, 3),
            blurRadius: 0,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: colors.textMid),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: _handleChanged,
              textInputAction: TextInputAction.search,
              style: PixelText.body(size: 15, color: colors.textDark),
              cursorColor: colors.textAccent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
                hintText: widget.hintText,
                hintStyle: PixelText.body(size: 15, color: colors.textMid),
              ),
            ),
          ),
          // Reserve the slot at all times so the field does not resize (and
          // shove the caret) on the first keystroke.
          SizedBox(
            width: 28,
            child: _hasText
                ? GestureDetector(
                    key: const Key('friend-search-clear'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _clear,
                    child: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: colors.textMid,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// Shown when a query matches nobody. Deliberately different in shape and
/// wording from a genuinely empty friend list: it names the query back to the
/// user so the fix (retype, or clear) is obvious.
class FriendSearchNoMatch extends StatelessWidget {
  const FriendSearchNoMatch({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 30,
            color: colors.textLight.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 10),
          Text(
            'No friends match "${query.trim()}"',
            textAlign: TextAlign.center,
            style: PixelText.title(size: 15, color: colors.textLight),
          ),
          const SizedBox(height: 6),
          Text(
            'Check the spelling, or clear the search to see everyone.',
            textAlign: TextAlign.center,
            style: PixelText.body(
              size: 13,
              color: colors.textLight.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}
