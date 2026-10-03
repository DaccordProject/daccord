import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/experiences/views/arcade_game_artwork.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:flutter/material.dart';

typedef ArcadeLobbyChoice = ({bool inviteOnly, List<String> invited});

class ArcadeLobbySetup extends StatefulWidget {
  const ArcadeLobbySetup({
    super.key,
    required this.client,
    required this.spaceId,
    required this.currentUserId,
    required this.game,
  });
  final AccordClient client;
  final String spaceId;
  final String? currentUserId;
  final AccordExperienceManifest game;
  @override
  State<ArcadeLobbySetup> createState() => _ArcadeLobbySetupState();
}

class _ArcadeLobbySetupState extends State<ArcadeLobbySetup> {
  bool _private = false;
  bool _loading = false;
  String? _error;
  List<AccordMember> _members = [];
  final Map<String, AccordMember> _selected = {};
  Timer? _debounce;
  int _generation = 0;

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    super.dispose();
  }

  void _setPrivate(bool value) {
    if (value == _private) return;
    _debounce?.cancel();
    _generation++;
    setState(() {
      _private = value;
      _loading = false;
    });
    if (value) unawaited(_search(''));
  }

  Future<void> _search(String query) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = query.trim().isEmpty
          ? await widget.client.members.list(
              widget.spaceId,
              query: {'limit': 25},
              withUser: true,
            )
          : await widget.client.members.search(
              widget.spaceId,
              query.trim(),
              query: {'limit': 25, 'with_user': true},
            );
      if (!result.ok) {
        throw StateError(result.errorMessageOr('Could not load members.'));
      }
      final members = (result.data as List).cast<AccordMember>();
      for (final member in members.where((m) => m.user == null)) {
        final user = await widget.client.users.fetch(member.userId);
        if (user.ok) member.user = user.data as AccordUser?;
      }
      if (!mounted || generation != _generation) return;
      setState(
        () => _members = members
            .where((m) => m.userId != widget.currentUserId)
            .toList(),
      );
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(
          () =>
              _error = e is StateError ? e.message : 'Could not load members.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: ArcadeGameArtwork(gameId: widget.game.id, radius: 8),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text('${widget.game.name} lobby')),
      ],
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Your name will appear on the lobby so friends can find you.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  avatar: const Icon(Icons.public, size: 18),
                  label: const Text('Open'),
                  selected: !_private,
                  onSelected: (_) => _setPrivate(false),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.lock_outline, size: 18),
                  label: const Text('Invite-only'),
                  selected: _private,
                  onSelected: (_) => _setPrivate(true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _private
                  ? 'Only you and the members you choose can see this lobby.'
                  : 'Everyone in this community can find and join your lobby.',
            ),
            if (_private) ...[
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search username or nickname',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (query) {
                  _debounce?.cancel();
                  _generation++; // Do not show a response to an older search.
                  _debounce = Timer(
                    const Duration(milliseconds: 250),
                    () => _search(query),
                  );
                },
              ),
              if (_selected.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final member in _selected.values)
                        InputChip(
                          label: Text(
                            accordMemberName(member, fallback: 'Player'),
                          ),
                          onDeleted: () =>
                              setState(() => _selected.remove(member.userId)),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              SizedBox(
                height: 180,
                child: _members.isEmpty && !_loading
                    ? const Center(child: Text('No members found'))
                    : ListView(
                        children: [
                          for (final member in _members)
                            CheckboxListTile(
                              dense: true,
                              title: Text(
                                accordMemberName(member, fallback: 'Player'),
                              ),
                              subtitle: member.user?.username.isNotEmpty == true
                                  ? Text('@${member.user!.username}')
                                  : null,
                              value: _selected.containsKey(member.userId),
                              onChanged: (selected) => setState(() {
                                if (selected == true) {
                                  _selected[member.userId] = member;
                                } else {
                                  _selected.remove(member.userId);
                                }
                              }),
                            ),
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _private && _selected.isEmpty
            ? null
            : () => Navigator.pop<ArcadeLobbyChoice>(context, (
                inviteOnly: _private,
                invited: _private ? _selected.keys.toList() : <String>[],
              )),
        child: const Text('Create lobby'),
      ),
    ],
  );
}
