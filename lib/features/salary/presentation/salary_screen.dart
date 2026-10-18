import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/card_kit.dart';

/// راتبي — a placeholder until the ERP payroll API exists. Shows no amount,
/// so an unknown salary is never mistaken for zero.
class SalaryScreen extends StatelessWidget {
  const SalaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('راتبي', style: AppTheme.heading1(color: AppColors.text)),
            const SizedBox(height: 16),
            const UnavailableCard(
              title: 'الرواتب',
              body:
                  'ستظهر هنا كشوف رواتبك الشهرية بتفاصيلها، مع حالة التحويل وتاريخه، عند تفعيل الخدمة.',
              icon: Icons.account_balance_wallet_outlined,
            ),
          ],
        ),
      ),
    );
  }
}
