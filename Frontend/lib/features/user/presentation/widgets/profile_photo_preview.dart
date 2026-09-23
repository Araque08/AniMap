import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

typedef ProfilePhotoUpload = Future<Map<String, dynamic>> Function(XFile image);

enum ProfilePhotoPreviewAction { cancel, chooseAnother, uploaded }

class ProfilePhotoPreviewResult {
  final ProfilePhotoPreviewAction action;
  final Map<String, dynamic>? profile;

  const ProfilePhotoPreviewResult(this.action, [this.profile]);
}

class ProfilePhotoPreviewDialog extends StatefulWidget {
  final XFile image;
  final ProfilePhotoUpload uploader;

  const ProfilePhotoPreviewDialog({
    super.key,
    required this.image,
    required this.uploader,
  });

  @override
  State<ProfilePhotoPreviewDialog> createState() =>
      _ProfilePhotoPreviewDialogState();
}

class _ProfilePhotoPreviewDialogState extends State<ProfilePhotoPreviewDialog> {
  late final Future<Uint8List> _bytes = widget.image.readAsBytes();
  bool _uploading = false;
  String? _error;

  Future<void> _upload() async {
    if (_uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final profile = await widget.uploader(widget.image);
      if (!mounted) return;
      Navigator.pop(
        context,
        ProfilePhotoPreviewResult(ProfilePhotoPreviewAction.uploaded, profile),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_uploading,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Previsualizar foto',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Así se verá tu nueva foto de perfil.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64736B)),
                ),
                const SizedBox(height: 22),
                Container(
                  width: 220,
                  height: 220,
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 18,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: FutureBuilder<Uint8List>(
                      future: _bytes,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const ColoredBox(
                            color: Color(0xFFE4EEE7),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return Image.memory(
                          snapshot.data!,
                          key: const ValueKey('profile-photo-preview'),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const ColoredBox(
                            color: Color(0xFFE4EEE7),
                            child: Icon(Icons.broken_image_outlined, size: 48),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 22),
                if (_uploading)
                  const Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 10),
                      Text('Subiendo foto…'),
                    ],
                  )
                else
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(
                          context,
                          const ProfilePhotoPreviewResult(
                            ProfilePhotoPreviewAction.cancel,
                          ),
                        ),
                        child: const Text('Cancelar'),
                      ),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(
                          context,
                          const ProfilePhotoPreviewResult(
                            ProfilePhotoPreviewAction.chooseAnother,
                          ),
                        ),
                        child: const Text('Elegir otra'),
                      ),
                      FilledButton(
                        onPressed: _upload,
                        child: const Text('Usar esta foto'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
