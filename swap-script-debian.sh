#!/bin/bash

# Vérifier si l'utilisateur est root
if [[ $EUID -ne 0 ]]; then
   echo "Ce script doit être exécuté en tant que root." 1>&2
   exit 1
fi

# Vérification des dépendances
for cmd in swapon swapoff mkswap grep sed dd free; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "Commande requise non trouvée: $cmd" 1>&2
        exit 1
    fi
done

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fonction pour afficher un message d'erreur et quitter le script
function error_exit {
    echo -e "${RED}ERREUR: $1${NC}" 1>&2
    exit 1
}

# Fonction pour afficher un message de succès
function success_message {
    echo -e "${GREEN}$1${NC}"
}

# Fonction pour afficher un avertissement
function warning_message {
    echo -e "${YELLOW}$1${NC}"
}

# Fonction pour obtenir une confirmation
function get_confirmation {
    while true; do
        read -p "$1 (O/N) : " confirm
        case $confirm in
            [OoYy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Veuillez répondre par O ou N.";;
        esac
    done
}

# Fonction pour vérifier si un swap existe déjà
function check_swap {
    if swapon --show | grep -q '/swapfile'; then
        return 0
    fi
    return 1
}

# Fonction pour afficher le statut détaillé du swap
function show_swap_status {
    echo "Status du swap :"
    echo "----------------"
    if check_swap; then
        echo -e "\nSwap actif :"
        swapon --show
        echo -e "\nUtilisation détaillée :"
        free -h
        swappiness=$(cat /proc/sys/vm/swappiness)
        echo -e "\nValeur de swappiness actuelle : $swappiness"
    else
        warning_message "Aucun fichier swap actif."
    fi
    echo -e "\nEspace disque disponible :"
    df -h /
}

# Fonction pour créer et activer un fichier swap
function create_swap {
    if check_swap; then
        error_exit "Un fichier swap existe déjà. Utilisez l'option de modification si vous souhaitez le changer."
    fi

    # Demander à l'utilisateur si il veut spécifier la taille manuellement ou utiliser 10% du disque
    if get_confirmation "Voulez-vous spécifier manuellement la taille du swap"; then
        while true; do
            read -p "Entrez la taille du swap (en Mo) : " swap_size
            if [[ "$swap_size" =~ ^[0-9]+$ ]] && [ "$swap_size" -gt 0 ]; then
                break
            else
                warning_message "La taille spécifiée est invalide. Veuillez entrer un nombre positif."
            fi
        done
        swap_size=$((swap_size * 1024)) # Conversion en Ko
    else
        # Calculer 10% de la taille du disque principal
        disk_size=$(df -k / | tail -1 | awk '{print $2}')
        if [ -z "$disk_size" ]; then
            error_exit "Impossible de récupérer la taille du disque."
        fi
        swap_size=$((disk_size / 10))
        echo "Taille automatique du swap : $((swap_size / 1024)) Mo"
    fi

    # Vérifier si l'espace disque est suffisant (avec marge de sécurité de 5%)
    free_space=$(df -k / | tail -1 | awk '{print $4}')
    if [ "$swap_size" -gt "$((free_space * 95 / 100))" ]; then
        error_exit "Espace disque insuffisant pour créer le fichier swap (gardons une marge de sécurité de 5%)."
    fi

    echo "Création du fichier swap de $((swap_size / 1024)) Mo..."

    # Tentative de création avec fallocate, sinon utiliser dd
    if ! fallocate -l ${swap_size}K /swapfile 2>/dev/null; then
        warning_message "fallocate a échoué, utilisation de dd comme alternative..."
        dd if=/dev/zero of=/swapfile bs=1K count=$swap_size status=progress || error_exit "Erreur lors de la création du fichier swap."
    fi

    # Définir les bonnes permissions
    chmod 600 /swapfile || error_exit "Erreur lors de la modification des permissions du fichier swap."

    # Initialiser le swap
    mkswap /swapfile || error_exit "Erreur lors de l'initialisation du swap."

    # Désactiver le swap existant si présent
    swapoff /swapfile 2>/dev/null

    # Activer le swap
    swapon /swapfile || error_exit "Erreur lors de l'activation du swap."

    # Ajouter le swap à /etc/fstab s'il n'existe pas déjà
    if ! grep -q "^/swapfile" /etc/fstab; then
        cp /etc/fstab /etc/fstab.bak
        echo "/swapfile none swap sw 0 0" >> /etc/fstab || error_exit "Erreur lors de l'ajout de l'entrée dans /etc/fstab."
    fi

    # Ajuster la valeur de swappiness
    if get_confirmation "Voulez-vous ajuster la valeur de swappiness (actuellement: $(cat /proc/sys/vm/swappiness))"; then
        while true; do
            read -p "Entrez la nouvelle valeur de swappiness (0-100) : " swappiness
            if [[ "$swappiness" =~ ^[0-9]+$ ]] && [ "$swappiness" -ge 0 ] && [ "$swappiness" -le 100 ]; then
                if [ -d "/etc/sysctl.d" ]; then
                    echo "vm.swappiness=$swappiness" > /etc/sysctl.d/99-swappiness.conf
                    sysctl -p /etc/sysctl.d/99-swappiness.conf
                else
                    warning_message "/etc/sysctl.d n'existe pas, ajout dans /etc/sysctl.conf"
                    if ! grep -q "^vm.swappiness" /etc/sysctl.conf; then
                        echo "vm.swappiness=$swappiness" >> /etc/sysctl.conf
                    else
                        sed -i "s/^vm.swappiness=.*/vm.swappiness=$swappiness/" /etc/sysctl.conf
                    fi
                    sysctl -p
                fi
                break
            else
                warning_message "Valeur invalide. Veuillez entrer un nombre entre 0 et 100."
            fi
        done
    fi

    # Vérification finale
    success_message "Le swap a été créé et activé avec succès."
    show_swap_status
}

# Fonction pour modifier la taille du swap existant
function modify_swap {
    if ! check_swap; then
        error_exit "Aucun swap existant à modifier."
    fi

    if ! get_confirmation "Êtes-vous sûr de vouloir modifier le swap existant"; then
        echo "Opération annulée."
        return
    fi

    # Faire une sauvegarde de fstab
    cp /etc/fstab /etc/fstab.bak || warning_message "Impossible de créer une sauvegarde de fstab"

    # Désactiver le swap actuel
    swapoff /swapfile || error_exit "Erreur lors de la désactivation du swap."

    # Supprimer l'ancienne entrée fstab
    sed -i '/^\/swapfile/d' /etc/fstab || error_exit "Erreur lors de la suppression de l'entrée dans /etc/fstab."

    # Supprimer le fichier swap existant
    rm /swapfile || error_exit "Erreur lors de la suppression du fichier swap existant."

    # Recréer et activer le swap avec la nouvelle taille
    success_message "Le fichier swap a été supprimé, création du nouveau swap..."
    create_swap
}

# Fonction pour supprimer le swap
function delete_swap {
    if ! check_swap; then
        error_exit "Aucun swap existant à supprimer."
    fi

    if ! get_confirmation "Êtes-vous sûr de vouloir supprimer le swap"; then
        echo "Opération annulée."
        return
    fi

    # Faire une sauvegarde de fstab
    cp /etc/fstab /etc/fstab.bak || warning_message "Impossible de créer une sauvegarde de fstab"

    # Désactiver le swap
    swapoff /swapfile || error_exit "Erreur lors de la désactivation du swap."

    # Supprimer l'entrée fstab
    sed -i '/^\/swapfile/d' /etc/fstab || error_exit "Erreur lors de la suppression de l'entrée dans /etc/fstab."

    # Supprimer le fichier swap
    rm /swapfile || error_exit "Erreur lors de la suppression du fichier swap."

    success_message "Le swap a été supprimé avec succès."
}

# Menu interactif
while true; do
    echo -e "\nGestion du fichier swap"
    echo "====================="
    echo "1. Afficher le status du swap"
    echo "2. Créer un fichier swap"
    echo "3. Modifier un fichier swap existant"
    echo "4. Supprimer le swap"
    echo "5. Quitter"
    read -p "Votre choix : " choice

    case $choice in
        1)
            show_swap_status
            ;;
        2)
            create_swap
            ;;
        3)
            modify_swap
            ;;
        4)
            delete_swap
            ;;
        5)
            success_message "Au revoir!"
            exit 0
            ;;
        *)
            warning_message "Choix invalide. Veuillez réessayer."
            ;;
    esac
done