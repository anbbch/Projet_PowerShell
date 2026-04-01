# ================================
# Variables globales
# ================================
$Global:PasswordResults = @()

# ================================
# Étape 1 + 2 : Génération sécurisée
# ================================
function Get-SecureRandomIndex {
    param (
        [int]$Max
    )

    if ($Max -le 0) {
        throw "La valeur Max doit être supérieure à 0."
    }

    $randomNumberGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 4

    # Rejection sampling : élimine le biais statistique du modulo
    $limit = [uint32]::MaxValue - ([uint32]::MaxValue % [uint32]$Max)
    do {
        $randomNumberGenerator.GetBytes($bytes)
        $value = [BitConverter]::ToUInt32($bytes, 0)
    } while ($value -ge $limit)

    return $value % $Max
}

function Get-SecureRandomChar {
    param (
        [string]$Characters
    )

    $index = Get-SecureRandomIndex -Max $Characters.Length
    return $Characters[$index]
}

function Shuffle-Characters {
    param (
        [char[]]$Characters
    )

    $list = New-Object System.Collections.Generic.List[char]
    foreach ($c in $Characters) { $list.Add($c) }

    $shuffled = New-Object System.Collections.Generic.List[char]

    while ($list.Count -gt 0) {
        $j = Get-SecureRandomIndex -Max $list.Count
        $shuffled.Add($list[$j])
        $list.RemoveAt($j)
    }

    return -join $shuffled
}

function New-Password {
    param (
        [int]$Length = 16,
        [switch]$Uppercase,
        [switch]$Lowercase,
        [switch]$Numbers,
        [switch]$SpecialChars
    )

    if (-not $Uppercase -and -not $Lowercase -and -not $Numbers -and -not $SpecialChars) {
        $Uppercase = $true
        $Lowercase = $true
        $Numbers = $true
        $SpecialChars = $true
    }

    $upperChars      = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    $lowerChars      = "abcdefghijklmnopqrstuvwxyz"
    $numberChars     = "0123456789"
    $specialCharsSet = "!@#$%^&*()-_=+[]{};:,.?/"

    $allChars      = ""
    $requiredChars = @()

    if ($Uppercase) {
        $allChars += $upperChars
        $requiredChars += (Get-SecureRandomChar -Characters $upperChars)
    }

    if ($Lowercase) {
        $allChars += $lowerChars
        $requiredChars += (Get-SecureRandomChar -Characters $lowerChars)
    }

    if ($Numbers) {
        $allChars += $numberChars
        $requiredChars += (Get-SecureRandomChar -Characters $numberChars)
    }

    if ($SpecialChars) {
        $allChars += $specialCharsSet
        $requiredChars += (Get-SecureRandomChar -Characters $specialCharsSet)
    }

    if ($Length -lt $requiredChars.Count) {
        throw "La longueur doit être au moins égale au nombre de groupes de caractères sélectionnés."
    }

    $passwordChars = @()
    $passwordChars += $requiredChars

    for ($i = $passwordChars.Count; $i -lt $Length; $i++) {
        $passwordChars += (Get-SecureRandomChar -Characters $allChars)
    }

    return (Shuffle-Characters -Characters $passwordChars)
}

# ================================
# Étape 3 : Vérification de robustesse
# ================================
function Test-PasswordStrength {
    param (
        [string]$Password
    )

    $score = 0

    if ($Password.Length -ge 12) { $score += 2 }
    if ($Password -match "[A-Z]")       { $score += 1 }
    if ($Password -match "[a-z]")       { $score += 1 }
    if ($Password -match "[0-9]")       { $score += 1 }
    if ($Password -match "[^a-zA-Z0-9]") { $score += 2 }
    if ($Password -match "(.)\1")       { $score -= 1 }

    if ($score -le 2)    { $strength = "Weak" }
    elseif ($score -le 4) { $strength = "Medium" }
    elseif ($score -le 6) { $strength = "Strong" }
    else                  { $strength = "Very Strong" }

    return [PSCustomObject]@{
        Password = $Password
        Score    = $score
        Strength = $strength
    }
}

