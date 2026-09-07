<#
.SYNOPSIS
    Deploie l'agent iZerak depuis le poste de developpement vers le Raspberry Pi.

.DESCRIPTION
    Empaquete le contenu de ce repertoire, l'envoie par scp et l'extrait sur le
    Pi. Les caches Python et l'environnement virtuel local sont exclus, et les
    fins de ligne sont normalisees en LF : un script shell en CRLF echoue sur
    Linux avec « bad interpreter: /bin/bash^M ».

    L'adresse du serveur n'est pas ecrite dans ce depot. Elle vient soit d'un
    alias declare dans votre ~/.ssh/config, soit de la variable IZERAK_PI, soit
    du parametre -PiHost.

.EXAMPLE
    .\deploy.ps1
    Envoie les fichiers vers l'hote « izerak-pi ».

.EXAMPLE
    .\deploy.ps1 -PiHost theo@192.168.1.10 -Install
    Envoie les fichiers puis lance l'installation sur le Pi.

.EXAMPLE
    .\deploy.ps1 -Test
    Envoie les fichiers puis execute la suite de tests sur le Pi.
#>
[CmdletBinding()]
param(
    # Alias ~/.ssh/config, ou « utilisateur@adresse ».
    [string]$PiHost,

    # Repertoire de destination sur le Pi.
    [string]$RemoteDir = '/home/theo/izerak',

    # Supprime le repertoire distant avant extraction, pour eliminer les
    # fichiers supprimes localement.
    [switch]$Clean,

    # Lance sudo ./install.sh apres le transfert. Demande le mot de passe sudo.
    [switch]$Install,

    # Lance la suite de tests sur le Pi apres le transfert.
    [switch]$Test,

    # Construit l'archive et s'arrete la, sans rien envoyer. Utile pour verifier
    # ce qui partirait, ou pour deployer a la main.
    [switch]$PackageOnly
)

# Volontairement 'Continue' et non 'Stop' : sous Windows PowerShell 5.1, la
# sortie d'erreur d'un executable natif est enveloppee dans un NativeCommandError
# que 'Stop' transforme en exception, avant meme qu'on ait pu lire son code de
# retour. Le controle se fait donc explicitement via $LASTEXITCODE.
$ErrorActionPreference = 'Continue'

if (-not $PiHost) {
    if ($env:IZERAK_PI) { $PiHost = $env:IZERAK_PI } else { $PiHost = 'izerak-pi' }
}

$source = $PSScriptRoot
$archiveName = 'izerak-agent.tgz'

# Repertoires de travail purement locaux : rien a envoyer sur le Pi.
$excluded = '__pycache__', '.venv', 'venv', '.pytest_cache', '.mypy_cache', '.ruff_cache'
# Fichiers texte a normaliser en LF avant l'envoi.
$textExtensions = '.sh', '.py', '.yaml', '.yml', '.toml', '.service', '.sudoers', '.md', '.cfg'

function Assert-Reachable {
    Write-Host "-> Verification de l'acces a $PiHost" -ForegroundColor Cyan
    # BatchMode empeche toute invite : si la cle n'est pas en place, on echoue
    # tout de suite avec un message utile plutot que de bloquer sur un prompt.
    # Le detour par cmd est le seul moyen fiable, en PowerShell 5.1, de faire
    # taire la sortie d'erreur d'un executable natif sans la voir remonter en
    # exception.
    & cmd /c "ssh -o BatchMode=yes -o ConnectTimeout=8 $PiHost true 2>nul"
    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host "Connexion sans mot de passe impossible vers $PiHost." -ForegroundColor Red
        Write-Host 'Configuration a faire une seule fois :' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\izerak_pi" -C "izerak deploy"'
        Write-Host '  type "$env:USERPROFILE\.ssh\izerak_pi.pub" | ssh theo@<adresse-du-pi> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"'
        Write-Host ''
        Write-Host 'Puis ajoutez dans ~/.ssh/config :'
        Write-Host ''
        Write-Host '  Host izerak-pi'
        Write-Host '    HostName <adresse-du-pi>'
        Write-Host '    User theo'
        Write-Host '    IdentityFile ~/.ssh/izerak_pi'
        Write-Host ''
        throw 'Acces SSH non configure.'
    }
}

