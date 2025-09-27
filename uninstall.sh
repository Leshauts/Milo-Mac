#!/bin/bash

# Script de désinstallation de Milo Mac et roc-vad
# Version 1.0

set -e  # Arrêter en cas d'erreur

echo "=============================================="
echo "Désinstallation de Milo Mac et roc-vad"
echo "=============================================="
echo ""

# Vérifier les permissions admin
if [ "$EUID" -eq 0 ]; then
    echo "Erreur: Ne pas exécuter ce script avec sudo directement"
    echo "Le script demandera les permissions admin quand nécessaire"
    exit 1
fi

# Arrêter Milo Mac s'il tourne
echo "1. Arrêt de Milo Mac..."
killall "Milo Mac" 2>/dev/null && echo "   Milo Mac arrêté" || echo "   Milo Mac n'était pas en cours d'exécution"

# Vérifier si roc-vad est installé
if command -v roc-vad &> /dev/null || [ -f "/usr/local/bin/roc-vad" ]; then
    echo ""
    echo "2. Désinstallation de roc-vad..."
    echo "   (Mot de passe administrateur requis)"
    
    if [ -f "/usr/local/bin/roc-vad" ]; then
        sudo /usr/local/bin/roc-vad uninstall
        echo "   roc-vad désinstallé"
    else
        echo "   roc-vad introuvable, passage à l'étape suivante"
    fi
else
    echo ""
    echo "2. roc-vad n'est pas installé, passage à l'étape suivante"
fi

# Supprimer l'application Milo Mac
echo ""
echo "3. Suppression de l'application Milo Mac..."

if [ -d "/Applications/Milo Mac.app" ]; then
    rm -rf "/Applications/Milo Mac.app"
    echo "   Application supprimée de /Applications/"
else
    echo "   Application introuvable dans /Applications/"
fi

# Nettoyer les fichiers de configuration
echo ""
echo "4. Nettoyage des fichiers de configuration..."

# Trouver et supprimer les préférences Milo Mac
find ~/Library/Preferences/ -name "*Milo*Mac*" -type f 2>/dev/null | while read file; do
    rm -f "$file"
    echo "   Supprimé: $(basename "$file")"
done

# Trouver et supprimer les caches
find ~/Library/Caches/ -name "*Milo*Mac*" -type d 2>/dev/null | while read dir; do
    rm -rf "$dir"
    echo "   Supprimé: $(basename "$dir")"
done

# Supprimer le dossier Application Support
if [ -d ~/Library/Application\ Support/Milo\ Mac/ ]; then
    rm -rf ~/Library/Application\ Support/Milo\ Mac/
    echo "   Dossier de support supprimé"
fi

# Nettoyer les LaunchAgents (démarrage automatique)
find ~/Library/LaunchAgents/ -name "*Milo*Mac*" -type f 2>/dev/null | while read file; do
    rm -f "$file"
    echo "   Agent de démarrage supprimé: $(basename "$file")"
done

echo ""
echo "=============================================="
echo "Désinstallation terminée avec succès!"
echo ""
echo "IMPORTANT: Redémarrez votre Mac pour finaliser"
echo "la suppression complète des services audio."
echo "=============================================="