function New-StrongPassword {
    param (
        [int]$Length = 7
    )

    if ($Length -lt 7) {
        $Length = 7
    }

    # Compteur de sécurité : évite une boucle infinie si le scoring
    # devenait incohérent avec les paramètres de génération.
    $maxAttempts = 100
    $attempts    = 0

    do {
        $Password = New-Password -Length $Length -Uppercase -Lowercase -Numbers -SpecialChars
        $analysis = Test-PasswordStrength -Password $Password
        $attempts++
    } while ($analysis.Score -lt 5 -and $attempts -lt $maxAttempts)

    if ($attempts -eq $maxAttempts) {
        Write-Warning "Score cible non atteint après $maxAttempts tentatives. Dernier score : $($analysis.Score)."
    }

    return $Password
}

# ================================
# Étape 4 : Génération pour plusieurs utilisateurs
# ================================
function New-PasswordList {
    param (
        [string]$UserFile,
        [int]$Length = 7
    )

    if (-not (Test-Path $UserFile)) {
        throw "Le fichier $UserFile est introuvable."
    }

    if ($Length -lt 7) {
        $Length = 7
    }

    $users = Get-Content $UserFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if ($users.Count -eq 0) {
        throw "Le fichier $UserFile est vide."
    }

    $results = @()

    foreach ($user in $users) {
        $Password = New-StrongPassword -Length $Length
        $analysis = Test-PasswordStrength -Password $Password

        $results += [PSCustomObject]@{
            User     = $user
            Password = $Password
            Strength = $analysis.Strength
            Score    = $analysis.Score
        }
    }

    $Global:PasswordResults = $results
    return $results
}

function Write-PasswordsToSourceFile {
    param (
        [string]$UserFile
    )

    if (-not $Global:PasswordResults -or $Global:PasswordResults.Count -eq 0) {
        throw "Aucune donnée à écrire."
    }

    $lines = foreach ($item in $Global:PasswordResults) {
        "$($item.User) : $($item.Password)"
    }

    Set-Content -Path $UserFile -Value $lines -Encoding UTF8
    Write-Host "Les mots de passe ont été écrits dans le fichier source : $UserFile"
}

# ================================
# Étape 5 : Export CSV
# ================================
function Export-Passwords {
    param (
        [string]$Path
    )

    if (-not $Global:PasswordResults -or $Global:PasswordResults.Count -eq 0) {
        Write-Host "Aucun mot de passe a exporter."
        return
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path -Path $HOME -ChildPath "Downloads\passwords.csv"
    }

    if (-not [System.IO.Path]::GetExtension($Path)) {
        $Path = Join-Path -Path $Path -ChildPath "passwords.csv"
    }

    $directory = Split-Path -Path $Path -Parent

    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path $directory)) {
        Write-Host "Le dossier n'existe pas. Creation du dossier..."
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    # Si le fichier existe deja, on incremente : passwords1.csv, passwords2.csv, etc.
    if (Test-Path $Path) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $ext      = [System.IO.Path]::GetExtension($Path)
        $counter  = 1
        do {
            $Path = Join-Path -Path $directory -ChildPath "$baseName$counter$ext"
            $counter++
        } while (Test-Path $Path)
    }

    $Global:PasswordResults |
        Select-Object User, Password, Strength, Score |
        Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8

    Write-Host "Export reussi : $Path"
}

# ================================
# Étape 6 : Coffre-fort sécurisé
# ================================
function Save-SecurePassword {
    param (
        [string]$User,
        [string]$Password,
        [string]$Path = (Join-Path -Path $HOME -ChildPath "secure_passwords.txt")
    )

    $securePassword    = ConvertTo-SecureString $Password -AsPlainText -Force
    $encryptedPassword = ConvertFrom-SecureString $securePassword

    "$User;$encryptedPassword" | Add-Content -Path $Path
    Write-Host "Mot de passe sécurisé enregistré pour $User dans $Path"
}

