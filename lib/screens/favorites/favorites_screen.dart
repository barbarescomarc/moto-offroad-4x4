// lib/screens/favorites/favorites_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../models/favorite_place.dart';
import '../../providers/favorites_provider.dart';

// Retourne le favori choisi via Navigator.pop, pour que l'appelant démarre
// le guidage dessus — voir map_screen.dart.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final favorites = context.watch<FavoritesProvider>();
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(title: const Text('FAVORIS')),
      body: favorites.places.isEmpty
          ? const Center(
              child: Text(
                'Aucun favori — ajoute un point depuis la carte',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              itemCount: favorites.places.length,
              itemBuilder: (_, i) {
                final p = favorites.places[i];
                return ListTile(
                  leading: const Icon(Icons.star, color: AppColors.orange),
                  title: Text(p.name, style: const TextStyle(color: Colors.white)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.statusRed),
                    onPressed: () => favorites.remove(p.id),
                  ),
                  onTap: () => Navigator.of(context).pop<FavoritePlace>(p),
                );
              },
            ),
    );
  }
}
