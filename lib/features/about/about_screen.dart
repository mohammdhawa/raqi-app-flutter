import 'package:flutter/material.dart';

// TODO: Replace with your actual import path
// import 'package:your_app/theme/app_colors.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// About Screen — SESSION 8
/// ──────────────────────────────────────────────────────────────────────────────
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // ── Constants ──────────────────────────────────────────────────────────────
  static const Color _primary = Color(0xFF224167);
  static const Color _primary700 = Color(0xFF1A3554);
  static const Color _accent = Color(0xFFC8A36B);
  static const Color _surface = Color(0xFFF6F7FB);
  static const Color _border = Color(0xFFE4E6EE);
  static const Color _text = Color(0xFF1B2A41);
  static const Color _text2 = Color(0xFF6B7591);
  static const Color _text3 = Color(0xFF9099AD);
  static const Color _white = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _white,
        body: Column(
          children: [
            _buildAppBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _buildCompanySection(context),
                    const SizedBox(height: 22),
                    _buildInfoTiles(),
                    const SizedBox(height: 24),
                    _buildVersionLegal(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── App Bar ────────────────────────────────────────────────────────────────
  Widget _buildAppBar(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 14,
        left: 16,
        right: 16,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_primary, _primary700],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_forward_ios, color: _white, size: 16),
            ),
          ),
          const Spacer(),
          // Title column
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'من نحن',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _white,
                ),
              ),
              Text(
                'الإصدار 1.0.0',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: _white.withValues(alpha: 0.78),
                ),
              ),
            ],
          ),
          const Spacer(),
          // Invisible spacer to balance back button
          const SizedBox(width: 36),
        ],
      ),
    );
  }

  // ── 1. Company Section ─────────────────────────────────────────────────────
  Widget _buildCompanySection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          // Logo
          Image.asset(
            'assets/logo-full-trans.png',
            width: MediaQuery.of(context).size.width * 0.55,
          ),
          const SizedBox(height: 14),
          // Gold rule
          Container(width: 40, height: 2, color: _accent),
          const SizedBox(height: 12),
          // Mission text
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: const Text(
              'شركة الراقـي للإنشاءات هي شركة متخصصة في الإنشاءات والمقاولات، تأسست عام 2020 في إدلب ثم انتقلت إلى حلب بعد التحرير. تميزت منذ انطلاقها بتقديم خدمات عالية الجودة قائمة على الثقة والمصداقية، تحت شعار: «نبني الثقة قبل الحجر».\n\nتسعى الشركة إلى التوسع في مختلف المدن السورية للمساهمة في إعادة الإعمار والتنمية العمرانية.\n\nنُمكِّن المؤسسات من إدارة سير اعتماد المستندات بكفاءة وشفافية، عبر منظومة رقمية تحترم تسلسل المسؤوليات وتضمن خصوصية البيانات في كل خطوة من خطوات القرار.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: _text2,
                height: 1.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 2. Info Tiles ──────────────────────────────────────────────────────────
  Widget _buildInfoTiles() {
    final tiles = [
      _TileData(Icons.description_outlined, 'إدارة المستندات', 'رقمية وفعّالة'),
      _TileData(Icons.verified, 'الاعتماد الرسمي', 'بتوقيع رقمي'),
      _TileData(Icons.shield_outlined, 'أمان البيانات', 'حماية كاملة'),
    ];

    return Row(
      children: List.generate(tiles.length * 2 - 1, (i) {
        if (i.isOdd) return const SizedBox(width: 10);
        final tile = tiles[i ~/ 2];
        return Expanded(child: _buildTile(tile));
      }),
    );
  }

  Widget _buildTile(_TileData data) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon container
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border, width: 1),
            ),
            child: Icon(data.icon, size: 20, color: _primary),
          ),
          const SizedBox(height: 8),
          Container(width: 16, height: 2, color: _accent),
          const SizedBox(height: 6),
          Text(
            data.label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              fontWeight: FontWeight.w400,
              color: _text2,
            ),
          ),
        ],
      ),
    );
  }

  // ── 3. Version & Legal ─────────────────────────────────────────────────────
  Widget _buildVersionLegal() {
    return Column(
      children: [
        Center(child: Container(width: 24, height: 2, color: _accent)),
        const SizedBox(height: 12),
        const Text(
          'الإصدار 1.0.0',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: _text2,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'جميع الحقوق محفوظة © 2026 · شركة الراقي',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 10,
            fontWeight: FontWeight.w400,
            color: _text3,
          ),
        ),
      ],
    );
  }
}

// ── Data class for tiles ─────────────────────────────────────────────────────
class _TileData {
  final IconData icon;
  final String label;
  final String subtitle;
  const _TileData(this.icon, this.label, this.subtitle);
}