function New-Payload {
    # Copie intermediaire : elle permet de normaliser les fins de ligne sans
    # toucher aux fichiers du depot.
    $staging = Join-Path ([System.IO.Path]::GetTempPath()) ("izerak-deploy-" + [guid]::NewGuid().ToString('N'))
    $agentDir = Join-Path $staging 'izerak-agent'
    New-Item -ItemType Directory -Force $agentDir | Out-Null

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $copied = 0

    Get-ChildItem -Path $source -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($source.Length).TrimStart('\', '/')
        foreach ($skip in $excluded) {
            if ($relative -split '[\\/]' -contains $skip) { return }
        }
        # deploy.ps1 pilote le deploiement depuis le poste Windows : il n'a
        # aucun usage sur le Pi.
        if ($_.Extension -eq '.pyc' -or $_.Name -eq $archiveName -or $_.Name -eq 'deploy.ps1') { return }

        $target = Join-Path $agentDir $relative
        New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null

        if ($textExtensions -contains $_.Extension.ToLower()) {
            $text = [System.IO.File]::ReadAllText($_.FullName)
            [System.IO.File]::WriteAllText($target, $text.Replace("`r`n", "`n"), $utf8NoBom)
        } else {
            Copy-Item $_.FullName $target
        }
        $script:copied++
    }

    Write-Host "-> $script:copied fichier(s) empaquetes" -ForegroundColor Cyan

    $archive = Join-Path $staging $archiveName
    & tar -czf $archive -C $agentDir .
    if ($LASTEXITCODE -ne 0) { throw 'Echec de la creation de l archive.' }

    return [pscustomobject]@{ Staging = $staging; Archive = $archive }
}

$script:copied = 0

if ($PackageOnly) {
    $payload = New-Payload
    Write-Host ''
    Write-Host 'Contenu de l archive :' -ForegroundColor Cyan
    & tar -tzf $payload.Archive
    Write-Host ''
    Write-Host "Archive : $($payload.Archive)" -ForegroundColor Green
    Write-Host 'Le repertoire temporaire n est pas supprime en mode -PackageOnly.' -ForegroundColor DarkGray
    return
}

Assert-Reachable
$payload = New-Payload

try {
    $remoteArchive = "/tmp/$archiveName"

    Write-Host "-> Envoi vers ${PiHost}:$RemoteDir" -ForegroundColor Cyan
    & scp -q $payload.Archive "${PiHost}:$remoteArchive"
    if ($LASTEXITCODE -ne 0) { throw 'Echec du transfert scp.' }

    # Guillemets simples cote distant : la chaine est interpretee par le shell
    # du Pi, pas par PowerShell.
    $cleanStep = ''
    if ($Clean) { $cleanStep = "rm -rf '$RemoteDir' && " }

    $remoteScript = "set -e; ${cleanStep}mkdir -p '$RemoteDir'; tar -xzf '$remoteArchive' -C '$RemoteDir'; rm -f '$remoteArchive'; echo 'extraction terminee'"
    & ssh $PiHost $remoteScript
    if ($LASTEXITCODE -ne 0) { throw 'Echec de l extraction sur le Pi.' }

    if ($Test) {
        Write-Host '-> Tests sur le Pi' -ForegroundColor Cyan
        $testScript = "cd '$RemoteDir' && python3 -m venv .venv 2>/dev/null; .venv/bin/pip install -q -e '.[dev]' && .venv/bin/python -m pytest -q"
        & ssh $PiHost $testScript
        if ($LASTEXITCODE -ne 0) { throw 'Les tests ont echoue sur le Pi.' }
    }

    if ($Install) {
        Write-Host '-> Installation (mot de passe sudo demande sur le Pi)' -ForegroundColor Cyan
        # -t alloue un terminal : sans lui, sudo ne peut pas demander le mot de passe.
        & ssh -t $PiHost "cd '$RemoteDir' && chmod +x install.sh && sudo ./install.sh"
        if ($LASTEXITCODE -ne 0) { throw 'Echec de l installation.' }
    }

    Write-Host ''
    Write-Host "Termine. Agent deploye dans $RemoteDir sur $PiHost." -ForegroundColor Green
    if (-not $Install) {
        Write-Host "Pour installer : .\deploy.ps1 -Install" -ForegroundColor DarkGray
    }
}
finally {
    Remove-Item -Recurse -Force $payload.Staging -ErrorAction SilentlyContinue
}
