import 'package:flutter/material.dart';

class BottomMenuAnimap extends StatelessWidget {
  final int currentIndex;

  const BottomMenuAnimap({
    super.key,
    required this.currentIndex,
  });

  static const Color primaryGreen = Color(0xFF51BD73);
  static const Color darkGreen = Color(0xFF2F8F5B);
  static const Color textInactive = Color(0xFF839189);
  static const Color background = Color(0xFFFFFFFF);

  void _navigate(BuildContext context, int index) {
    if (index == currentIndex) return;

    String routeName;

    switch (index) {
      case 0:
        routeName = '/home';
        break;

      case 1:
        routeName = '/create-report';
        break;

      case 2:
        routeName = '/profile';
        break;

      default:
        routeName = '/home';
    }

    Navigator.pushNamedAndRemoveUntil(
      context,
      routeName,
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        height: 78,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x16000000),
              blurRadius: 24,
              spreadRadius: 0,
              offset: Offset(0, 7),
            ),
          ],
          border: Border.all(
            color: const Color(0xFFE6ECE8),
            width: 1,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: _MenuItem(
                    icon: Icons.home_rounded,
                    outlinedIcon: Icons.home_outlined,
                    label: 'Inicio',
                    isSelected: currentIndex == 0,
                    onTap: () => _navigate(context, 0),
                  ),
                ),

                const SizedBox(width: 90),

                Expanded(
                  child: _MenuItem(
                    icon: Icons.person_rounded,
                    outlinedIcon: Icons.person_outline_rounded,
                    label: 'Perfil',
                    isSelected: currentIndex == 2,
                    onTap: () => _navigate(context, 2),
                  ),
                ),
              ],
            ),

            Positioned(
              top: -26,
              child: _CenterReportButton(
                isSelected: currentIndex == 1,
                onTap: () => _navigate(context, 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final IconData outlinedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.outlinedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  static const Color primaryGreen = Color(0xFF51BD73);
  static const Color darkGreen = Color(0xFF2F8F5B);
  static const Color textInactive = Color(0xFF839189);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: primaryGreen.withOpacity(.08),
        highlightColor: primaryGreen.withOpacity(.04),
        child: SizedBox(
          height: 78,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: isSelected ? 46 : 40,
                height: 34,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFE8F6ED)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isSelected ? icon : outlinedIcon,
                  size: 25,
                  color: isSelected ? darkGreen : textInactive,
                ),
              ),

              const SizedBox(height: 3),

              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight:
                  isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? darkGreen : textInactive,
                ),
                child: Text(label),
              ),

              const SizedBox(height: 3),

              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: isSelected ? 18 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: darkGreen,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterReportButton extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;

  const _CenterReportButton({
    required this.isSelected,
    required this.onTap,
  });

  static const Color primaryGreen = Color(0xFF51BD73);
  static const Color darkGreen = Color(0xFF2F8F5B);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: isSelected ? 74 : 70,
              height: isSelected ? 74 : 70,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(
                  color: const Color(0xFFE2EAE5),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: darkGreen.withOpacity(.22),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      primaryGreen,
                      darkGreen,
                    ],
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.pets_rounded,
                      color: Colors.white,
                      size: 32,
                    ),

                    Positioned(
                      right: 11,
                      bottom: 10,
                      child: Container(
                        width: 21,
                        height: 21,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: darkGreen,
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: darkGreen,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 2),

        Text(
          'Reportar',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: isSelected
                ? darkGreen
                : const Color(0xFF718078),
          ),
        ),
      ],
    );
  }
}