# ================================
# Documentation
# ================================
function Show-Documentation {

    Write-Host ""
    Write-Host "================ DOCUMENTATION DU SCRIPT ================="
    Write-Host ""

    Write-Host "UTILISATION DES OPTIONS DU MENU"
    Write-Host "--------------------------------"
    Write-Host ""

    Write-Host "Option 1 : Générer un mot de passe"
    Write-Host "Génère un mot de passe sécurisé."
    Write-Host "Le mot de passe généré est mémorisé pour pouvoir être exporté ensuite."
    Write-Host "Attention : cette option réinitialise PasswordResults — un export"
    Write-Host "suivant ne contiendra que ce dernier mot de passe."
    Write-Host ""

    Write-Host "Option 2 : Tester la force d'un mot de passe"
    Write-Host "Analyse un mot de passe et retourne un score avec un niveau :"
    Write-Host "Weak, Medium, Strong ou Very Strong."
    Write-Host ""

    Write-Host "Option 3 : Générer une liste de mots de passe"
    Write-Host "Lit un fichier utilisateur, demande la longueur, puis crée des mots de passe robustes."
    Write-Host "Propose ensuite l'affichage terminal ou l'écriture dans le fichier source."
    Write-Host ""

    Write-Host "Option 4 : Exporter les mots de passe"
    Write-Host "Exporte les mots de passe mémorisés dans un fichier CSV."
    Write-Host "Si aucun chemin n'est donné, l'export se fait dans Downloads\passwords.csv."
    Write-Host ""

    Write-Host "Option 5 : Déposer au coffre-fort"
    Write-Host "Enregistre un mot de passe chiffré dans un fichier texte."
    Write-Host "Note : le chiffrement utilise DPAPI (clé liée à la session Windows courante)."
    Write-Host "Le fichier ne sera lisible que sur la même machine par le même utilisateur."
    Write-Host ""

    Write-Host "Option 6 : Documentation"
    Write-Host "Affiche l'aide du script."
    Write-Host ""

    Write-Host "Option 7 : Quitter"
    Write-Host "Ferme le programme."
    Write-Host ""

    Write-Host "FONCTIONS UTILISÉES"
    Write-Host "-------------------"
    Write-Host ""
    Write-Host "Get-SecureRandomIndex  : génère un indice aléatoire sécurisé (rejection sampling)."
    Write-Host "Get-SecureRandomChar   : récupère un caractère aléatoire sécurisé."
    Write-Host "Shuffle-Characters     : mélange les caractères du mot de passe (Fisher-Yates)."
    Write-Host "New-Password           : génère un mot de passe selon les critères demandés."
    Write-Host "Test-PasswordStrength  : calcule le score et le niveau de robustesse."
    Write-Host "New-StrongPassword     : garantit un mot de passe robuste (longueur min. 7, max. 100 tentatives)."
    Write-Host "New-PasswordList       : génère des mots de passe pour plusieurs utilisateurs."
    Write-Host "Write-PasswordsToSourceFile : écrit utilisateur : motdepasse dans le fichier source."
    Write-Host "Export-Passwords       : exporte les résultats en CSV."
    Write-Host "Save-SecurePassword    : chiffre et enregistre un mot de passe (DPAPI)."
    Write-Host "Show-Menu              : affiche le menu interactif."
    Write-Host ""
    Write-Host "==========================================================="
    Write-Host ""
}

# ================================
# Affichage des résultats
# ================================
function Show-Results {
    if ($Global:PasswordResults -and $Global:PasswordResults.Count -gt 0) {
        $Global:PasswordResults | Format-Table -AutoSize
    }
    else {
        Write-Host "Aucun résultat disponible."
    }
}

