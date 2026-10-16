# VolcaClock 1.0

VolcaClock suit le tempo d'une application compatible Ableton Link (djay Pro, par exemple) et envoie une MIDI clock vers une machine externe, comme un Korg Volca, avec un départ calé sur le premier temps de la mesure. L'app vit dans la barre de menus et ne consomme presque rien.

Projet indépendant, sans lien avec Korg, Novation, Ableton ni Algoriddim.

## Ce qu'il faut

Un Mac sous macOS 12 ou plus récent (Apple Silicon ou Intel), une application compatible Ableton Link, et une sortie MIDI vers ta machine : interface USB MIDI, ou contrôleur doté d'une prise MIDI Out capable de relayer ce que le Mac lui envoie.

## Installation

1. Décompresse le fichier téléchargé et glisse VolcaClock.app dans le dossier Applications.
2. Lance VolcaClock. Si macOS indique que l'app ne peut pas être vérifiée, ouvre Réglages Système, Confidentialité et sécurité, descends jusqu'au message concernant VolcaClock et clique sur « Ouvrir quand même ». Ne fais cette manipulation que si tu as téléchargé l'app depuis sa page officielle.
3. Si macOS demande l'accès au réseau local, accepte : Ableton Link communique par ce biais, même entre deux apps du même Mac. VolcaClock n'utilise pas internet et ne collecte aucune donnée.

## Utilisation

1. Active Ableton Link dans ton application (dans djay Pro, dans les réglages).
2. Clique sur l'icône métronome de la barre de menus : la première ligne affiche le tempo et le nombre de pairs Link.
3. Dans « Sortie MIDI », choisis le port relié à ta machine.
4. Pour piloter le départ depuis un contrôleur, clique sur « Apprendre le bouton... » et appuie sur le bouton voulu. Sinon, utilise « Démarrer / Arrêter » dans le menu.
5. Un appui arme le départ (icône sablier) ; la machine démarre au prochain temps 1 (icône lecture). Un second appui l'arrête.

La clock est envoyée en continu, même à l'arrêt, pour que la machine connaisse le tempo avant le départ. Si elle sonne légèrement en avance ou en retard, ajuste « Décalage » par pas de 5 ms (négatif pour avancer).

## Problèmes fréquents

« Link : aucun pair » : Link n'est pas activé dans ton application, ou l'accès au réseau local a été refusé (Réglages Système, Confidentialité et sécurité, Réseau local).

La machine ne réagit pas : vérifie qu'elle accepte la MIDI clock (voir son manuel) et, si tu passes par un contrôleur, que celui-ci relaie bien les messages du Mac vers sa prise MIDI Out.

La machine réagit quand tu appuies sur le bouton appris : ton contrôleur envoie aussi ce bouton sur sa sortie MIDI, sur le canal qu'écoute la machine. Change l'un des deux canaux.

## Licence

VolcaClock est un logiciel libre distribué sous licence GNU GPL version 2 ou ultérieure (voir LICENSE et GPL-2.0.md), sans aucune garantie. Il intègre Ableton Link (GPL v2 ou ultérieure) et asio (licence Boost). Le code source complet est publié à côté de l'app.
