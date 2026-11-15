import 'package:flutter/material.dart';

class PredictiveMaintenanceHero extends StatelessWidget {
  const PredictiveMaintenanceHero({
    super.key,
    required this.height,
    this.backgroundImage,
  });

  final double height;
  final ImageProvider<Object>? backgroundImage;

  static const _factoryImage = NetworkImage(
    'https://images.unsplash.com/photo-1581092160607-ee22621dd758?auto=format&fit=crop&w=1400&q=85',
  );

  @override
  Widget build(BuildContext context) {
    final image = backgroundImage ?? _factoryImage;

    return ClipPath(
      clipper: _HeroWaveClipper(),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: image,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) => const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF092C4C), Color(0xFF075E6B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xE6092948),
                    Color(0xB3095363),
                    Color(0x66075E6B),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x33000000), Color(0x99051C33)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            _HeroContent(compact: height < 130),
          ],
        ),
      ),
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final brandSize = compact ? 19.0 : 25.0;
    final iconSize = compact ? 32.0 : 48.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        compact ? 14 : 20,
        24,
        compact ? 18 : 28,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -14,
            top: -18,
            child: Icon(
              Icons.precision_manufacturing_rounded,
              size: compact ? 68 : 148,
              color: Colors.white.withAlpha(28),
            ),
          ),
          Positioned.fill(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IndustrialLogo(size: iconSize),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Maintenance',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: brandSize,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'prédictive',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFF12C7BB),
                              fontSize: brandSize,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!compact) ...[
                  const Spacer(),
                  const Padding(
                    padding: EdgeInsets.only(left: 3),
                    child: Text(
                      'Anticipez les pannes,\npréservez votre production',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IndustrialLogo extends StatelessWidget {
  const _IndustrialLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF123F5D), Color(0xFF06263F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(
            color: const Color(0xFF38D5C9),
            width: size * 0.045,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00C8B7).withAlpha(75),
              blurRadius: size * 0.24,
              spreadRadius: size * 0.02,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.settings_rounded,
              size: size * 0.72,
              color: Colors.white,
            ),
            Icon(
              Icons.show_chart_rounded,
              size: size * 0.42,
              color: const Color(0xFF12C7BB),
            ),
            Positioned(
              right: size * 0.12,
              top: size * 0.12,
              child: Container(
                width: size * 0.13,
                height: size * 0.13,
                decoration: const BoxDecoration(
                  color: Color(0xFF7CFFF2),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()..lineTo(0, size.height - 18);
    path.cubicTo(
      size.width * 0.24,
      size.height + 8,
      size.width * 0.48,
      size.height - 34,
      size.width * 0.72,
      size.height - 12,
    );
    path.cubicTo(
      size.width * 0.84,
      size.height - 2,
      size.width * 0.93,
      size.height - 8,
      size.width,
      size.height - 22,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