# ================================
# Étape 7 : Menu interactif
# ================================
function Show-Menu {
    do {
        Write-Host ""
        Write-Host "===== Générateur et gestionnaire de mots de passe sécurisé ====="
        Write-Host "1 - Générer un mot de passe"
        Write-Host "2 - Tester la force d'un mot de passe"
        Write-Host "3 - Générer une liste de mots de passe"
        Write-Host "4 - Exporter les mots de passe"
        Write-Host "5 - Déposer au coffre-fort"
        Write-Host "6 - Documentation"
        Write-Host "7 - Quitter"
        Write-Host ""

        $choice = Read-Host "Choisissez une option"

        switch ($choice) {

            "1" {
                $Length = [int](Read-Host "Longueur du mot de passe")

                if ($Length -lt 7) {
                    Write-Host "La longueur minimale est 7. Elle sera fixée à 7."
                    $Length = 7
                }

                $Password = New-StrongPassword -Length $Length
                $analysis = Test-PasswordStrength -Password $Password

                # Note : réinitialise PasswordResults — un export suivant
                # ne contiendra que ce mot de passe, pas les précédents.
                $Global:PasswordResults = @(
                    [PSCustomObject]@{
                        User     = "Utilisateur_Simple"
                        Password = $Password
                        Strength = $analysis.Strength
                        Score    = $analysis.Score
                    }
                )

                Write-Host "Mot de passe généré : $Password"
                Write-Host "Force : $($analysis.Strength) (score : $($analysis.Score))"
            }

            "2" {
                $Password = Read-Host "Entrez le mot de passe à tester"
                $result = Test-PasswordStrength -Password $Password
                $result | Format-List
            }

            "3" {
                $UserFile = Read-Host "Chemin du fichier utilisateurs (Entree = Downloads\\users.txt)"
                if ([string]::IsNullOrWhiteSpace($UserFile)) { $UserFile = Join-Path -Path $HOME -ChildPath "Downloads\\users.txt" }
                $Length   = [int](Read-Host "Longueur des mots de passe (minimum 7)")

                if ($Length -lt 7) {
                    Write-Host "La longueur choisie est inferieure a 7. Elle sera automatiquement fixee a 7."
                    $Length = 7
                }

                if (-not (Test-Path $UserFile)) {
                    Write-Host "Le fichier est introuvable. Combien de mots de passe voulez-vous generer ?"
                    $Count = [int](Read-Host "Nombre de mots de passe")

                    $results = @()
                    for ($i = 1; $i -le $Count; $i++) {
                        $Password = New-StrongPassword -Length $Length
                        $analysis = Test-PasswordStrength -Password $Password
                        $results += [PSCustomObject]@{
                            User     = "Utilisateur_$i"
                            Password = $Password
                            Strength = $analysis.Strength
                            Score    = $analysis.Score
                        }
                    }
                    $Global:PasswordResults = $results
                    $results | Format-Table -AutoSize
                    Export-Passwords -Path (Join-Path -Path $HOME -ChildPath "Downloads\users.csv")
                }
                else {
                    $results = New-PasswordList -UserFile $UserFile -Length $Length

                    $displayChoice = Read-Host "Voulez-vous les afficher dans le terminal ? (O/N). Si vous tapez N, ils seront ecrits dans le fichier source"

                    if ($displayChoice -match "^[Oo]$") {
                        $results | Format-Table -AutoSize
                    }
                    else {
                        Write-PasswordsToSourceFile -UserFile $UserFile
                    }
                }
            }

            "4" {
                
                $Path = Read-Host "Chemin d'enregistrement (Entree = Downloads\\passwords.csv)"

                Export-Passwords -Path $Path
            }

            "5" {
                $User     = Read-Host "Nom de l'utilisateur"
                $Password = Read-Host "Mot de passe"
                $Path     = Read-Host "Chemin du fichier coffre-fort (Entrée = secure_passwords.txt)"

                if ([string]::IsNullOrWhiteSpace($Path)) {
                    Save-SecurePassword -User $User -Password $Password
                }
                else {
                    Save-SecurePassword -User $User -Password $Password -Path $Path
                }
            }

            "6" {
                Show-Documentation
            }

            "7" {
                Write-Host "Fin du programme."
            }

            default {
                Write-Host "Option invalide."
            }
        }

    } while ($choice -ne "7")
}

# Lancement du menu
Show-Menu