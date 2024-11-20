# Gestionnaire de Swap - Script Bash

Ce script Bash permet de gérer facilement la création, la modification et la suppression de fichiers de swap sous Linux. Il offre également la possibilité de vérifier l'état actuel du swap, d'ajuster les paramètres de swappiness et de créer des fichiers swap de manière interactive.

## Fonctionnalités

1. **Afficher le statut du swap :** Vérifiez si un fichier swap est actif et affichez des informations détaillées sur son utilisation et la mémoire disponible.
2. **Créer un fichier swap :** Créez un fichier swap avec une taille spécifiée par l'utilisateur ou calculée automatiquement en fonction de la taille du disque.
3. **Modifier un fichier swap existant :** Modifiez un fichier swap déjà existant en ajustant sa taille.
4. **Supprimer le swap :** Supprimez un fichier swap existant et réinitialisez les configurations associées.
5. **Ajuster la valeur de swappiness :** Permet à l'utilisateur de modifier la valeur de swappiness pour optimiser l'utilisation de la mémoire.

## Prérequis

Le script nécessite les commandes suivantes pour fonctionner correctement :
- `swapon`
- `swapoff`
- `mkswap`
- `grep`
- `sed`
- `dd`
- `free`

Assurez-vous que ces commandes sont installées sur votre système avant d'exécuter le script.

## Installation

1. Clonez ce dépôt ou téléchargez le script `swap_manager.sh` sur votre machine.

```bash
git clone https://github.com/votre-utilisateur/votre-depot.git
