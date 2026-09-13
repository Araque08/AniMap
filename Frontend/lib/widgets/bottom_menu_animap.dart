import 'package:flutter/material.dart';

class BottomMenuAnimap extends StatelessWidget {
  final int currentIndex;

  const BottomMenuAnimap({super.key, required this.currentIndex});

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

    Navigator.pushNamedAndRemoveUntil(context, routeName, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    const Color green = Color(0xFF3F9568);

    return SafeArea(
      child: Container(
        height: 78,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAF6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF7CC484), width: 1.3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _MenuIcon(
                  icon: Icons.home_rounded,
                  isSelected: currentIndex == 0,
                  onTap: () => _navigate(context, 0),
                ),

                const SizedBox(width: 100),

                _MenuIcon(
                  icon: Icons.person_rounded,
                  isSelected: currentIndex == 2,
                  onTap: () => _navigate(context, 2),
                ),
              ],
            ),

            Positioned(
              top: -18,
              child: GestureDetector(
                onTap: () => _navigate(context, 1),
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAF6),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 62,
                      height: 62,
                      decoration: const BoxDecoration(
                        color: green,
                        shape: BoxShape.circle,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(
                            Icons.pets_rounded,
                            color: Colors.white,
                            size: 42,
                          ),
                          Positioned(
                            bottom: 11,
                            right: 13,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.add_rounded,
                                color: green,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuIcon extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _MenuIcon({
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const Color green = Color(0xFF3F9568);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 80,
        height: 70,
        child: Icon(
          icon,
          size: 38,
          color: isSelected ? green : green.withOpacity(0.85),
        ),
      ),
    );
  }
}

//Esta codigo es para colocarlo en las interfaces que lo requieran, muestra toda la parte de la navegacion inferior.

/*
bottomNavigationBar: const BottomMenuAnimap(
  currentIndex: 1,
),
*/
