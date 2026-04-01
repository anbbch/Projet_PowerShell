# Générateur et gestionnaire de mots de passe sécurisé

Script PowerShell permettant de générer des mots de passe sécurisés, d'analyser leur robustesse, de gérer des listes d'utilisateurs et de stocker les mots de passe de manière chiffrée, via un menu interactif.

---

## Lancement

```powershell
.\password_manager.ps1
```

---

## Options du menu

| N° | Option | Description |
|----|--------|-------------|
| 1 | Générer un mot de passe | Saisir la longueur souhaitée (minimum 7). Le mot de passe s'affiche avec son score de robustesse et est mémorisé pour un export éventuel. |
| 2 | Tester la force d'un mot de passe | Analyse un mot de passe existant et retourne un score ainsi qu'un niveau : `Weak`, `Medium`, `Strong` ou `Very Strong`. |
| 3 | Générer une liste de mots de passe | Lit un fichier `.txt` avec un nom d'utilisateur par ligne et génère un mot de passe pour chacun. Appuyer sur Entrée pour utiliser `Downloads\users.txt`. Si le fichier est introuvable, saisir un nombre de mots de passe à générer. Les résultats s'affichent dans le terminal et sont exportés automatiquement dans `Downloads\users.csv`. |
| 4 | Exporter les mots de passe | Exporte les mots de passe mémorisés en CSV. Appuyer sur Entrée pour enregistrer dans `Downloads\passwords.csv`. Si le fichier existe déjà, un suffixe est ajouté automatiquement (`passwords1.csv`, `passwords2.csv`…). |
| 5 | Déposer au coffre-fort | Chiffre un mot de passe et l'enregistre dans un fichier texte via DPAPI (Windows). Le fichier ne peut être relu que sur la même machine par le même utilisateur. |
| 6 | Documentation | Affiche l'aide du script dans le terminal. |
| 7 | Quitter | Ferme le programme. |

---

## Format du fichier utilisateurs (option 3)

Fichier `.txt` avec un nom par ligne :

```
Alice
Bob
Charlie
```

---

## Système de score de robustesse

| Critère | Points |
|---------|--------|
| Longueur ≥ 12 caractères | +2 |
| Contient une majuscule (A-Z) | +1 |
| Contient une minuscule (a-z) | +1 |
| Contient un chiffre (0-9) | +1 |
| Contient un caractère spécial | +2 |
| Caractères répétés consécutifs | -1 |

| Score | Niveau |
|-------|--------|
| 0 – 2 | `Weak` |
| 3 – 4 | `Medium` |
| 5 – 6 | `Strong` |
| 7+ | `Very Strong` |

---

## Notes techniques

- La génération aléatoire utilise `System.Security.Cryptography.RandomNumberGenerator`, plus sécurisé que `Get-Random`.
- Le coffre-fort utilise le chiffrement DPAPI Windows (`ConvertFrom-SecureString`) : le fichier chiffré n'est lisible que sur la même machine par le même utilisateur.
- Chaque mot de passe généré contient toujours au moins une majuscule, une minuscule, un chiffre et un caractère spécial.
- La longueur minimale est de 7 caractères — elle est corrigée automatiquement si une valeur inférieure est saisie.
