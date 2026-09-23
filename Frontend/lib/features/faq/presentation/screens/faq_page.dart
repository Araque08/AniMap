import 'package:flutter/material.dart';

import '../../../../widgets/bottom_menu_animap.dart';
import '../../../../widgets/top_menu_animap.dart';
import '../../../admin/data/faq_service.dart';

class FaqScreen extends StatefulWidget {
  final FaqService? faqService;
  const FaqScreen({super.key, this.faqService});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  String selectedCategory = 'Todas';
  late final FaqService _service = widget.faqService ?? FaqService();
  List<Map<String, dynamic>> faqs = [];
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.getPublicFaqs(),
        _service.getCategories(),
      ]);
      if (!mounted) return;
      setState(() {
        faqs = results[0];
        _categories = results[1];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  List<String> get categories {
    final values = _categories
        .map((category) => category['nombre'].toString())
        .toList();
    return ['Todas', ...values];
  }

  @override
  Widget build(BuildContext context) {
    final filteredFaqs = selectedCategory == 'Todas'
        ? faqs
        : faqs.where((faq) => faq['categoria'] == selectedCategory).toList();

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
              separatorBuilder: (_, _) => const SizedBox(width: 8),
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
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  )
                : filteredFaqs.isEmpty
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
                            faq['pregunta']?.toString() ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              faq['categoria']?.toString() ?? '',
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
                                faq['respuesta']?.toString() ?? '',
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
