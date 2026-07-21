import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/back_or_home_button.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/map/presentation/map_screen.dart';
import '../../features/navigation/presentation/route_planner_screen.dart';
import '../../features/onboarding/presentation/onboarding.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

/// URL is the source of truth: every screen is restorable from its route
/// alone (deep links, and the future web build, come free).
final appRouterProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    // First run goes to onboarding; ref.read keeps this current per
    // navigation without rebuilding the router.
    redirect: (context, state) {
      final onboarded = ref.read(onboardedProvider);
      if (!onboarded && state.matchedLocation != '/onboarding') {
        return '/onboarding';
      }
      if (onboarded && state.matchedLocation == '/onboarding') {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/plan',
        builder: (context, state) => RoutePlannerScreen(
          initialDestinationRoomId: state.uri.queryParameters['dest'],
          initialFromRoomId: state.uri.queryParameters['from'],
        ),
      ),
      GoRoute(
        path: '/map',
        builder: (context, state) => MapScreen(
          focusRoomId: state.uri.queryParameters['room'],
        ),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(
        leading: const BackOrHomeButton(),
        title: const Text('Not found'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wrong_location_outlined, size: 56),
              const SizedBox(height: 12),
              Text(
                "This page doesn't exist:\n${state.uri}",
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
