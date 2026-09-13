import 'package:flutter/material.dart';

import '../../../../widgets/bottom_menu_animap.dart';
import '../../../../widgets/top_menu_animap.dart';

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  String selectedCategory = 'Todas';

  final List<Map<String, String>> faqs = [
    {
      'category': 'General',
      'question': '¿Qué es AniMap?',
      'answer':
          'AniMap es una aplicación móvil para reportar mascotas perdidas y avistamientos dentro de una comunidad, usando mapa interactivo, ubicación y notificaciones.',
    },
    {
      'category': 'Mascotas',
      'question': '¿Cómo registro una mascota?',
      'answer':
          'Debes ingresar a la sección Mis Mascotas, completar los datos de la mascota y guardar su información para poder gestionarla dentro de la aplicación.',
    },
    {
      'category': 'Reportes',
      'question': '¿Cómo creo un reporte de mascota perdida?',
      'answer':
          'Debes entrar en Crear reporte, seleccionar una mascota registrada, agregar una descripción del caso y marcar la última ubicación conocida.',
    },
    {
      'category': 'Avistamientos',
      'question': '¿Puedo reportar una mascota que vi en la calle?',
      'answer':
          'Sí. Puedes registrar un avistamiento con una descripción, ubicación y una foto opcional para ayudar a la comunidad.',
    },
    {
      'category': 'Notificaciones',
      'question': '¿Cómo funcionan las notificaciones?',
      'answer':
          'La aplicación puede enviar alertas cuando se registre un avistamiento o una posible coincidencia relacionada con una mascota perdida.',
    },
    {
      'category': 'Mapa',
      'question': '¿Para qué sirve el mapa interactivo?',
      'answer':
          'El mapa permite visualizar reportes de mascotas perdidas y avistamientos mediante marcadores de ubicación.',
    },
  ];

  List<String> get categories {
    final values = faqs.map((faq) => faq['category']!).toSet().toList();
    return ['Todas', ...values];
  }

  @override
  Widget build(BuildContext context) {
    final filteredFaqs = selectedCategory == 'Todas'
        ? faqs
        : faqs.where((faq) => faq['category'] == selectedCategory).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF7),

      drawer: const AniMapSideMenu(),

      body: Column(
        children: [
          const TopMenuAnimap(),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            decoration: const BoxDecoration(
              color: Color(0xFFDFF3E8),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(26),
                bottomRight: Radius.circular(26),
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Centro de ayuda',
                  style: TextStyle(
                    color: Color(0xFF344955),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                SizedBox(height: 6),

                Text(
                  'Encuentra respuestas rápidas sobre el uso de AniMap.',
                  style: TextStyle(color: Color(0xFF344955), fontSize: 14),
                ),
              ],
            ),
          ),

          SizedBox(
            height: 62,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = categories[index];
                final isSelected = selectedCategory == category;

                return ChoiceChip(
                  label: Text(category),
                  selected: isSelected,
                  selectedColor: const Color(0xFF2E7D5B),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF2E7D5B)),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF2E7D5B),
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) {
                    setState(() {
                      selectedCategory = category;
                    });
                  },
                );
              },
            ),
          ),

          Expanded(
            child: filteredFaqs.isEmpty
                ? const Center(
                    child: Text(
                      'No hay preguntas registradas.',
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                    itemCount: filteredFaqs.length,
                    itemBuilder: (context, index) {
                      final faq = filteredFaqs[index];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ExpansionTile(
                          iconColor: const Color(0xFF2E7D5B),
                          collapsedIconColor: const Color(0xFF2E7D5B),
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            16,
                          ),
                          title: Text(
                            faq['question']!,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              faq['category']!,
                              style: const TextStyle(
                                color: Color(0xFF2E7D5B),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                faq['answer']!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),

      bottomNavigationBar: const BottomMenuAnimap(currentIndex: -1),
    );
  }
}
