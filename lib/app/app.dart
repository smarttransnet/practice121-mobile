import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/presentation/controllers/auth_controller.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class Practice121App extends ConsumerStatefulWidget {
  const Practice121App({super.key});

  @override
  ConsumerState<Practice121App> createState() => _Practice121AppState();
}

class _Practice121AppState extends ConsumerState<Practice121App> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(authControllerProvider.notifier).initializeSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Practice121',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
