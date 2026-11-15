import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/api_config.dart';
import '../../services/api_client.dart';

/// US-25 : photos jointes à une intervention (prise de vue ou galerie, envoi compressé).
class InterventionPhotos extends StatefulWidget {
  const InterventionPhotos({
    super.key,
    required this.apiClient,
    required this.interventionId,
    required this.canAdd,
    this.picker,
  });

  final ApiClient apiClient;
  final int interventionId;
  final bool canAdd;
  final ImagePicker? picker;

  @override
  State<InterventionPhotos> createState() => _InterventionPhotosState();
}

class _InterventionPhotosState extends State<InterventionPhotos> {
  List<Map<String, dynamic>> _photos = const [];
  bool _busy = false;
  String? _error;

  String get _base => '/interventions/${widget.interventionId}/photos';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.apiClient.request('GET', _base);
      if (mounted) {
        setState(
          () =>
              _photos = (r as List).whereType<Map<String, dynamic>>().toList(),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = e is ApiException ? e.message : 'Photos indisponibles.',
        );
      }
    }
  }

  Future<void> _add(ImageSource source) async {
    final picker = widget.picker ?? ImagePicker();
    final file = await picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await file.readAsBytes();
      await widget.apiClient.upload(_base, 'photo', bytes, file.name);
      await _load();
    } catch (e) {
      setState(
        () => _error = e is ApiException ? e.message : 'Envoi impossible.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(Map<String, dynamic> photo) => showDialog<void>(
    context: context,
    builder: (_) =>
        Dialog(child: InteractiveViewer(child: _image(photo, BoxFit.contain))),
  );

  Widget _image(Map<String, dynamic> photo, BoxFit fit) => Image.network(
    '${ApiConfig.baseUrl}$_base/${photo['id']}/fichier',
    headers: widget.apiClient.authHeaders,
    fit: fit,
    errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Photos (${_photos.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (widget.canAdd) ...[
            IconButton(
              tooltip: 'Prendre une photo',
              onPressed: _busy ? null : () => _add(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
            ),
            IconButton(
              tooltip: 'Choisir dans la galerie',
              onPressed: _busy ? null : () => _add(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
            ),
          ],
        ],
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (_photos.isNotEmpty)
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _open(_photos[i]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 90,
                  height: 90,
                  child: _image(_photos[i], BoxFit.cover),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
