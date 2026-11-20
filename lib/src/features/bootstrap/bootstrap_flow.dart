import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../shared/presentation/app_colors.dart';
import '../../shared/presentation/app_scale.dart';
import '../../shared/presentation/widgets/ambient_background.dart';
import '../../shared/presentation/widgets/immich_logo.dart';

class BootstrapFlow extends StatefulWidget {
  const BootstrapFlow({super.key});

  @override
  State<BootstrapFlow> createState() => _BootstrapFlowState();
}

class _BootstrapFlowState extends State<BootstrapFlow> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _visible = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = AppScale.of(context);
    final versionTextStyle = GoogleFonts.inter(
      color: Colors.white.withValues(alpha: 0.62),
      fontSize: scale.text(14, min: 12, max: 16),
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
      height: 1.2,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AmbientBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ImmichLogo(
                size: scale.sizeOf(220, min: 160, max: 260),
              ),
              SizedBox(height: scale.space(18, min: 14, max: 22)),
              AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: const Duration(milliseconds: 520),
                curve: Curves.easeOutCubic,
                child: FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final packageInfo = snapshot.data;
                    if (packageInfo == null) {
                      return const SizedBox.shrink();
                    }
                    return Text(
                      'v${packageInfo.version} (${packageInfo.buildNumber})',
                      textAlign: TextAlign.center,
                      style: versionTextStyle,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
