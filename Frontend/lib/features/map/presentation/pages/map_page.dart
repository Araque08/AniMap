import 'package:flutter/material.dart';
import '../../../pet/presentation/pages/my_pets_page.dart';
class MapPage extends StatefulWidget {
  final String userName;

  const MapPage({
    super.key,
    required this.userName,
  });

  @override
  State<MapPage> createState() => _MapPageState();
}

enum MapFilter {
  active,
  found,
}

enum MapStatus {
  loaded,
  empty,
  error,
}

class _MapPageState extends State<MapPage> {
  MapFilter _selectedFilter = MapFilter.active;
  MapStatus _status = MapStatus.loaded;
  bool _menuOpen = false;
  String? _selectedCardType = 'lost';

  static const Color backgroundColor = Color(0xFFDDEFE2);
  static const Color primaryGreen = Color(0xFF4E967B);
  static const Color darkText = Color(0xFF405466);
  static const Color lightGreen = Color(0xFFE6F5EC);
  static const Color foundGreen = Color(0xFF4E967B);
  static const Color lostRed = Color(0xFFE96F67);

  void _toggleFilter(MapFilter filter) {
    setState(() {
      _selectedFilter = filter;
      _selectedCardType = filter == MapFilter.active ? 'lost' : 'found';
      _status = MapStatus.loaded;
    });
  }

  void _openLostCard() {
    setState(() {
      _selectedCardType = 'lost';
      _status = MapStatus.loaded;
    });
  }

  void _openSightingCard() {
    setState(() {
      _selectedCardType = 'sighting';
      _status = MapStatus.loaded;
    });
  }

  void _openFoundCard() {
    setState(() {
      _selectedCardType = 'found';
      _status = MapStatus.loaded;
      _selectedFilter = MapFilter.found;
    });
  }

  void _showEmptyState() {
    setState(() {
      _status = MapStatus.empty;
      _selectedCardType = null;
    });
  }

  void _showErrorState() {
    setState(() {
      _status = MapStatus.error;
      _selectedCardType = null;
    });
  }

  void _retryLoad() {
    setState(() {
      _status = MapStatus.loaded;
      _selectedCardType = _selectedFilter == MapFilter.active ? 'lost' : 'found';
    });
  }

