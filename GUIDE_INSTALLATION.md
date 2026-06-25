# 🏍️ MOTO OFFROAD 4X4 — Guide d'installation

## 1. Installer Flutter (15 minutes)

### Sur Mac
```bash
# 1. Télécharger Flutter
curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.22.0-stable.tar.xz

# 2. Extraire
tar xf flutter_macos_arm64_3.22.0-stable.tar.xz

# 3. Ajouter au PATH (dans ~/.zshrc ou ~/.bash_profile)
export PATH="$HOME/flutter/bin:$PATH"

# 4. Vérifier l'installation
flutter doctor
```

### Sur Windows
1. Télécharger : https://flutter.dev/docs/get-started/install/windows
2. Extraire dans `C:\flutter`
3. Ajouter `C:\flutter\bin` au PATH système
4. Lancer `flutter doctor` dans PowerShell

### Sur Linux
```bash
sudo snap install flutter --classic
flutter doctor
```

---

## 2. Installer Android Studio + SDK Android

1. Télécharger Android Studio : https://developer.android.com/studio
2. Lancer et suivre le setup wizard
3. Installer SDK Android 14 (API 34) via SDK Manager
4. Accepter les licences :
   ```bash
   flutter doctor --android-licenses
   ```

---

## 3. Lancer l'application

```bash
# Aller dans le dossier du projet
cd "APP OFFROAD MOTO 4X4/moto_offroad"

# Télécharger les dépendances
flutter pub get

# Vérifier les appareils connectés
flutter devices

# Lancer sur Android (téléphone connecté en USB ou émulateur)
flutter run

# Build APK de test
flutter build apk --debug
```

---

## 4. Tester sur votre téléphone Android

1. Activer le **Mode développeur** : Paramètres → À propos → taper 7× sur "Numéro de build"
2. Activer le **Débogage USB** : Paramètres → Options développeur → Débogage USB
3. Connecter le téléphone via USB
4. Accepter la demande de débogage sur le téléphone
5. `flutter run` — l'app s'installe automatiquement

---

## 5. Structure du projet

```
moto_offroad/
├── lib/
│   ├── main.dart              ← Point d'entrée
│   ├── app/
│   │   ├── theme.dart         ← Couleurs, styles
│   │   └── router.dart        ← Navigation
│   ├── models/
│   │   ├── trace.dart         ← Modèle trace GPX
│   │   ├── poi.dart           ← Points d'intérêt
│   │   └── rider_profile.dart ← Profil pilote
│   ├── services/
│   │   ├── location_service.dart ← GPS temps réel
│   │   ├── gpx_service.dart      ← Import/export GPX
│   │   └── sos_service.dart      ← SOS, partage
│   ├── providers/             ← État de l'application
│   ├── screens/               ← Écrans principaux
│   └── widgets/               ← Composants réutilisables
└── pubspec.yaml               ← Dépendances
```

---

## 6. Prochaines étapes de développement

- [ ] Configurer les clés API (IGN Géoportail, Google Places, TomTom Fuel)
- [ ] Configurer Firebase (mode groupe temps réel)
- [ ] Ajouter l'écran météo (Open-Meteo + algorithme praticabilité)
- [ ] Ajouter les POI (stations, restaurants, moto shops)
- [ ] Implémenter le mode hors-ligne (MBTiles)
- [ ] Tuto interactif (onboarding)
- [ ] Tests et publication Google Play
