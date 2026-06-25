import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../app/theme.dart';
import '../providers/trace_provider.dart';

/// Bottom sheet — Import d'un fichier GPX
class GpxImportSheet extends StatefulWidget {
  const GpxImportSheet({super.key});

  @override
  State<GpxImportSheet> createState() => _GpxImportSheetState();
}

class _GpxImportSheetState extends State<GpxImportSheet> {
  final _urlCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() { _urlCtrl.dispose(); super.dispose(); }

  Future<void> _pickFile() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gpx'],
      );
      if (result == null || result.files.single.path == null) {
        setState(() => _loading = false);
        return;
      }
      final trace = context.read<TraceProvider>();
      final ok = await trace.importFromFile(result.files.single.path!);
      if (mounted) {
        if (ok) Navigator.pop(context);
        else setState(() { _loading = false; _error = trace.error; });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Erreur lors de l\'import'; });
    }
  }

  Future<void> _importFromUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() { _loading = true; _error = null; });

    final trace = context.read<TraceProvider>();
    final ok = await trace.importFromUrl(url);
    if (mounted) {
      if (ok) Navigator.pop(context);
      else setState(() { _loading = false; _error = trace.error; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poignée
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A3E),
              borderRadius: BorderRadius.circular(2),
            ),
          )),
          const SizedBox(height: 16),
          const Text('IMPORTER UNE TRACE GPX', style: TextStyle(
            fontFamily: 'Rajdhani', fontSize: 16, fontWeight: FontWeight.w700,
            color: AppColors.orange, letterSpacing: 1,
          )),
          const SizedBox(height: 16),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.red.withOpacity(.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.red.withOpacity(.3)),
              ),
              child: Text(_error!, style: const TextStyle(color: AppColors.statusRed, fontSize: 12)),
            ),
            const SizedBox(height: 12),
          ],

          // Import fichier
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _pickFile,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Choisir un fichier .gpx'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF2A2A3E)),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),
          const SizedBox(height: 12),

          const Row(children: [
            Expanded(child: Divider(color: Color(0xFF2A2A3E))),
            Padding(padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('ou depuis une URL', style: TextStyle(color: AppColors.textMuted, fontSize: 11))),
            Expanded(child: Divider(color: Color(0xFF2A2A3E))),
          ]),
          const SizedBox(height: 12),

          // Import URL
          Row(children: [
            Expanded(
              child: TextField(
                controller: _urlCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'https://wikiloc.com/… ou lien TET, Imarod',
                  hintStyle: TextStyle(fontSize: 12),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _loading ? null : _importFromUrl,
              style: ElevatedButton.styleFrom(minimumSize: const Size(60, 48)),
              child: _loading
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download),
            ),
          ]),
          const SizedBox(height: 8),
          const Text('Compatible : Wikiloc, TET (Trans Euro Trail), Imarod, et tout site GPX standard',
            style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
