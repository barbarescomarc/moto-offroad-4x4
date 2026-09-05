# MOTO OFFROAD 4X4

Application GPS pour moto tout-terrain et 4x4 (France & Europe) : carte OSM/IGN/satellite,
enregistrement et édition de traces, guidage, météo, autonomie carburant, et un mode
« Solo sécurisé » avec contacts de confiance, détection de chute et suivi de trajet.

## Télécharger (Android)

Dernière version publiée :
https://github.com/barbarescomarc/moto-offroad-4x4/releases/latest/download/moto-offroad.apk

Autorisez l'installation depuis cette source lorsque le téléphone le demande.

## iOS

Le projet iOS compile (workflow `build-ios.yml`) mais n'est pas encore distribué.
Deux fonctions Android n'existent pas sur iOS et y sont masquées : l'envoi de SMS
sans intervention de l'utilisateur et la réponse automatique aux appels entrants —
Apple ne les accorde à aucune application tierce. Sur iOS, l'alerte de chute passe
donc par le serveur (e-mail aux contacts).

## Développement

```bash
flutter pub get
flutter test
flutter analyze
```

`lib/config/api_keys.dart` est gitignoré : le recréer en local (les workflows CI le
génèrent eux-mêmes). Les APK sont compilés par GitHub Actions, pas en local.
