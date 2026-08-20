import 'package:flutter/material.dart';

import '../../../../design_system/widgets/empty_state.dart';

class FormsScreen extends StatelessWidget {
  const FormsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: EmptyState(
        title: 'Forms',
        description: 'Coming soon. Manage your custom forms and templates here.',
        icon: Icons.description_outlined,
      ),
    );
  }
}
