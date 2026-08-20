import 'package:flutter/material.dart';

import '../../../../design_system/widgets/empty_state.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: EmptyState(
        title: 'Profile Settings',
        description: 'Coming soon. Manage your account and preferences.',
        icon: Icons.person_outline,
      ),
    );
  }
}
