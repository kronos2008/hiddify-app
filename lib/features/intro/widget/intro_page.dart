import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/common/general_pref_tiles.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/widget/preference_tile.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class IntroPage extends HookConsumerWidget {
  const IntroPage({super.key});

  static bool locationInfoLoaded = false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final isStarting = useState(false);

    if (!locationInfoLoaded) {
      autoSelectRegion(ref);
      locationInfoLoaded = true;
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth > 400 ? 400 : constraints.maxWidth;
                    final size = width * 0.4;
                    return Assets.images.logo.svg(width: size, height: size);
                  },
                ),
                const Gap(16),

                /// 🔥 ТВОЙ ТЕКСТ
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    "Все что вам нужно для безопасного интернета",
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ),

                const Gap(24),

                const LocalePrefTile(),

                ChoicePreferenceWidget(
                  selected: ref.watch(ConfigOptions.region),
                  preferences: ref.watch(ConfigOptions.region.notifier),
                  choices: Region.values,
                  title: t.pages.settings.routing.region,
                  showFlag: true,
                  icon: Icons.place_rounded,
                  presentChoice: (value) => value.present(t),
                  onChanged: (val) async {
                    await ref.read(ConfigOptions.directDnsAddress.notifier).reset();
                  },
                ),

                const EnableAnalyticsPrefTile(),

                const Gap(40),

                /// ❌ УДАЛЕН HIDDIFY БЛОК
              ],
            ),
          ),
        ),
      ),

      floatingActionButton: FloatingActionButton.extended(
        icon: isStarting.value
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
            : const Icon(Icons.rocket_launch),
        label: Text("Начать", style: theme.textTheme.titleMedium),
        onPressed: () async {
          if (isStarting.value) return;
          isStarting.value = true;

          if (!ref.read(analyticsControllerProvider).requireValue) {
            try {
              await ref.read(analyticsControllerProvider.notifier).disableAnalytics();
            } catch (_) {}
          }

          await ref.read(Preferences.introCompleted.notifier).update(true);
        },
      ),
    );
  }

  Future<void> autoSelectRegion(WidgetRef ref) async {
    try {
      final DioHttpClient client = DioHttpClient(
        timeout: const Duration(seconds: 2),
        userAgent: "TrueVPN",
        debug: true,
      );

      final response = await client.get<Map<String, dynamic>>(
        'https://api.ip.sb/geoip/',
      );

      if (response.statusCode == 200) {
        final jsonData = response.data!;
        final country = jsonData['country_code']?.toString() ?? "US";

        Region region = Region.other;

        switch (country) {
          case "RU":
            region = Region.ru;
            break;
          case "CN":
            region = Region.cn;
            break;
          case "IR":
            region = Region.ir;
            break;
        }

        await ref.read(ConfigOptions.region.notifier).update(region);
      }
    } catch (_) {}
  }
}
