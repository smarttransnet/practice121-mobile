import 'package:flutter/material.dart';

import '../../../../design_system/widgets/empty_state.dart';

class PatientsScreen extends StatelessWidget {
  const PatientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: EmptyState(
        title: 'Patients Directory',
        description: 'Coming soon. Here you will see a list of all your patients.',
        icon: Icons.people_alt_outlined,
      ),
    );
  }
}
