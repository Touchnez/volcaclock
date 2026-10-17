# VolcaClock (notes de développement)

Petite app de barre de menus qui suit le tempo de djay Pro via Ableton Link et envoie une MIDI clock au Volca Kick par la sortie MIDI DIN du Launch Control 3. Un bouton du Launch Control arme le départ : le Volca démarre sur le prochain temps 1 de djay, un second appui l'arrête.

Le mode d'emploi destiné aux autres utilisateurs est dans LISEZMOI-UTILISATEUR.md ; il est joint à l'app publiée.

## 1. Compiler

1. Dans le Terminal, installe une fois les outils d'Apple : `xcode-select --install`.
2. Tape `cd` suivi d'un espace, glisse le dossier VolcaClock depuis le Finder dans la fenêtre du Terminal, puis Entrée.
3. Lance `bash build.sh`. Au premier lancement, le script télécharge le SDK Ableton Link depuis GitHub. L'app est compilée pour Apple Silicon et Intel, compatible macOS 12 et suivants.
4. L'app se trouve dans `build/VolcaClock.app`.

Traductions : le code garde les textes en français comme clés (`NSLocalizedString`). Les fichiers `Resources/fr.lproj` et `Resources/en.lproj` donnent le texte affiché selon la langue de macOS (anglais par défaut). Pour ajouter un texte, mets-le dans `NSLocalizedString(...)` et ajoute la ligne dans les deux fichiers `Localizable.strings`.

## 2. Publier

`bash release.sh` recompile l'app et crée dans le dossier `release/` deux archives : `VolcaClock-1.0.zip` (l'app, le mode d'emploi utilisateur, la licence) et `VolcaClock-1.0-source.zip` (le code source complet, SDK Link compris). La licence GPL impose de publier les deux ensemble, au même endroit.

Sans compte Apple Developer, l'app n'est signée que localement : macOS la bloque chez les autres utilisateurs, qui doivent l'autoriser dans Réglages Système (la manipulation est décrite dans le mode d'emploi). Avec un compte Apple Developer, la signature et la notarisation suppriment ce blocage :

1. Dans Xcode, Réglages, Comptes, crée un certificat « Developer ID Application ».
2. Enregistre une fois tes identifiants de notarisation : `xcrun notarytool store-credentials volcaclock` (identifiant Apple, identifiant d'équipe, mot de passe d'app créé sur account.apple.com).
3. Lance : `DEVELOPER_ID="Developer ID Application: Ton Nom (EQUIPE)" NOTARY_PROFILE="volcaclock" bash release.sh`

Pour une nouvelle version, augmente `CFBundleShortVersionString` et `CFBundleVersion` dans Info.plist avant de relancer `release.sh`.

## 3. Brancher

Un câble MIDI DIN 5 broches entre la prise MIDI Out du Launch Control 3 et la prise MIDI In du Volca Kick. Le Launch Control reste branché au Mac en USB.

Côté Volca Kick, vérifie dans le manuel (réglages globaux) que la réception de la MIDI clock est active et note son canal MIDI.

## 4. Premier lancement

1. Dans djay Pro, active Ableton Link dans les réglages.
2. Lance VolcaClock (icône métronome dans la barre de menus). Si macOS demande l'accès au réseau local, accepte.
3. La première ligne du menu doit afficher le tempo de djay et au moins un pair.
4. Dans « Sortie MIDI », choisis le port du Launch Control 3 qui correspond à sa prise MIDI Out.
5. « Apprendre le bouton... », puis appuie sur le bouton choisi (non mappé dans djay).
6. Un appui arme (sablier), le Volca part au temps 1 (lecture), un second appui l'arrête.

## 5. Dépannage

Le Volca ne réagit à aucun port : dans Novation Components, active le routage de l'USB vers la sortie MIDI du Launch Control 3.

Le Volca réagit au bouton appris : change le canal du bouton dans Components, ou celui du Volca.

« Link : aucun pair » : Link n'est pas activé dans djay, ou l'accès au réseau local a été refusé (Réglages Système, Confidentialité et sécurité, Réseau local).

Kick en avance ou en retard : menu « Décalage », par pas de 5 ms.
