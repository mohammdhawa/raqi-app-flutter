import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

  static const List<BoxShadow> _shCard = [
    BoxShadow(color: Color(0x0A1B2A41), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0F1B2A41), blurRadius: 16, offset: Offset(0, 6)),
  ];

  // ── Helpers ────────────────────────────────────────────────────────────────
  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

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
                    _buildMandalaDivider(),
                    const SizedBox(height: 20),
                    _buildDeveloperSection(),
                    const SizedBox(height: 28),
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

  // ── 3. Mandala Divider ─────────────────────────────────────────────────────
  Widget _buildMandalaDivider() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_accent, Colors.transparent, _accent],
            ),
          ),
        ),
        Container(
          color: _white,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Image.asset(
            'assets/logo-symbol-gold.png',
            width: 20,
            height: 20,
          ),
        ),
      ],
    );
  }

  // ── 4. Developer Section ───────────────────────────────────────────────────
  Widget _buildDeveloperSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: const [
            Icon(Icons.people_outline, size: 16, color: _primary),
            SizedBox(width: 6),
            Text(
              'فريق التطوير',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Manager Card: محمود هندواي ─────────────────────────────────────
        _buildManagerCard(),
        const SizedBox(height: 10),

        // ── Developer Card: محمد هوى ───────────────────────────────────────
        _buildDeveloperCard(),
      ],
    );
  }

  /// بطاقة مدير قسم الإعلام والتسويق — محمود هندواي
  Widget _buildManagerCard() {
    return Container(
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: 0.45), width: 1.5),
        boxShadow: _shCard,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            // Gold right-edge bar (thicker for the manager)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: _accent),
            ),
            // Badge: مدير القسم
            Positioned(
              top: 10,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _accent.withValues(alpha: 0.4), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.star_rounded, size: 11, color: _accent),
                    SizedBox(width: 4),
                    Text(
                      'مدير القسم',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: _accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Card content
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 36, 14, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Avatar
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_accent, Color(0xFFB8893B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(color: _white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: _accent.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'م',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: _white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Name & role
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'محمود هندواي',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _text,
                              ),
                            ),
                            Text(
                              'مدير قسم الإعلام والتسويق',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                color: _text2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Info row
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _accent.withValues(alpha: 0.2), width: 1),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.business_center_outlined, size: 13, color: _accent),
                        SizedBox(width: 6),
                        Text(
                          'قسم التسويق والإعلان',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// رابط التسلسل الهرمي بين المدير والمطوّر
  /// بطاقة المطوّر — محمد هوى
  Widget _buildDeveloperCard() {
    return Container(
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border, width: 1),
        boxShadow: _shCard,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            // Gold right-edge bar
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 3, color: _accent),
            ),
            // Card content
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  // Main developer row
                  Row(
                    children: [
                      // Avatar
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: _primary,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'م',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: _white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Name & role
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'مهندس التطوير',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _text,
                              ),
                            ),
                            Text(
                              'مطوّر تطبيقات Web & Mobile',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                color: _text2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Social icons
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _socialButton(
                            icon: Icons.mail_outlined,
                            onTap: () => _launch('mailto:alraqimraketing@gmail.com'),
                          ),
                          const SizedBox(width: 8),
                          _socialButton(
                            icon: Icons.link,
                            onTap: () => _launch('https://linkedin.com'),
                          ),
                          const SizedBox(width: 8),
                          _socialButton(
                            icon: Icons.code,
                            onTap: () => _launch('https://github.com'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Extra info row
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'محمد رجب هوى',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'مدير القسم التقني',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: _text2,
                          ),
                        ),

                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Contact row
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined, size: 14, color: _text2),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _launch('tel:+963958244652'),
                        child: const Text(
                          '+963 958 244 652',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: _text2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Icon(Icons.email_outlined, size: 14, color: _text2),
                      const SizedBox(width: 6),
                      Flexible(
                        child: GestureDetector(
                          onTap: () => _launch('mailto:alraqimraketing@gmail.com'),
                          child: const Text(
                            'alraqimraketing@gmail.com',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              color: _text2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _socialButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Icon(icon, size: 16, color: _primary),
        ),
      ),
    );
  }

  // ── 5. Version & Legal ─────────────────────────────────────────────────────
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