  void _toggleMenu() {
    setState(() {
      _menuOpen = !_menuOpen;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              _Header(
                onMenuTap: _toggleMenu,
              ),
              _FilterBar(
                selectedFilter: _selectedFilter,
                onActiveTap: () => _toggleFilter(MapFilter.active),
                onFoundTap: () => _toggleFilter(MapFilter.found),
              ),
              Expanded(
                child: Stack(
                  children: [
                    _MapMock(
                      selectedFilter: _selectedFilter,
                      status: _status,
                      onLostTap: _openLostCard,
                      onSightingTap: _openSightingCard,
                      onFoundTap: _openFoundCard,
                    ),
                    if (_status == MapStatus.empty) const _EmptyStateCard(),
                    if (_status == MapStatus.error)
                      _ErrorStateCard(
                        onRetry: _retryLoad,
                      ),
                    if (_status == MapStatus.loaded && _selectedCardType != null)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 18,
                        child: _ReportPreviewCard(
                          type: _selectedCardType!,
                          onClose: () {
                            setState(() {
                              _selectedCardType = null;
                            });
                          },
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _LocationBar(),
                    ),
                  ],
                ),
              ),
              _BottomNavigation(
                onHomeTap: _retryLoad,
                onCreateTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Aquí irá crear reporte.'),
                    ),
                  );
                },
                onProfileTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Perfil de ${widget.userName}'),
                    ),
                  );
                },
              ),
            ],
          ),
          if (_menuOpen)
            _SideMenu(
              onClose: _toggleMenu,
              onLostPets: () {
                setState(() {
                  _menuOpen = false;
                  _selectedFilter = MapFilter.active;
                  _status = MapStatus.loaded;
                  _selectedCardType = 'lost';
                });
              },
              onMyPets: () {
                setState(() {
                  _menuOpen = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Aquí irá Mis Mascotas.'),
                  ),
                );
              },
              onFaq: () {
                setState(() {
                  _menuOpen = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Aquí irá Preguntas Frecuentes.'),
                  ),
                );
              },
              onLogout: () {
                Navigator.pop(context);
              },
              onCreateReport: () {
                setState(() {
                  _menuOpen = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Aquí irá Crear reporte.'),
                  ),
                );
              },
            ),
          Positioned(
            right: 12,
            top: 130,
            child: Column(
              children: [
                _DevStateButton(
                  label: 'Mapa',
                  onTap: _retryLoad,
                ),
                _DevStateButton(
                  label: 'Vacío',
                  onTap: _showEmptyState,
                ),
                _DevStateButton(
                  label: 'Error',
                  onTap: _showErrorState,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onMenuTap;

  const _Header({
    required this.onMenuTap,
  });

  static const Color darkText = Color(0xFF405466);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 75,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        color: const Color(0xFFDDF2E7),
        child: Row(
          children: [
            GestureDetector(
              onTap: onMenuTap,
              child: const Icon(
                Icons.menu,
                size: 28,
                color: Colors.black87,
              ),
            ),
            const Spacer(),
            Image.asset(
              'assets/images/Logo_Principal_AniMap.png',
              height: 50,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 6),
            const Text(
              'AniMap',
              style: TextStyle(
                color: darkText,
                fontSize: 27,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.notifications,
              size: 26,
              color: Colors.black87,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final MapFilter selectedFilter;
  final VoidCallback onActiveTap;
  final VoidCallback onFoundTap;

  const _FilterBar({
    required this.selectedFilter,
    required this.onActiveTap,
    required this.onFoundTap,
  });

  static const Color primaryGreen = Color(0xFF4E967B);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      color: Colors.white,
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _FilterButton(
              text: 'Activos',
              selected: selectedFilter == MapFilter.active,
              onTap: onActiveTap,
            ),
            const SizedBox(width: 12),
            _FilterButton(
              text: 'Encontrados',
              selected: selectedFilter == MapFilter.found,
              onTap: onFoundTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _FilterButton({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  static const Color primaryGreen = Color(0xFF4E967B);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 108,
      height: 32,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: selected ? primaryGreen : const Color(0xFFE5F4EC),
          foregroundColor: selected ? Colors.white : const Color(0xFF405466),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
            side: BorderSide(
              color: selected ? primaryGreen : const Color(0xFFBFDCCB),
            ),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MapMock extends StatelessWidget {
  final MapFilter selectedFilter;
  final MapStatus status;
  final VoidCallback onLostTap;
  final VoidCallback onSightingTap;
  final VoidCallback onFoundTap;

  const _MapMock({
    required this.selectedFilter,
    required this.status,
    required this.onLostTap,
    required this.onSightingTap,
    required this.onFoundTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isError = status == MapStatus.error;
    final bool isEmpty = status == MapStatus.empty;

    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: isError || isEmpty ? 0.45 : 1,
            child: Image.network(
              'https://maps.googleapis.com/maps/api/staticmap?center=Ciudad%20Salitre%20Occidental,Bogota,Colombia&zoom=15&size=600x900&maptype=roadmap&key=',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return Container(
                  color: const Color(0xFFE4EFE7),
                  child: CustomPaint(
                    painter: _SimpleMapPainter(),
                  ),
                );
              },
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: 14,
          child: _Legend(
            selectedFilter: selectedFilter,
          ),
        ),
        Positioned(
          top: 80,
          left: 14,
          child: _ZoomControl(),
        ),
        if (!isError && !isEmpty && selectedFilter == MapFilter.active) ...[
          _MapMarker(
            top: 84,
            left: 80,
            color: const Color(0xFFE96F67),
            onTap: onLostTap,
          ),
          _MapMarker(
            top: 135,
            left: 160,
            color: const Color(0xFFE96F67),
            onTap: onLostTap,
          ),
          _MapMarker(
            top: 220,
            left: 40,
            color: const Color(0xFFE96F67),
            onTap: onLostTap,
          ),
          _MapMarker(
            top: 110,
            right: 52,
            color: const Color(0xFF4E967B),
            onTap: onSightingTap,
          ),
          _MapMarker(
            top: 185,
            right: 105,
            color: const Color(0xFF4E967B),
            onTap: onSightingTap,
          ),
          _MapMarker(
            top: 300,
            right: 65,
            color: const Color(0xFF4E967B),
            onTap: onSightingTap,
          ),
          _MapMarker(
            top: 270,
            left: 120,
            color: const Color(0xFFE96F67),
            onTap: onLostTap,
          ),
        ],
        if (!isError && !isEmpty && selectedFilter == MapFilter.found) ...[
          _MapMarker(
            top: 75,
            left: 55,
            color: const Color(0xFF4E967B),
            onTap: onFoundTap,
          ),
          _MapMarker(
            top: 118,
            left: 165,
            color: const Color(0xFF4E967B),
            onTap: onFoundTap,
          ),
          _MapMarker(
            top: 195,
            right: 75,
            color: const Color(0xFF4E967B),
            onTap: onFoundTap,
          ),
          _MapMarker(
            top: 285,
            left: 105,
            color: const Color(0xFF4E967B),
            onTap: onFoundTap,
          ),
        ],
        Positioned(
          right: 18,
          bottom: 80,
          child: CircleAvatar(
            backgroundColor: Colors.white,
            radius: 20,
            child: Icon(
              Icons.my_location,
              color: Colors.grey.shade700,
            ),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final MapFilter selectedFilter;

  const _Legend({
    required this.selectedFilter,
  });

  @override
  Widget build(BuildContext context) {
    final bool found = selectedFilter == MapFilter.found;

    return Container(
      width: 138,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 5,
          ),
        ],
      ),
      child: found
          ? const Row(
        children: [
          Icon(Icons.pets, size: 15, color: Color(0xFF4E967B)),
          SizedBox(width: 5),
          Text(
            'Mascota encontrada',
            style: TextStyle(fontSize: 11),
          ),
        ],
      )
          : const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pets, size: 15, color: Color(0xFFE96F67)),
              SizedBox(width: 5),
              Text(
                'Mascota Perdida',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
          SizedBox(height: 5),
          Row(
            children: [
              Icon(Icons.pets, size: 15, color: Color(0xFF4E967B)),
              SizedBox(width: 5),
              Text(
                'Avistamiento',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ZoomControl extends StatelessWidget {
  const _ZoomControl();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 4,
          ),
        ],
      ),
      child: const Column(
        children: [
          SizedBox(height: 6),
          Text('+', style: TextStyle(fontSize: 25)),
          Divider(height: 1),
          Text('−', style: TextStyle(fontSize: 25)),
          SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _MapMarker extends StatelessWidget {
  final double? top;
  final double? left;
  final double? right;
  final Color color;
  final VoidCallback onTap;

  const _MapMarker({
    this.top,
    this.left,
    this.right,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      child: GestureDetector(
        onTap: onTap,
        child: Icon(
          Icons.location_on,
          size: 38,
          color: color,
        ),
      ),
    );
  }
}

class _ReportPreviewCard extends StatelessWidget {
  final String type;
  final VoidCallback onClose;

  const _ReportPreviewCard({
    required this.type,
    required this.onClose,
  });

  static const Color primaryGreen = Color(0xFF4E967B);
  static const Color darkText = Color(0xFF405466);

  @override
  Widget build(BuildContext context) {
    final bool isLost = type == 'lost';
    final bool isSighting = type == 'sighting';

    final title = isLost
        ? 'Mascota Perdida'
        : isSighting
        ? 'Avistamiento'
        : 'Mascota encontrada';

    final name = isLost
        ? 'Max'
        : isSighting
        ? 'No identificado'
        : 'Pluto';

    final details = isLost
        ? 'Perro · Raza: Golden Retriever'
        : isSighting
        ? 'Especie: Gato'
        : 'Macho · Golden Retriever';

    final location = isLost
        ? 'Carrera 53'
        : isSighting
        ? 'Carrera 60'
        : 'Pablo Andrade';

    final description = isLost
        ? 'Visto por última vez corriendo hacia la avenida, parece asustado.'
        : isSighting
        ? 'Visto cerca a la Carrera 60, parece estar perdido.'
        : 'El reporte fue finalizado porque la mascota fue encontrada.';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.97),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFFDDEFE2),
                child: Icon(
                  isSighting ? Icons.pets : Icons.pets,
                  color: primaryGreen,
                  size: 30,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: darkText,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$name · $details',
                        style: const TextStyle(
                          color: Color(0xFF65756C),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'Perdido: 12 Abr 2024, 10:30 AM',
                        style: TextStyle(fontSize: 10),
                      ),
                      Text(
                        'Ubicación: $location',
                        style: const TextStyle(fontSize: 10),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Descripción: $description',
                        style: const TextStyle(fontSize: 10, height: 1.25),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 28,
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Aquí irá el detalle del reporte.'),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: const Text(
                            'Ver Detalle',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
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
          Positioned(
            right: 0,
            top: 0,
            child: GestureDetector(
              onTap: onClose,
              child: const Icon(
                Icons.close,
                size: 19,
                color: Color(0xFF789085),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 295,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.pets,
              size: 42,
              color: Color(0xFF8EB5A5),
            ),
            SizedBox(height: 14),
            Text(
              'No hay reportes disponibles',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF405466),
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Actualmente no hay reportes de mascotas perdidas o avistadas en este mapa.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF77877E),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorStateCard extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorStateCard({
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 285,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_rounded,
              size: 58,
              color: Color(0xFFE96F67),
            ),
            const SizedBox(height: 12),
            const Text(
              'No se pudo cargar el mapa',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF405466),
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ocurrió un problema temporal al cargar la información. Verifica tu conexión e inténtalo nuevamente.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF77877E),
                fontSize: 11,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 30,
              width: 180,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4E967B),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text(
                  'Reintentar',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationBar extends StatelessWidget {
  const _LocationBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      color: Colors.white.withOpacity(0.9),
      child: const Row(
        children: [
          Icon(
            Icons.home,
            size: 16,
            color: Color(0xFF4E967B),
          ),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Ciudad Salitre Occidental, Bogotá',
              style: TextStyle(
                color: Color(0xFF52675C),
                fontSize: 12,
              ),
            ),
          ),
          Icon(
            Icons.keyboard_arrow_up,
            size: 16,
            color: Color(0xFF52675C),
          ),
        ],
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  final VoidCallback onHomeTap;
  final VoidCallback onCreateTap;
  final VoidCallback onProfileTap;

  const _BottomNavigation({
    required this.onHomeTap,
    required this.onCreateTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FBF8),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 5,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                onPressed: onHomeTap,
                icon: const Icon(
                  Icons.home,
                  color: Color(0xFF4E967B),
                  size: 34,
                ),
              ),
              const SizedBox(width: 72),
              IconButton(
                onPressed: onProfileTap,
                icon: const Icon(
                  Icons.person,
                  color: Color(0xFF4E967B),
                  size: 34,
                ),
              ),
            ],
          ),
          Positioned(
            top: -3,
            child: GestureDetector(
              onTap: onCreateTap,
              child: Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFE2E6E1),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 61,
                    height: 61,
                    decoration: const BoxDecoration(
                      color: Color(0xFF73C15A),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.pets,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideMenu extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onLostPets;
  final VoidCallback onMyPets;
  final VoidCallback onFaq;
  final VoidCallback onLogout;
  final VoidCallback onCreateReport;

  const _SideMenu({
    required this.onClose,
    required this.onLostPets,
    required this.onMyPets,
    required this.onFaq,
    required this.onLogout,
    required this.onCreateReport,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: onClose,
          child: Container(
            color: Colors.black.withOpacity(0.25),
          ),
        ),
        Container(
          width: MediaQuery.of(context).size.width * 0.78,
          height: double.infinity,
          color: const Color(0xFFFAFCF7),
          padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
          child: Column(
            children: [
              Row(
                children: [
                  Image.asset(
                    'assets/images/Logo_Principal_AniMap.png',
                    height: 52,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'AniMap',
                    style: TextStyle(
                      color: Color(0xFF405466),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 65),
              _MenuItem(
                text: 'Mis Mascotas',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MyPetsPage(),
                    ),
                  );
                },
              ),
              _MenuItem(
                text: 'Preguntas Frecuentes',
                onTap: onFaq,
              ),
              _MenuItem(
                text: 'Cerrar sesión',
                onTap: onLogout,
              ),
              _MenuItem(
                text: 'Crear reporte',
                onTap: onCreateReport,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _MenuItem({
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(
          color: Color(0xFFC8D5CC),
          thickness: 1,
        ),
        ListTile(
          onTap: onTap,
          title: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

class _DevStateButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DevStateButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.75,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: SizedBox(
          width: 58,
          height: 24,
          child: ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF4E967B),
              elevation: 1,
            ),
            child: Text(
              label,
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ),
      ),
    );
  }
}

class _SimpleMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint background = Paint()
      ..color = const Color(0xFFE5EFE8)
      ..style = PaintingStyle.fill;

    final Paint street = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final Paint mainStreet = Paint()
      ..color = const Color(0xFFECD46B)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), background);

    for (double y = 30; y < size.height; y += 55) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 25), street);
    }

    for (double x = 20; x < size.width; x += 70) {
      canvas.drawLine(Offset(x, 0), Offset(x + 35, size.height), street);
    }

    canvas.drawLine(
      Offset(0, size.height * 0.35),
      Offset(size.width, size.height * 0.55),
      mainStreet,
    );

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Ciudad Salitre\nOccidental',
        style: TextStyle(
          color: Color(0xFF52675C),
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        size.height * 0.38,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}