import 'package:flutter/material.dart';

import '../l10n/s.dart';
import '../settings/definitions/bottom_nav_defs.dart';
import '../widgets/settings/settings_group_page.dart';

class BottomNavSettingsPage extends StatelessWidget {
  final String? highlightId;

  const BottomNavSettingsPage({super.key, this.highlightId});

  @override
  Widget build(BuildContext context) {
    return SettingsGroupPage(
      title: context.l10n.bottomNav_title,
      groupsBuilder: buildBottomNavGroups,
      highlightId: highlightId,
    );
  }
}
