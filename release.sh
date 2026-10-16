#!/bin/bash
# Prepare une version publiable de VolcaClock dans le dossier release/ :
#   VolcaClock-<version>.zip         l'app prete a telecharger, avec mode d'emploi et licence
#   VolcaClock-<version>-source.zip  le code source complet, exige par la licence GPL
#
# Signature Apple (facultative, necessite un compte Apple Developer) :
#   DEVELOPER_ID="Developer ID Application: Prenom Nom (EQUIPE)"  identite de signature
#   NOTARY_PROFILE="volcaclock"                                    profil cree avec
#     xcrun notarytool store-credentials
# Exemple : DEVELOPER_ID="..." NOTARY_PROFILE="volcaclock" bash release.sh
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
OUT="release"
APP="build/VolcaClock.app"
STAGE="$OUT/VolcaClock-$VERSION"

bash build.sh

rm -rf "$OUT"
mkdir -p "$STAGE"

# Texte complet de la GPL v2, fourni par le depot Ableton Link.
GPL_FILE=$(find Vendor/link -maxdepth 1 -iname "*gpl*" | head -n 1)
if [ -z "$GPL_FILE" ]; then
  echo "Texte de la GPL introuvable dans Vendor/link : copie-le a la main dans $STAGE." >&2
  exit 1
fi

# Signature
if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "Signature Developer ID..."
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "Notarisation aupres d'Apple (quelques minutes)..."
    ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
    xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm "$OUT/notarize.zip"
    SIGNED="signee et notarisee"
  else
    SIGNED="signee, NON notarisee"
  fi
else
  SIGNED="NON signee (signature locale seulement)"
fi

# Paquet utilisateur
cp -R "$APP" "$STAGE/"
cp README.md "$STAGE/README.md"
cp LISEZMOI-UTILISATEUR.md "$STAGE/LISEZMOI.md"
cp LICENSE "$STAGE/LICENSE"
cp "$GPL_FILE" "$STAGE/GPL-2.0.md"
(cd "$OUT" && ditto -c -k --keepParent "VolcaClock-$VERSION" "VolcaClock-$VERSION.zip")
rm -rf "$STAGE"

# Paquet source complet (avec le SDK Link a la version utilisee, sans historique git)
SRC="$OUT/VolcaClock-$VERSION-source"
mkdir -p "$SRC"
cp -R Sources Info.plist build.sh release.sh LICENSE README.md LISEZMOI.md LISEZMOI-UTILISATEUR.md .gitignore "$SRC/"
rsync -a --exclude ".git" Vendor "$SRC/"
git -C Vendor/link rev-parse HEAD > "$SRC/LINK_VERSION.txt"
(cd "$OUT" && ditto -c -k --keepParent "VolcaClock-$VERSION-source" "VolcaClock-$VERSION-source.zip")
rm -rf "$SRC"

echo ""
echo "Termine. App $SIGNED."
ls -lh "$OUT"
