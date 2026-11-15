import 'package:flutter/material.dart';

import '../../services/api_client.dart';

/// US-28 : bandeau « hors ligne » et nombre de modifications en attente de synchronisation.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([apiClient.offline, apiClient.pendingWrites]),
    builder: (context, _) {
      final offline = apiClient.offline.value;
      final pending = apiClient.pendingWrites.value;
      if (!offline && pending == 0) return const SizedBox.shrink();
      final text = offline
          ? 'Hors ligne : données enregistrées sur le téléphone'
                '${pending > 0 ? ' · $pending modification(s) à envoyer' : ''}'
          : '$pending modification(s) en attente d’envoi';
      return Material(
        color: offline ? Colors.orange.shade100 : Colors.blue.shade50,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(
                  offline ? Icons.cloud_off : Icons.cloud_upload_outlined,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(text, style: const TextStyle(fontSize: 13)),
                ),
                if (pending > 0)
                  TextButton(
                    onPressed: () async {
                      final rejected = await apiClient.syncPending();
                      if (rejected.isNotEmpty && context.mounted) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Non synchronisé : ${rejected.join(' ; ')}',
                            ),
                          ),
                        );
                      }
                    },
                    child: const Text('Synchroniser'),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
