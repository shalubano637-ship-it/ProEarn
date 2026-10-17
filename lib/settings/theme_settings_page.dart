import 'package:flutter/material.dart';
import '../theme/theme.dart';
import '../theme/theme_controller.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appThemeController,
      builder: (context, _) {
        final dark = appThemeController.mode == ThemeMode.dark;
        return Scaffold(
          appBar: AppBar(title: const Text('Themes')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Choose your app appearance',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Only one theme can be active at a time. Light theme is the default.',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
              ),
              const SizedBox(height: 18),
              _themeTile(
                context,
                icon: Icons.light_mode_outlined,
                title: 'Light Theme',
                subtitle: 'Bright interface',
                selected: !dark,
                onChanged: (value) {
                  if (value) appThemeController.setMode(ThemeMode.light);
                },
              ),
              const SizedBox(height: 10),
              _themeTile(
                context,
                icon: Icons.dark_mode_outlined,
                title: 'Dark Theme',
                subtitle: 'Dark interface',
                selected: dark,
                onChanged: (value) {
                  if (value) appThemeController.setMode(ThemeMode.dark);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _themeTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
        ),
      ),
      child: SwitchListTile(
        secondary: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        value: selected,
        onChanged: onChanged,
      ),
    );
  }
}
