import 'package:flutter/material.dart';
import '../../../../widgets/bottom_menu_animap.dart';
import '../../data/pets_service.dart';
import 'register_pet_page.dart';
import 'pet_profile_page.dart';

class MyPetsPage extends StatefulWidget {
  const MyPetsPage({super.key});

  @override
  State<MyPetsPage> createState() => _MyPetsPageState();
}

class _MyPetsPageState extends State<MyPetsPage> {
  late Future<List<Map<String, dynamic>>> _futureMascotas;

  bool _hayMascotasActivas = false;

  @override
  void initState() {
    super.initState();
    _futureMascotas = PetsService.getMyPets();
  }

  Future<void> _refreshPets() async {
    setState(() {
      _futureMascotas = PetsService.getMyPets();
    });
  }

  String _buildImageUrl(Map<String, dynamic> pet) {
    final fotoPrincipal = pet['fotoPrincipal'];

    if (fotoPrincipal == null) {
      return '';
    }

    final imagePath = fotoPrincipal['url'];

    if (imagePath == null || imagePath.toString().isEmpty) {
      return '';
    }

    return '${PetsService.baseUrl.replaceAll('/api', '')}$imagePath';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F8FA),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Mis Mascotas',
          style: TextStyle(
            color: Color(0xFF1F2937),
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1F2937)),
      ),

      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _futureMascotas,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorView(
              message: 'No se pudieron cargar tus mascotas.',
              onRetry: _refreshPets,
            );
          }

          final pets = snapshot.data ?? [];

          final mascotasActivas = pets.where((mascota) {
            final estado = mascota['estado']?.toString().toUpperCase() ?? '';
            return estado != 'INACTIVA';
          }).toList();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _hayMascotasActivas != mascotasActivas.isNotEmpty) {
              setState(() {
                _hayMascotasActivas = mascotasActivas.isNotEmpty;
              });
            }
          });

          if (mascotasActivas.isEmpty) {
            return _EmptyPetsView(
              onAddPet: () async {
                final created = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RegisterPetPage(),
                  ),
                );

                if (created == true) {
                  _refreshPets();
                }
              },
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshPets,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 120),
              itemCount: mascotasActivas.length,
              itemBuilder: (context, index) {
                final pet = mascotasActivas[index];

                final imageUrl = _buildImageUrl(pet);

                return _PetCard(
                  name: pet['nombre']?.toString() ?? 'Sin nombre',
                  species: pet['especie']?.toString() ?? 'Sin especie',
                  breed: pet['raza']?.toString() ?? 'Sin raza',
                  status: pet['estado']?.toString() ?? 'ACTIVA',
                  imageUrl: imageUrl,

                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PetProfilePage(
                          mascotaId: int.parse(pet['id']!.toString()),
                          mostrarAccionesDueno: true,
                        ),
                      ),
                    );

                    if (result == true) {
                      setState(() {
                        _futureMascotas = PetsService.getMyPets();
                      });
                    }
                  },

                  onEdit: () async {
                    final updated = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            RegisterPetPage(mascotaEditar: pet),
                      ),
                    );

                    if (updated == true) {
                      _refreshPets();
                    }
                  },
                );
              },
            ),
          );
        },
      ),

      floatingActionButton: _hayMascotasActivas
          ? Padding(
        padding: const EdgeInsets.only(bottom: 90),
        child: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF2563EB),
          onPressed: () async {
            final created = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const RegisterPetPage(),
              ),
            );

            if (created == true) {
              _refreshPets();
            }
          },
                icon: const Icon(Icons.add, color: Colors.white),
          label: const Text(
            'Agregar',
                  style: TextStyle(color: Colors.white),
          ),
        ),
      )
          : null,

      bottomNavigationBar: const BottomMenuAnimap(currentIndex: 1),
    );
  }
}

class _PetCard extends StatelessWidget {
  final String name;
  final String species;
  final String breed;
  final String status;
  final String imageUrl;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _PetCard({
    required this.name,
    required this.species,
    required this.breed,
    required this.status,
    required this.imageUrl,
    required this.onTap,
    required this.onEdit,
  });

  Color get statusColor {
    switch (status) {
      case 'ACTIVA':
        return const Color(0xFF16A34A);
      case 'PERDIDA':
        return const Color(0xFFDC2626);
      case 'ENCONTRADA':
        return const Color(0xFF2563EB);
      case 'INACTIVA':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String get statusText {
    switch (status) {
      case 'ACTIVA':
        return 'Activa';
      case 'PERDIDA':
        return 'Perdida';
      case 'ENCONTRADA':
        return 'Encontrada';
      case 'INACTIVA':
        return 'Inactiva';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: imageUrl.isEmpty
                    ? _GenericPetImage()
                    : Image.network(
                  imageUrl,
                        headers: PetsService.authHeaders,
                  width: 82,
                  height: 82,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const _GenericPetImage();
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$species · $breed',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, color: Color(0xFF374151)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenericPetImage extends StatelessWidget {
  const _GenericPetImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 82,
      height: 82,
      color: const Color(0xFFE5E7EB),
      child: const Icon(Icons.pets, color: Color(0xFF6B7280), size: 36),
    );
  }
}

class _EmptyPetsView extends StatelessWidget {
  final VoidCallback onAddPet;

  const _EmptyPetsView({required this.onAddPet});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 90, 24, 24),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 34),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFFA7F3D0), width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8F8EF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.pets,
                    size: 54,
                    color: Color(0xFF047857),
                  ),
                ),

                const SizedBox(height: 22),

                const Text(
                  'No tienes mascotas registradas',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF263238),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  'Registra tu primera mascota para poder verla aquí, editar su información y consultar su perfil cuando lo necesites.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),

                const SizedBox(height: 26),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: onAddPet,
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text(
                      'Registrar mascota',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF047857),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 70, color: Color(0xFFDC2626)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: onRetry,
              child: const Text(
                'Reintentar',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
