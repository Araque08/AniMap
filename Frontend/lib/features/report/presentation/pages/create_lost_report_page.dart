import 'package:flutter/material.dart';

import '../../../../widgets/bottom_menu_animap.dart';

class CreateLostReportPage extends StatefulWidget {
  const CreateLostReportPage({super.key});

  @override
  State<CreateLostReportPage> createState() => _CreateLostReportPageState();
}

class _CreateLostReportPageState extends State<CreateLostReportPage> {
  String _selectedPet = 'Doge';
  bool _useGps = true;

  static const Color lightGreen = Color(0xFFDFF3E8);
  static const Color accentGreen = Color(0xFF4D9B6A);
  static const Color darkText = Color(0xFF344955);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F4),

      body: SafeArea(
        child: Column(
          children: [
            _Header(),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TitleRow(),

                    const SizedBox(height: 8),

                    _PetSelector(
                      selectedPet: _selectedPet,
                      onChanged: (value) {
                        if (value == null) return;

                        setState(() {
                          _selectedPet = value;
                        });
                      },
                    ),

                    const SizedBox(height: 12),

                    const Text(
                      'Datos Base (autocompletados)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 10),

                    const _InfoChips(),

                    const SizedBox(height: 16),

                    const Text(
                      'Descripción y Observaciones:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Pequeña cicatriz en la oreja derecha, miedoso a ruidos fuertes',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Datos obtenidos del perfil registrado',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.black54,
                      ),
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      'Última ubicación conocida (Obligatorio)',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const _MapPreview(),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _LocationButton(
                            text: 'Usar GPS',
                            icon: Icons.gps_fixed,
                            selected: _useGps,
                            onTap: () {
                              setState(() {
                                _useGps = true;
                              });
                            },
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: _LocationButton(
                            text: 'Selección Manual',
                            icon: Icons.touch_app,
                            selected: !_useGps,
                            onTap: () {
                              setState(() {
                                _useGps = false;
                              });
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    const Text(
                      'Dirección encontrada',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF91A89B),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Carrera 7 # 12-34, Salitre Bogotá',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Center(
                      child: SizedBox(
                        width: 210,
                        height: 32,
                        child: ElevatedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Reporte creado correctamente'),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentGreen,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Crear Reporte',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: const BottomMenuAnimap(
        currentIndex: 1,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      width: double.infinity,
      color: _CreateLostReportPageState.lightGreen,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(
            Icons.menu,
            size: 30,
            color: Colors.black87,
          ),

          const Spacer(),

          Row(
            children: [
              Container(
                width: 33,
                height: 33,
                decoration: const BoxDecoration(
                  color: _CreateLostReportPageState.accentGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.pets,
                  color: Colors.white,
                  size: 21,
                ),
              ),

              const SizedBox(width: 6),

              const Text(
                'AniMap',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: _CreateLostReportPageState.darkText,
                ),
              ),
            ],
          ),

          const Spacer(),

          const Icon(
            Icons.notifications,
            size: 27,
            color: Colors.black87,
          ),
        ],
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () {
            Navigator.pop(context);
          },
          child: const Icon(
            Icons.keyboard_backspace,
            size: 30,
            color: Colors.black,
          ),
        ),

        const SizedBox(width: 10),

        const Expanded(
          child: Text(
            'Nuevo reporte de pérdida',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
        ),

        const SizedBox(width: 40),
      ],
    );
  }
}

class _PetSelector extends StatelessWidget {
  final String selectedPet;
  final ValueChanged<String?> onChanged;

  const _PetSelector({
    required this.selectedPet,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _CreateLostReportPageState.lightGreen,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: Color(0xFFEAD9A6),
            child: Text(
              '🐶',
              style: TextStyle(fontSize: 21),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedPet,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down),
                items: const [
                  DropdownMenuItem(
                    value: 'Doge',
                    child: Text('Doge'),
                  ),
                  DropdownMenuItem(
                    value: 'Milo',
                    child: Text('Milo'),
                  ),
                  DropdownMenuItem(
                    value: 'Luna',
                    child: Text('Luna'),
                  ),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChips extends StatelessWidget {
  const _InfoChips();

  @override
  Widget build(BuildContext context) {
    final items = [
      'Nombre: Doge',
      'Raza: Shiba Inu',
      'Sexo: Macho',
      'Especie: Perro',
      'Color: Sésamo',
      'Dueño: Alex',
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((item) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFEDEDED),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            item,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.black87,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MapPreview extends StatelessWidget {
  const _MapPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFDDEFE8),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFFD0D0D0),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _FakeMapPainter(),
            ),
          ),

          const Center(
            child: Icon(
              Icons.location_on,
              color: Colors.blue,
              size: 38,
            ),
          ),

          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              color: Colors.white,
              child: const Text(
                'UBICACIÓN DEL REPORTE',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _LocationButton({
    required this.text,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? _CreateLostReportPageState.accentGreen
        : const Color(0xFFEAF7F0);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: _CreateLostReportPageState.accentGreen,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : _CreateLostReportPageState.accentGreen,
            ),

            const SizedBox(width: 6),

            Text(
              text,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FakeMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final roadPaint2 = Paint()
      ..color = const Color(0xFFC7E0D7)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(0, size.height * 0.25),
      Offset(size.width, size.height * 0.10),
      roadPaint,
    );

    canvas.drawLine(
      Offset(0, size.height * 0.65),
      Offset(size.width, size.height * 0.45),
      roadPaint,
    );

    canvas.drawLine(
      Offset(size.width * 0.20, 0),
      Offset(size.width * 0.35, size.height),
      roadPaint2,
    );

    canvas.drawLine(
      Offset(size.width * 0.70, 0),
      Offset(size.width * 0.50, size.height),
      roadPaint2,
    );

    canvas.drawLine(
      Offset(0, size.height * 0.85),
      Offset(size.width, size.height * 0.75),
      roadPaint2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}