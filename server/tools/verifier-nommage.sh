#!/usr/bin/env bash
#
# Verifie que la bibliotheque respecte les conventions de nommage d'Emby.
#
# Lecture seule : ce script ne renomme, ne deplace et ne supprime jamais rien.
# Il enumere ce qui cloche et sort en code 1 s'il a trouve quelque chose, pour
# pouvoir etre enchaine apres un rangement.
#
# Conventions verifiees, d'apres emby.media/support/articles/Movie-Naming.html
# et TV-Naming.html :
#
#   Films/Titre (Annee) [tmdbid=123]/Titre (Annee) [tmdbid=123].mkv
#   Films/Titre (Annee) [tmdbid=123]/Titre (Annee) [tmdbid=123] - 1080p.mkv
#   Series/Titre (Annee) [tmdbid=123]/Season 01/Titre S01E01.mkv
#
# Le tag utilise le signe EGAL : c'est la forme documentee par Emby. Jellyfin
# attend un tiret. Ne pas « corriger » l'un en l'autre sans savoir lequel des
# deux serveurs lit la bibliotheque.
#
# Usage : verifier-nommage.sh [racine]        (defaut : /srv/nas1/Emby)

set -uo pipefail

RACINE="${1:-/srv/nas1/Emby}"
FILMS="$RACINE/Films"
SERIES="$RACINE/Series"

anomalies=0

signale() {
  printf '  %s\n' "$1"
  anomalies=$((anomalies + 1))
}

titre() {
  printf '\n== %s\n' "$1"
}

# Extensions video reconnues par Emby, minuscules. Le reste (nfo, srt, jpg) est
# legitime a cote d'un film et ne doit pas etre signale.
est_video() {
  case "${1,,}" in
    *.mkv | *.mp4 | *.avi | *.m4v | *.mov | *.wmv | *.ts | *.m2ts) return 0 ;;
    *) return 1 ;;
  esac
}

# Sous-dossiers d'extras reconnus par Emby : leur contenu echappe aux regles.
est_extras() {
  case "${1,,}" in
    extras | specials | trailers | "deleted scenes" | interviews | \
      "behind the scenes" | "featurettes" | "shorts" | "scenes" | "samples") return 0 ;;
    *) return 1 ;;
  esac
}

if [ ! -d "$RACINE" ]; then
  printf 'Racine introuvable : %s\n' "$RACINE" >&2
  exit 2
fi

# ---------------------------------------------------------------- Films

titre "Films : dossiers ne suivant pas Titre (Annee) [tmdbid=N]"
if [ -d "$FILMS" ]; then
  while IFS= read -r -d '' d; do
    nom=$(basename "$d")
    [[ "$nom" =~ ^.+\ \([0-9]{4}\)\ \[tmdbid=[0-9]+\]$ ]] || signale "$nom"
  done < <(find "$FILMS" -mindepth 1 -maxdepth 1 -type d -print0)
else
  signale "repertoire absent : $FILMS"
fi

titre "Films : fichiers video dont le nom ne reprend pas celui du dossier"
if [ -d "$FILMS" ]; then
  while IFS= read -r -d '' d; do
    nom=$(basename "$d")
    while IFS= read -r -d '' f; do
      parent=$(basename "$(dirname "$f")")
      [ "$parent" != "$nom" ] && est_extras "$parent" && continue
      base=$(basename "$f")
      est_video "$base" || continue
      # Accepte « Dossier.ext » et « Dossier - variante.ext » (multi-version).
      [[ "$base" == "$nom".* || "$base" == "$nom"\ -\ * ]] || signale "$nom/$base"
    done < <(find "$d" -type f -print0)
  done < <(find "$FILMS" -mindepth 1 -maxdepth 1 -type d -print0)
fi

# --------------------------------------------------------------- Series

titre "Series : dossiers ne suivant pas Titre (Annee) [tmdbid=N]"
if [ -d "$SERIES" ]; then
  while IFS= read -r -d '' d; do
    nom=$(basename "$d")
    [[ "$nom" =~ ^.+\ \([0-9]{4}\)\ \[tmdbid=[0-9]+\]$ ]] || signale "$nom"
  done < <(find "$SERIES" -mindepth 1 -maxdepth 1 -type d -print0)

  titre "Series : fichiers a la racine, hors de toute serie"
  while IFS= read -r -d '' f; do
    signale "$(basename "$f")"
  done < <(find "$SERIES" -mindepth 1 -maxdepth 1 -type f -print0)

  titre "Series : dossiers de saison mal nommes (attendu « Season NN » ou « Specials »)"
  while IFS= read -r -d '' s; do
    nom=$(basename "$s")
    [[ "$nom" =~ ^(Season\ [0-9]{2}|Season\ 0|Specials)$ ]] || \
      signale "$(basename "$(dirname "$s")")/$nom"
  done < <(find "$SERIES" -mindepth 2 -maxdepth 2 -type d -print0)

  titre "Series : episodes sans motif SxxEyy"
  while IFS= read -r -d '' f; do
    base=$(basename "$f")
    est_video "$base" || continue
    [[ "$base" =~ [Ss][0-9]{2}[Ee][0-9]{2} ]] || signale "$base"
  done < <(find "$SERIES" -mindepth 3 -type f -print0)
else
  signale "repertoire absent : $SERIES"
fi

# ------------------------------------------------------------- Residus

titre "Residus de telechargement dans la bibliotheque"
for motif in '*.parts' '*.!qB' '*Torrent911*' '*OxTorrent*' '*Wawacity*' '*.unwanted*'; do
  while IFS= read -r -d '' f; do
    signale "${f#"$RACINE"/}"
  done < <(find "$FILMS" "$SERIES" -name "$motif" -print0 2>/dev/null)
done

# ------------------------------------------------------------ Doublons

titre "Doublons de taille exacte dans un meme dossier"
# Deux fichiers de taille identique cote a cote sont presque toujours la meme
# copie sous deux noms : exFAT n'a pas de liens durs, l'espace est reellement
# occupe deux fois.
while IFS= read -r -d '' d; do
  find "$d" -maxdepth 1 -type f -printf '%s\n' 2>/dev/null | sort | uniq -d | \
    while read -r taille; do
      [ -n "$taille" ] || continue
      signale "$(basename "$d") : $(find "$d" -maxdepth 1 -type f -size "${taille}c" \
        -printf '%f, ' 2>/dev/null | sed 's/, $//') (${taille} octets chacun)"
    done
done < <(find "$FILMS" "$SERIES" -mindepth 1 -type d -print0 2>/dev/null)

# ------------------------------------------------------------- Verdict

printf '\n'
if [ "$anomalies" -eq 0 ]; then
  printf 'Aucune anomalie.\n'
  exit 0
fi
printf '%d anomalie(s).\n' "$anomalies"
exit 1
