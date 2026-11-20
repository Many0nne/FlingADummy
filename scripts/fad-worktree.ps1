<#
.SYNOPSIS
  Cree, reutilise et demarre (ou arrete, ou supprime) un worktree Fling a Dummy avec son propre serveur Rojo,
  et gere le verrou de la place Studio partagee.

.DESCRIPTION
  Une branche = un worktree worktrees\fad-<slug> = un slot N (le checkout principal etant le slot 0, port 34900) :
  `rojo serve` du worktree ecoute sur le port 34900+N. Rien de versionne n'est modifie : port, pid et journal du serveur
  sont dans worktrees\.run\<slug>.port|.pid|.log, hors du worktree (git status y reste propre, meme sur une vieille branche).

  Idempotent : a relancer sans risque au debut de chaque tache. Un worktree deja present sur la bonne branche est
  reutilise tel quel (modifications et slot conserves), y compris un worktree cree a la main avec `git worktree add`
  au meme emplacement ; un `rojo serve` lance a la main sur le port du worktree est repris. Par defaut le script
  demarre `rojo serve` en arriere-plan et attend que http://localhost:<port>/api/rojo reponde. -NoUp : sans demarrer.

  Le worktree recoit un .claude\settings.local.json (exclu de git) qui autorise sa session Claude a ecrire dans
  worktrees\.briefs (compte rendu du brief /delegate) et dans %TEMP%, malgre blockWritesOutsideWorkingDirectories.

  Registre de nettoyage (worktrees\.owners.json, lu par fad-worktree-cleanup.ps1) : la session Claude qui lance le
  script est inscrite comme utilisatrice du worktree. Quand ses threads T3 ne sont plus actifs, Rojo est arrete ;
  quand la PR de la branche est mergee (ou fermee), le worktree est supprime (si tout est commite et pousse).

.EXAMPLE
  .\scripts\fad-worktree.ps1 feature/x                 # cree/reutilise et demarre rojo serve (branche creee depuis main si absente)
  .\scripts\fad-worktree.ps1 fix/y -Base feature/x     # nouvelle branche creee depuis une autre base
  .\scripts\fad-worktree.ps1 feature/x -NoUp           # sans demarrer Rojo
  .\scripts\fad-worktree.ps1 feature/x -Slot 1         # impose le slot (port 34901), par exemple pour reprendre un Rojo lance a la main
  .\scripts\fad-worktree.ps1 feature/x -Stop           # arrete Rojo (et libere Studio)
  .\scripts\fad-worktree.ps1 feature/x -Remove         # arrete Rojo, supprime le worktree (branche conservee)

  Pour /delegate :
  .\scripts\fad-worktree.ps1 feature/x -NoUp -NoRegister     # creer sans inscrire la session courante
  .\scripts\fad-worktree.ps1 feature/x -RegisterThread <id>  # inscrire seulement un thread T3 (rien d'autre)

  Studio partage (une seule place Studio pour tous les worktrees, verrou worktrees\.run\studio.lock) :
  .\scripts\fad-worktree.ps1 feature/x -AcquireStudio                # reserve Studio, ou sort en code 2 avec le detenteur
  .\scripts\fad-worktree.ps1 feature/x -AcquireStudio -WaitStudio 20 # attend jusqu'a 20 min qu'il se libere
  .\scripts\fad-worktree.ps1 feature/x -ReleaseStudio                # libere, place renvoyee sur 34900 ou deconnectee (aussi par -Stop et -Remove)
  .\scripts\fad-worktree.ps1 -StudioStatus                           # detenteur, port connecte, dernier etat signale par le plugin
  Un verrou est repris d'office si son detenteur n'a plus de worktree, plus de Rojo, ou plus de thread T3 actif.

  Auto-connexion (plugin Rojo « CSGO autoconnect » multi-projets, installe par CSGO_surf_combat\tools\rojo-plugin\install.ps1) :
  la reservation publie le port du worktree dans worktrees\.run\studio.target, inscrit Fling a Dummy au registre commun
  (%LOCALAPPDATA%\RojoAutoconnect\projects\fad.json, place 88580736516669), s'assure que le serveur de commande repond
  (port 34870) et attend 15 s que la fenetre Fling a Dummy se connecte ; la fenetre CSGO n'est pas touchee. La liberation
  renvoie la place sur 34900 si le Rojo du checkout principal repond, sinon la deconnecte. -StudioStatus et
  -AcquireStudio alertent si le plugin signale la place connectee a un Rojo qui n'est pas de ce depot.
#>
param(
  [Parameter(Position = 0)][string]$Branch,
  [string]$Base = 'main',
  [int]$Slot = 0,
  [switch]$NoUp,
  [switch]$Stop,
  [switch]$Remove,
  [switch]$NoRegister,
  [string]$RegisterThread,
  [switch]$AcquireStudio,
  [int]$WaitStudio = 0,
  [switch]$ReleaseStudio,
  [switch]$StudioStatus
)

$ErrorActionPreference = 'Stop'

# Racine du checkout principal, meme si le script est lance depuis la copie d'un worktree.
$commonDir = git -C $PSScriptRoot rev-parse --path-format=absolute --git-common-dir
$root = (Resolve-Path (Split-Path -Parent $commonDir)).Path
$worktrees = Join-Path $root 'worktrees'
$runDir = Join-Path $worktrees '.run'
$ownersFile = Join-Path $worktrees '.owners.json'
$studioLock = Join-Path $runDir 'studio.lock'
# Port du checkout principal (slot 0) ; FAD_BASE_PORT ne sert qu'aux tests (bac a sable loin des ports reels).
$basePort = if ($env:FAD_BASE_PORT) { [int]$env:FAD_BASE_PORT } else { 34900 }
# Branche du checkout principal : elle peut aussi reserver Studio (son Rojo est lance a la main sur le port de base).
$mainBranch = 'main'
# Auto-connexion de Studio par le plugin Rojo « CSGO autoconnect » multi-projets (Many0nne/CSGO_surf_combat, doc
# tools/rojo-plugin/README.md, « Utiliser l'auto-connexion depuis un autre projet ») : chaque fenetre Studio ne suit que
# la cible du projet inscrit pour sa place. Cible et etat dans worktrees\.run du checkout principal.
$placeIds = @('88580736516669')
$studioTarget = Join-Path $runDir 'studio.target'
$studioStateFile = Join-Path $runDir 'studio.status'
# Serveur de commande partage par les projets du poste (lance par le premier script qui reserve Studio) ; registre, journal
# et pid dans un dossier commun. ROJO_AUTOCONNECT_DIR, FAD_CONTROL_PORT et FAD_CONNECT_WAIT ne servent qu'aux tests.
$controlPort = if ($env:FAD_CONTROL_PORT) { [int]$env:FAD_CONTROL_PORT } else { 34870 }
# Version du protocole attendue : tout serveur de version >= est garde (il sert aussi les fenetres des autres projets).
$controlVersion = 3
$controlDir = if ($env:ROJO_AUTOCONNECT_DIR) { $env:ROJO_AUTOCONNECT_DIR } else { Join-Path $env:LOCALAPPDATA 'RojoAutoconnect' }
$controlPidFile = Join-Path $controlDir 'control.pid'
# Delai d'attente de la connexion signalee par le plugin apres une reservation (secondes).
$connectWait = if ($env:FAD_CONNECT_WAIT) { [int]$env:FAD_CONNECT_WAIT } else { 15 }
$helper = Join-Path $PSScriptRoot 't3_threads.py'

# Cle propre a ce checkout pour les mutex : deux checkouts (ou un bac a sable de test) ne se bloquent pas entre eux.
$sha = [Security.Cryptography.SHA256]::Create()
$rootKey = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant())) | Select-Object -First 6 |
    ForEach-Object { $_.ToString('x2') })

# Cette methode permet de calculer le slug d'une branche (nom des dossiers et fichiers d'etat) : `/` et accents -> `-`.
function Get-Slug([string]$Name) { $Name -replace '[^A-Za-z0-9._-]', '-' }

# Cette methode permet de lire un fichier texte en UTF-8 (y compris sous Windows PowerShell 5.1) ; $null s'il manque.
function Read-Text([string]$Path) { if (Test-Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path) } else { $null } }

# Cette methode permet d'ecrire un fichier d'etat en UTF-8 sans BOM (dossier cree au besoin) par un temporaire puis un
# remplacement, qu'aucun lecteur sans mutex ne lise tronque ; nouvelles tentatives si le fichier est ouvert ailleurs.
function Write-Text([string]$Path, [string]$Text) {
  New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
  $tmp = "$Path.$PID.tmp"
  [IO.File]::WriteAllText($tmp, $Text, [Text.UTF8Encoding]::new($false))
  try {
    for ($i = 1; ; $i++) {
      try {
        # [NullString]::Value : un $null passe a un parametre string deviendrait "" (« The path is empty »).
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tmp, $Path, [NullString]::Value) } else { [IO.File]::Move($tmp, $Path) }
        return
      } catch [System.IO.IOException], [System.UnauthorizedAccessException] {
        if ($i -ge 10) { throw }
        Start-Sleep -Milliseconds 100
      }
    }
  } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

# Cette methode permet de lire un entier (port, pid) dans un fichier d'etat ; 0 si le fichier manque ou est illisible.
function Read-Int([string]$Path) {
  $n = 0
  if ([int]::TryParse("$(Read-Text $Path)".Trim(), [ref]$n)) { return $n }
  return 0
}

# Cette methode permet d'executer une action sous un mutex systeme propre a ce checkout lorsque plusieurs agents
# touchent au meme etat (slots, registre, verrou Studio) ; un mutex abandonne par un processus mort est repris.
function Invoke-Locked([string]$Name, [scriptblock]$Action) {
  $m = [System.Threading.Mutex]::new($false, "Local\fad-$Name-$rootKey")
  try { [void]$m.WaitOne() } catch [System.Threading.AbandonedMutexException] { }
  try { & $Action } finally { $m.ReleaseMutex(); $m.Dispose() }
}

# Cette methode permet de lancer une commande git bavarde (fetch, worktree add) sans que ses messages sur stderr ne
# deviennent des erreurs bloquantes (Windows PowerShell 5.1 sous redirection) ; le code reste dans $LASTEXITCODE.
function Invoke-GitLoud {
  $ErrorActionPreference = 'Continue'
  & git @args 2>&1 | ForEach-Object { Write-Host "$_" }
}

# Cette methode permet de lancer une commande externe en ignorant son stderr sans que Windows PowerShell 5.1 ne le
# transforme en erreur bloquante ; renvoie stdout, le code reste dans $LASTEXITCODE.
function Invoke-Quiet([string]$Exe) {
  $ErrorActionPreference = 'Continue'
  $rest = @($args)
  & $Exe @rest 2>$null
}

# Cette methode permet de retrouver le thread T3 d'une session Claude ; $null si le helper echoue ou ne la connait pas.
function Get-ThreadOf([string]$Session) {
  try { $out = Invoke-Quiet python -I $helper thread-of $Session } catch { return $null }
  if ($LASTEXITCODE -ne 0) { return $null }
  $t = "$out".Trim()
  if ($t) { return $t }
  return $null
}

# Cette methode permet de connaitre l'etat de threads T3 (active, settled, archived...) lorsqu'on juge un verrou ;
# $null si le helper est en panne (on ne conclut alors rien).
function Get-ThreadStates([string[]]$Threads) {
  try { $out = Invoke-Quiet python -I $helper status @Threads } catch { return $null }
  if ($LASTEXITCODE -ne 0 -or -not "$out".Trim()) { return $null }
  try { return ("$out" | ConvertFrom-Json) } catch { return $null }
}

# Cette methode permet d'autoriser la session Claude du worktree a ecrire son compte rendu (worktrees\.briefs) et ses
# fichiers temporaires (%TEMP%) : ajoute ces dossiers a .claude\settings.local.json (ignore par git), sans toucher au reste.
function Set-AgentSettings {
  $exclude = Join-Path $commonDir 'info\exclude'
  $pattern = '.claude/settings.local.json'
  if (-not ((Test-Path $exclude) -and ((Get-Content $exclude) -contains $pattern))) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $exclude) | Out-Null
    Add-Content -Path $exclude -Value $pattern
  }
  $dirs = @((Join-Path $worktrees '.briefs'), [IO.Path]::GetTempPath().TrimEnd('\', '/'))
  $file = Join-Path $dir '.claude\settings.local.json'
  $settings = [pscustomobject]@{}
  $raw = Read-Text $file
  if ("$raw".Trim()) {
    try { $settings = $raw | ConvertFrom-Json } catch { Write-Warning "$file illisible : non modifie."; return }
  }
  if (-not $settings.PSObject.Properties['permissions']) { $settings | Add-Member permissions ([pscustomobject]@{}) }
  $current = @($settings.permissions.additionalDirectories | Where-Object { $_ })
  $missing = @($dirs | Where-Object { $current -notcontains $_ })
  if (-not $missing) { return }
  $settings.permissions | Add-Member -Force additionalDirectories @($current + $missing)
  Write-Text $file ($settings | ConvertTo-Json -Depth 10)
}

# Cette methode permet de lire le registre des worktrees lorsqu'on doit l'enrichir ou le nettoyer, en ramenant chaque
# entree a la forme { branch, sessions[], threads[] } quel que soit l'etat du fichier (vide, ancien format, PS 5.1) ;
# leve une erreur si le fichier est illisible (a ne pas ecraser).
function Get-Owners {
  $raw = Read-Text $ownersFile
  if (-not "$raw".Trim()) { return @() }
  # foreach deroule le tableau JSON : Windows PowerShell 5.1 le renvoie d'un bloc (un seul objet Object[]).
  $parsed = $raw | ConvertFrom-Json
  return @(foreach ($o in $parsed) {
      if (-not $o.branch) { continue }
      [pscustomobject]@{
        branch = [string]$o.branch
        sessions = @($o.sessions | Where-Object { $_ })
        threads = @($o.threads | Where-Object { $_ })
      }
    })
}

# Cette methode permet d'ecrire le registre complet (sous le mutex 'state' de l'appelant).
function Save-Owners($Owners) { Write-Text $ownersFile (ConvertTo-Json @($Owners) -Depth 4) }

# Cette methode permet d'inscrire la session Claude courante (ou le thread T3 donne) comme utilisatrice de la branche
# lorsque le script cree ou reutilise un worktree depuis Claude Code, ou quand /delegate a cree son thread.
function Register-Owner([string]$Thread) {
  $session = if ($Thread) { $null } else { $env:CLAUDE_CODE_SESSION_ID }
  if (-not ($session -or $Thread)) { return }
  # Le thread T3 (stable meme apres /clear) ; vide si la session ne tourne pas dans T3 ou n'a pas fini son premier tour.
  $t = if ($session) { Get-ThreadOf $session } else { $Thread }
  Invoke-Locked 'state' {
    try { $owners = @(Get-Owners) }
    catch { Write-Warning "Registre $ownersFile illisible : inscription de '$Branch' ignoree (le reparer a la main)."; return }
    $entry = $owners | Where-Object { $_.branch -eq $Branch } | Select-Object -First 1
    if (-not $entry) {
      $entry = [pscustomobject]@{ branch = $Branch; sessions = @(); threads = @() }
      $owners += $entry
    }
    if ($session -and $session -notin $entry.sessions) { $entry.sessions = @($entry.sessions) + $session }
    if ($t -and $t -notin $entry.threads) { $entry.threads = @($entry.threads) + $t }
    Save-Owners $owners
  }
}

# Cette methode permet de retirer la branche du registre lorsque son worktree vient d'etre supprime.
function Unregister-Owner {
  Invoke-Locked 'state' {
    if (-not (Test-Path $ownersFile)) { return }
    try { $owners = @(Get-Owners | Where-Object { $_.branch -ne $Branch }) } catch { Write-Warning "Registre $ownersFile illisible : '$Branch' non retiree."; return }
    Save-Owners $owners
  }
}

# Cette methode permet de savoir si une ref git existe dans le depot principal.
function Test-Ref([string]$Ref) {
  Invoke-Quiet git -C $root show-ref --verify --quiet $Ref | Out-Null
  return ($LASTEXITCODE -eq 0)
}

# Cette methode permet de savoir si le dossier est un worktree enregistre du depot (et pas un reliquat).
function Test-WorktreeRegistered {
  $target = (Resolve-Path $dir).Path -replace '\\', '/'
  [bool](git -C $root worktree list --porcelain | Where-Object { $_ -eq "worktree $target" })
}

# Cette methode permet de lire la branche d'un worktree dans son fichier HEAD (UTF-8), lorsque la sortie de git serait
# mal decodee par la console (branche accentuee) ; $null en HEAD detache ou si le dossier n'est pas un worktree.
function Get-WorktreeBranch([string]$Path) {
  $dotGit = Join-Path $Path '.git'
  if (Test-Path -LiteralPath $dotGit -PathType Leaf) {
    $gitDir = ("$(Read-Text $dotGit)".Trim() -replace '^gitdir:\s*', '')
    if (-not [IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $Path $gitDir }
  } else { $gitDir = $dotGit }
  $head = "$(Read-Text (Join-Path $gitDir 'HEAD'))".Trim()
  # Rebase en cours : HEAD est detache, la branche est notee dans rebase-merge (ou rebase-apply)/head-name.
  if ($head -notlike 'ref: *') {
    foreach ($d in 'rebase-merge', 'rebase-apply') {
      $name = "$(Read-Text (Join-Path $gitDir "$d\head-name"))".Trim()
      if ($name) { $head = "ref: $name"; break }
    }
  }
  if ($head -like 'ref: refs/heads/*') { return $head.Substring('ref: refs/heads/'.Length) }
  return $null
}

# Cette methode permet de bloquer lorsque le dossier du slug appartient a une autre branche (meme slug : `a/b-c` et
# `a-b/c`), pour ne jamais arreter ni supprimer le worktree d'une autre tache.
function Assert-OwnWorktree {
  if (-not (Test-Path $dir)) { return }
  if (-not (Test-WorktreeRegistered)) { return }
  $current = Get-WorktreeBranch $dir
  if ($current -and $current -ne $Branch) { throw "$dir est le worktree de '$current', pas de '$Branch' : rien n'est touche." }
}

# Cette methode permet de connaitre le processus qui ecoute sur un port local ; 0 si le port est libre.
function Get-PortListener([int]$Port) {
  $c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return [int]$c.OwningProcess }
  return 0
}

# Cette methode permet de savoir si un processus est bien un serveur Rojo de ce port, et pas un pid recycle par Windows
# apres un redemarrage : sa ligne de commande cite `rojo`, `serve` et `--port <port>` (port 0 = inconnu : n'importe lequel).
function Test-RojoProcess([int]$Id, [int]$Port) {
  if ($Id -le 0) { return $false }
  $p = Get-CimInstance Win32_Process -Filter "ProcessId = $Id" -ErrorAction SilentlyContinue
  if (-not $p) { return $false }
  $cl = "$($p.CommandLine)"
  $portPattern = if ($Port -gt 0) { "--port\s+$Port\b" } else { '--port\s+\d+' }
  return ($cl -match 'rojo') -and ($cl -match '\bserve\b') -and ($cl -match $portPattern)
}

# Cette methode permet de savoir si le serveur Rojo enregistre pour un slug (pid et port de worktrees\.run) tourne encore.
function Test-RojoRunning([string]$ForSlug) {
  Test-RojoProcess (Read-Int (Join-Path $runDir "$ForSlug.pid")) (Read-Int (Join-Path $runDir "$ForSlug.port"))
}

# Cette methode permet de savoir si le Rojo d'une branche tourne, y compris celui du checkout principal (`rojo serve`
# lance a la main sur le port de base, sans fichier pid) lorsque cette branche reserve ou detient Studio.
function Test-HolderRojo([string]$HolderBranch) {
  if ($HolderBranch -ne $mainBranch) { return (Test-RojoRunning (Get-Slug $HolderBranch)) }
  $l = Get-PortListener $basePort
  if (-not $l) { return $false }
  return ((Get-Process -Id $l -ErrorAction SilentlyContinue).ProcessName -eq 'rojo') -or (Test-RojoProcess $l $basePort)
}

# Cette methode permet de renvoyer le code HTTP d'une URL, ou $null si rien ne repond (pwsh 7 et Windows PowerShell 5.1).
function Get-UrlCode([string]$Url) {
  try { return [int](Invoke-WebRequest -Uri $Url -TimeoutSec 3 -UseBasicParsing).StatusCode }
  catch { $r = $_.Exception.Response; if ($r) { return [int]$r.StatusCode } return $null }
}

# Cette methode permet d'attendre que Rojo reponde 200 sur /api/rojo lorsqu'il demarre ; s'arrete apres 30 s,
# ou des que son processus est mort. Renvoie le dernier code.
function Wait-Rojo([string]$Url) {
  $code = $null
  for ($i = 0; $i -lt 30; $i++) {
    $code = Get-UrlCode $Url
    if ($code -eq 200) { break }
    if (-not (Test-RojoRunning $slug)) { break }
    Start-Sleep -Seconds 1
  }
  return $code
}

# Cette methode permet d'arreter le Rojo du worktree : arbre du pid enregistre (s'il s'agit bien de Rojo), puis tout
# serveur Rojo qui ecoute encore sur le port du slot (lance a la main). Renvoie $true si quelque chose a ete arrete.
function Stop-Rojo([int]$Port) {
  $stopped = $false
  if (Test-Path $pidFile) {
    $rojoPid = Read-Int $pidFile
    if (Test-RojoProcess $rojoPid $Port) { taskkill /PID $rojoPid /T /F *> $null; $stopped = $true }
    Remove-Item -Force $pidFile
  }
  if ($Port -gt 0) {
    $listener = Get-PortListener $Port
    if (Test-RojoProcess $listener $Port) { taskkill /PID $listener /T /F *> $null; $stopped = $true }
  }
  return $stopped
}

# Cette methode permet de lire le verrou Studio (branche, port, depuis) lorsqu'on veut savoir qui utilise Studio ;
# $null s'il est libre ou illisible (un verrou corrompu ne bloque personne).
function Get-StudioLock {
  $raw = Read-Text $studioLock
  if (-not "$raw".Trim()) { return $null }
  try { $lock = $raw | ConvertFrom-Json } catch { return $null }
  if (-not $lock.branch) { return $null }
  return $lock
}

# Cette methode permet de dire pourquoi le detenteur du verrou Studio ne l'utilise plus (worktree supprime, Rojo arrete,
# threads T3 tous termines) lorsqu'une autre branche le demande ; renvoie $null si le detenteur est encore actif.
function Get-StudioLockStaleReason($Lock) {
  if ($Lock.branch -ne $mainBranch) {
    if (-not (Test-Path (Join-Path $worktrees "fad-$(Get-Slug $Lock.branch)"))) { return 'worktree supprime' }
  }
  if (-not (Test-HolderRojo $Lock.branch)) { return 'Rojo arrete' }
  # Threads du detenteur : celui de la session qui a reserve (note dans le verrou, ou resolu depuis si elle en etait a son
  # premier tour). Session sans thread T3 (terminal) : rien ne permet de la dire finie, le verrou reste actif. Verrou
  # sans session (pose hors de Claude) : threads du registre de la branche, sessions resolues comprises.
  if ($Lock.session -or $Lock.thread) {
    $threads = @($Lock.thread | Where-Object { $_ })
    if (-not $threads) { $threads = @(Get-ThreadOf $Lock.session | Where-Object { $_ }) }
    if (-not $threads) { return $null }
  } else {
    try { $entry = Get-Owners | Where-Object { $_.branch -eq $Lock.branch } | Select-Object -First 1 } catch { $entry = $null }
    $threads = @($entry.threads)
    foreach ($s in @($entry.sessions)) { if ($s) { $threads += Get-ThreadOf $s } }
    $threads = @($threads | Where-Object { $_ } | Select-Object -Unique)
  }
  if ($threads) {
    # Seuls des etats certains comptent : un thread `missing` (base T3 deplacee, id errone) n'est pas un thread fini.
    $states = Get-ThreadStates $threads
    $finished = @($threads | Where-Object { $states -and $states.$_ -in 'settled', 'archived', 'deleted' })
    if ($finished.Count -eq $threads.Count) { return 'threads T3 termines' }
  }
  return $null
}

# Cette methode permet de lister les ports Rojo (checkout principal et worktrees) auxquels Studio est connecte en ce moment,
# lorsqu'il faut dire a l'agent ou a l'utilisateur s'il doit faire Disconnect avant de se connecter ailleurs.
function Get-StudioConnectedPorts {
  # Tests : connexions de Studio simulees (aucun Studio dans le bac a sable).
  if ($env:FAD_FAKE_STUDIO_PORTS) { return @($env:FAD_FAKE_STUDIO_PORTS -split ',' | ForEach-Object { [int]$_ } | Where-Object { $_ -gt 0 }) }
  $ports = @($basePort) + @(Get-ChildItem -Path $runDir -Filter '*.port' -File -ErrorAction SilentlyContinue |
      ForEach-Object { Read-Int $_.FullName })
  # Cote client, seulement les connexions ouvertes par Studio (pas les sondes HTTP des autres agents).
  @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
      Where-Object { $_.RemotePort -in $ports -and (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName -like 'RobloxStudio*' } |
      Select-Object -ExpandProperty RemotePort -Unique | Sort-Object)
}

# Cette methode permet de decrire en une ligne le detenteur du verrou Studio lorsqu'on l'affiche.
function Format-StudioLock($Lock) { "'$($Lock.branch)' (port $($Lock.port), depuis $($Lock.since))" }

# Cette methode permet d'expliquer la connexion manuelle de Studio a un port (secours quand le plugin autoconnect ne
# s'est pas connecte seul) en signalant le port auquel Studio est deja connecte.
function Write-ConnectHelp([int]$Port) {
  $conn = @(Get-StudioConnectedPorts | Where-Object { $_ -ne $Port })
  $from = if ($conn) { "Disconnect dans le plugin Rojo (connecte au port $($conn -join ', ')), puis " } else { '' }
  Write-Host "Connexion a la main (Studio en mode Edit, place $($placeIds -join ', ')) : $($from)plugin Rojo > port $Port > Connect."
}

# Cette methode permet de lire la derniere cible publiee (port, rev) lorsqu'on juge une connexion a 34900 ; $null si absente.
function Get-StudioTarget {
  $raw = Read-Text $studioTarget
  if (-not "$raw".Trim()) { return $null }
  try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

# Cette methode permet de reconnaitre une connexion de Studio au checkout principal faite hors des scripts (l'utilisateur
# qui teste sur 34900) : la derniere cible publiee n'y renvoyait pas la place (une liberation y renvoie la place au repos).
function Test-ManualBaseConnection {
  if (-not (@(Get-StudioConnectedPorts) -contains $basePort)) { return $false }
  $target = Get-StudioTarget
  # Aucune cible encore publiee (avant la premiere reservation) : 34900 etait l'etat de repos de la connexion manuelle.
  if (-not $target) { return $false }
  return "$($target.port)" -ne "$basePort"
}

# Cette methode permet de lire le dernier etat signale par le plugin pour la place Fling a Dummy (studio.status :
# rev, state, port) lorsqu'on attend une connexion ou qu'on cherche une connexion suspecte ; $null s'il manque ou est illisible.
function Get-StudioState {
  $raw = Read-Text $studioStateFile
  if (-not "$raw".Trim()) { return $null }
  try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

# Cette methode permet de savoir si un port est celui d'un serveur Rojo de ce depot (checkout principal, worktree attribue,
# ou slot 34900+N d'un worktree deja supprime), lorsqu'il faut reconnaitre une connexion a un Rojo etranger (CSGO).
function Test-RepoRojoPort([int]$Port) {
  if ($Port -ge $basePort -and $Port -lt $basePort + 100) { return $true }
  $Port -in @(Get-ChildItem -Path $runDir -Filter '*.port' -File -ErrorAction SilentlyContinue | ForEach-Object { Read-Int $_.FullName })
}

# Cette methode permet d'alerter lorsque le plugin signale la place Fling a Dummy connectee a un port qui n'est d'aucun
# serveur Rojo de ce depot (cas de la pollution par le code CSGO) ; renvoie $true si l'alerte a ete affichee.
function Write-ForeignConnectionAlert($State) {
  if (-not $State -or $State.state -ne 'connected') { return $false }
  $port = 0
  if (-not [int]::TryParse("$($State.port)", [ref]$port) -or (Test-RepoRojoPort $port)) { return $false }
  $when = (Get-Item -LiteralPath $studioStateFile).LastWriteTime.ToString('yyyy-MM-dd HH:mm')
  Write-Host "ALERTE : la place Fling a Dummy ($($placeIds -join ', ')) est connectee au port $port, qui n'est aucun serveur Rojo de ce depot (CSGO ?), selon le plugin ($when)."
  Write-Host "  Ne pas sauvegarder ni publier la place : le code d'un autre projet y est synchronise. Reserver Studio (-AcquireStudio) la reconnecte au bon port ; retirer ensuite ce qui n'est pas a Fling a Dummy hors des dossiers mappes."
  return $true
}

# Cette methode permet d'inscrire Fling a Dummy dans le registre commun du serveur de commande (place, port principal,
# fichiers cible et etat du checkout principal) lorsqu'il publie une cible ; reecrite a chaque fois, elle suit le checkout.
function Register-AutoconnectProject {
  $entry = [ordered]@{ name = 'fad'; placeIds = $placeIds; mainPort = $basePort; target = $studioTarget; status = $studioStateFile }
  $file = Join-Path $controlDir 'projects\fad.json'
  # Echec (fichier occupe trop longtemps) : l'inscription precedente reste valable (memes chemins), on continue.
  try { Write-Text $file ([pscustomobject]$entry | ConvertTo-Json -Compress) }
  catch { Write-Warning "Inscription $file non mise a jour ($($_.Exception.Message)) : l'ancienne est gardee." }
}

# Cette methode permet de publier le port Rojo que la fenetre Fling a Dummy doit suivre lorsque le verrou change de main ;
# chaine vide = deconnecter. Le plugin ne reagit qu'au changement de `rev`, renvoyee par la methode.
function Set-StudioTarget([string]$Port) {
  $rev = [string](Get-Date).Ticks
  Write-Text $studioTarget ([pscustomobject][ordered]@{ port = $Port; rev = $rev } | ConvertTo-Json -Compress)
  Register-AutoconnectProject
  return $rev
}

# Cette methode permet de lire la version du serveur de commande lorsqu'il faut decider de le garder : -1 s'il ne repond
# pas, 0 s'il annonce un ancien protocole (csgo-control 2), sinon N de `rojo-control N`.
function Get-ControlVersion([int]$TimeoutSec = 3) {
  # Port libre : reponse immediate (Windows met ~2 s a refuser une connexion vers un port ferme).
  if (-not (Get-PortListener $controlPort)) { return -1 }
  # 127.0.0.1 et pas localhost : le serveur n'ecoute qu'en IPv4, et l'essai prealable de ::1 prend plus d'une seconde.
  try { $health = (Invoke-WebRequest "http://127.0.0.1:$controlPort/health" -TimeoutSec $TimeoutSec -UseBasicParsing).Content } catch { return -1 }
  if ($health -is [byte[]]) { $health = [Text.Encoding]::UTF8.GetString($health) }
  if ("$health".Trim() -match '^rojo-control (\d+)$') { return [int]$Matches[1] }
  return 0
}

# Cette methode permet de lire la version d'un fichier control-server.luau (ligne VERSION) lorsqu'on decide de le lancer ; 0 sinon.
function Get-ControlFileVersion([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return 0 }
  $m = Select-String -LiteralPath $Path -Pattern '^local VERSION = "rojo-control (\d+)"' | Select-Object -First 1
  if ($m) { return [int]$m.Matches[0].Groups[1].Value }
  return 0
}

# Cette methode permet d'arreter l'ancien serveur de commande note dans control.pid lorsqu'il faut le remplacer, seulement
# si ce pid est bien un control-server.luau (pas un pid recycle par Windows apres un redemarrage).
function Stop-ControlPid {
  $old = Read-Int $controlPidFile
  if ($old -le 0) { return }
  $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $old" -ErrorAction SilentlyContinue).CommandLine
  if ("$cmd" -like '*control-server.luau*') { taskkill /PID $old /T /F *> $null }
}

# Cette methode permet de s'assurer, sous le mutex commun aux projets, que le serveur de commande repond (version >= 3,
# jamais arrete : il sert les autres fenetres), sinon de le lancer depuis la copie commune ; $true s'il est utilisable.
function Start-RojoControl {
  # Mutex commun a tous les projets du poste ; un registre de test (ROJO_AUTOCONNECT_DIR) a le sien, pour ne pas attendre les vrais.
  $mutexName = 'Local\rojo-autoconnect-control'
  if ($env:ROJO_AUTOCONNECT_DIR) {
    $mutexName += '-' + (-join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($controlDir.ToLowerInvariant())) | Select-Object -First 6 | ForEach-Object { $_.ToString('x2') }))
  }
  $m = [System.Threading.Mutex]::new($false, $mutexName)
  try {
    $owned = try { $m.WaitOne(60000) } catch [System.Threading.AbandonedMutexException] { $true }
    if (-not $owned) { Write-Warning "Serveur de commande du plugin occupe depuis 60 s par un autre script : non verifie."; return $false }
    try {
      $running = Get-ControlVersion
      # Pas de reponse alors qu'un processus ecoute : serveur peut-etre juste lent, seconde chance de 10 s.
      if ($running -lt 0 -and (Get-PortListener $controlPort)) { $running = Get-ControlVersion 10 }
      if ($running -ge $controlVersion) { return $true }
      # Tout verifier avant d'arreter quoi que ce soit : sans serveur a lancer, celui en place continue.
      $shared = Join-Path $controlDir 'control-server.luau'
      if ((Get-ControlFileVersion $shared) -lt $controlVersion) {
        Write-Warning "Serveur de commande du plugin absent ou ancien ($shared) : lancer une fois CSGO_surf_combat\tools\rojo-plugin\install.ps1, puis redemarrer Studio."
        if ($running -eq 0) {
          Write-Warning "Un ancien serveur de commande (avant CSGO#589) tourne sur $controlPort : avec l'ancien plugin, il peut reconnecter cette fenetre a CSGO. Verifier le port connecte avant de tester."
        }
        return $false
      }
      $lune = (Get-Command lune -ErrorAction SilentlyContinue).Source
      if (-not $lune) { Write-Warning "lune introuvable : lancer ``rokit install`` dans $root."; return $false }
      # Ancienne version (ou serveur bloque) : processus lune qui ecoute, et pid enregistre s'il s'agit bien du serveur.
      $listener = Get-PortListener $controlPort
      if ($listener -and (Get-Process -Id $listener -ErrorAction SilentlyContinue).ProcessName -eq 'lune') { taskkill /PID $listener /T /F *> $null }
      Stop-ControlPid
      # Port encore tenu par autre chose (ancien serveur lance autrement, autre service) : lune ne pourrait pas s'y lier.
      for ($i = 0; $i -lt 10 -and (Get-PortListener $controlPort); $i++) { Start-Sleep -Milliseconds 200 }
      $other = Get-PortListener $controlPort
      if ($other) { Write-Warning "Port $controlPort tenu par un autre processus (pid $other) : serveur de commande non lance."; return $false }
      # Chemins entre apostrophes dans -Command : une apostrophe du chemin y est doublee.
      $q = { param($s) "'" + ($s -replace "'", "''") + "'" }
      $log = Join-Path $controlDir 'control.log'
      $command = "& $(& $q $lune) run $(& $q $shared) $(& $q $controlDir) $controlPort *> $(& $q $log)"
      # Dossier de travail = racine du checkout principal (le shim Rokit de lune y trouve rokit.toml) : pas un worktree,
      # que le serveur bloquerait a sa suppression.
      $shell = (Get-Process -Id $PID).Path
      $proc = Start-Process -FilePath $shell -WorkingDirectory $root -WindowStyle Hidden -PassThru `
        -ArgumentList '-NoProfile', '-NonInteractive', '-Command', $command
      Write-Text $controlPidFile "$($proc.Id)"
      # Mutex garde jusqu'a la reponse (shim Rokit lent au premier lancement) : le script suivant ne le croit pas absent.
      for ($i = 0; $i -lt 40; $i++) {
        if ((Get-ControlVersion 1) -ge $controlVersion) { return $true }
        Start-Sleep -Milliseconds 500
      }
      Write-Warning "Le serveur de commande du plugin ne repond pas sur $controlPort : voir $log."
      return $false
    } finally { $m.ReleaseMutex() }
  } finally { $m.Dispose() }
}

# Cette methode permet d'attendre que le plugin signale la connexion de la place pour cette cible (meme `rev`, meme port)
# lorsque -AcquireStudio vient de la publier ; $false apres le delai (Studio ferme ou en Play, place non ouverte, plugin officiel).
function Wait-StudioConnected([string]$Rev, [int]$Port) {
  $deadline = (Get-Date).AddSeconds($connectWait)
  while ($true) {
    $s = Get-StudioState
    if ($s -and "$($s.rev)" -eq $Rev -and $s.state -eq 'connected' -and "$($s.port)" -eq "$Port") { return $true }
    if ((Get-Date) -ge $deadline) { return $false }
    Start-Sleep -Milliseconds 500
  }
}

# Cette methode permet de liberer le verrou Studio tenu par la branche courante (fin de verification, -Stop, -Remove) en
# renvoyant la place sur le Rojo principal s'il repond, sinon en la deconnectant ; port publie ('' = aucun), $null sans verrou.
function Release-StudioLock {
  $published = Invoke-Locked 'studio' {
    $lock = Get-StudioLock
    if (-not ($lock -and $lock.branch -eq $Branch)) { return $null }
    Remove-Item -Force $studioLock
    # Port libre : inutile d'attendre le refus de connexion (~2 s par adresse sous Windows).
    $mainUp = (Get-PortListener $basePort) -and (Get-UrlCode "http://127.0.0.1:$basePort/api/rojo") -eq 200
    $target = if ($mainUp) { "$basePort" } else { '' }
    # Publication impossible (fichier occupe) : le verrou reste libere, -Stop / -Remove continuent.
    try { [void](Set-StudioTarget $target) }
    catch { Write-Warning "Cible Studio non publiee ($($_.Exception.Message)) : la place reste sur son port, a deconnecter a la main." }
    return $target
  }
  # Pas de demarrage du serveur de commande ici (nettoyage planifie) : la reservation s'en est chargee.
  return $published
}

# Cette methode permet de decrire ou la liberation renvoie la place lorsqu'on l'affiche, avec le geste manuel si le plugin ne suit pas.
function Format-Released([string]$Target) {
  $where = if ($Target) { "cible publiee : checkout principal (port $Target)" } else { "cible publiee : deconnexion (Rojo du checkout principal arrete)" }
  $manual = if ($Target) { "plugin Rojo > Disconnect > port $Target > Connect" } else { 'plugin Rojo > Disconnect' }
  "$where ; si la place ne suit pas (plugin officiel, Studio ferme) : $manual"
}

if ($StudioStatus) {
  $lock = Get-StudioLock
  if ($lock) {
    $stale = Get-StudioLockStaleReason $lock
    Write-Host "Studio reserve par $(Format-StudioLock $lock)$(if ($stale) { " : abandonne ($stale), sera repris a la prochaine reservation" })."
  } else { Write-Host 'Studio libre.' }
  $conn = Get-StudioConnectedPorts
  Write-Host $(if ($conn) { "Studio connecte au(x) port(s) Rojo : $($conn -join ', ')." } else { "Studio n'est connecte a aucun serveur Rojo de ce depot." })
  $state = Get-StudioState
  if ($state) {
    $desc = if ($state.state -eq 'connected') { "connectee au port $($state.port)" } else { "$($state.state)" }
    Write-Host "Plugin autoconnect, dernier etat de la place Fling a Dummy : $desc."
    [void](Write-ForeignConnectionAlert $state)
  }
  return
}

if (-not $Branch) { throw 'Branche manquante : .\scripts\fad-worktree.ps1 <branche> [options] (seul -StudioStatus s''en passe).' }
$slug = Get-Slug $Branch
$dir = Join-Path $worktrees "fad-$slug"
$portFile = Join-Path $runDir "$slug.port"
$pidFile = Join-Path $runDir "$slug.pid"
$logFile = Join-Path $runDir "$slug.log"
$currentPort = Read-Int $portFile

if ($ReleaseStudio) {
  $released = Release-StudioLock
  if ($null -ne $released) { Write-Host "Studio libere par '$Branch' : $(Format-Released $released)." }
  else { Write-Host "Studio n'etait pas reserve par '$Branch'." }
  return
}

if ($AcquireStudio) {
  # Sans Rojo, le verrou serait aussitot considere comme abandonne (et Studio n'aurait rien a suivre).
  if (-not (Test-HolderRojo $Branch)) {
    if ($Branch -eq $mainBranch) { throw "Rojo ne tourne pas sur le port $basePort : lancer d'abord ``rojo serve`` dans le checkout principal." }
    throw "Rojo ne tourne pas pour '$Branch' : lancer d'abord .\scripts\fad-worktree.ps1 $Branch."
  }
  if ($Branch -eq $mainBranch) { $currentPort = $basePort }
  # Session et thread du demandeur, notes dans le verrou : un detenteur qui s'arrete sans liberer est reconnu (y compris main).
  $holderSession = $env:CLAUDE_CODE_SESSION_ID
  $holderThread = if ($holderSession) { Get-ThreadOf $holderSession } else { $null }
  $deadline = (Get-Date).AddMinutes($WaitStudio)
  while ($true) {
    $result = Invoke-Locked 'studio' {
      $lock = Get-StudioLock
      $taken = $null
      if ($lock -and $lock.branch -ne $Branch) {
        $stale = Get-StudioLockStaleReason $lock
        if (-not $stale) { return @{ ok = $false; lock = $lock } }
        $taken = "verrou de $(Format-StudioLock $lock) repris ($stale)"
      }
      # Studio connecte a 34900 a la main (pas par une liberation) : l'utilisateur y teste sans doute, la publication
      # couperait son test. Traite comme occupe ; main peut reserver (meme port).
      # Vaut aussi pour le detenteur qui re-reserve : l'utilisateur a pu se connecter a la main entre-temps.
      if ($Branch -ne $mainBranch -and (Test-ManualBaseConnection)) { return @{ ok = $false; manual = $true } }
      $since = if ($lock -and $lock.branch -eq $Branch) { $lock.since } else { Get-Date -Format 'yyyy-MM-dd HH:mm' }
      $content = [pscustomobject]@{ branch = $Branch; port = $currentPort; since = $since; session = $holderSession; thread = $holderThread }
      Write-Text $studioLock ($content | ConvertTo-Json)
      # Etat d'avant la publication : une connexion etrangere (CSGO) est signalee meme si la reconnexion reussit.
      $before = Get-StudioState
      # Cible publiee sous le mutex : deux agents ne publient jamais dans le desordre de leurs reservations. Echec (fichier
      # occupe) : le verrou reste pris, connexion a la main.
      $rev = try { Set-StudioTarget "$currentPort" }
      catch { Write-Warning "Cible Studio non publiee ($($_.Exception.Message)) : pas d'auto-connexion."; $null }
      return @{ ok = $true; taken = $taken; rev = $rev; before = $before }
    }
    if ($result.ok) { break }
    if ((Get-Date) -ge $deadline) {
      if ($result.manual) {
        Write-Host "Studio occupe : connecte a la main au checkout principal ($basePort), hors verrou (l'utilisateur y teste sans doute)."
        Write-Host "Demander a l'utilisateur ; s'il ne teste pas : plugin Rojo > Disconnect (ou main -AcquireStudio puis main -ReleaseStudio), puis relancer."
        exit 2
      }
      Write-Host "Studio occupe par $(Format-StudioLock $result.lock)."
      Write-Host "Continuer le travail sans Studio, puis relancer avec -AcquireStudio (ou -WaitStudio <minutes> pour attendre)."
      exit 2
    }
    Start-Sleep -Seconds 15
  }
  if ($result.taken) { Write-Host "Note : $($result.taken)." }
  Write-Host "Studio reserve pour '$Branch' (port $currentPort). Liberer des la verification finie : -ReleaseStudio."
  [void](Write-ForeignConnectionAlert $result.before)
  $controlUp = $result.rev -and (Start-RojoControl)
  if ($controlUp -and (Wait-StudioConnected $result.rev $currentPort)) {
    Write-Host "Studio connecte au port $currentPort (plugin Rojo autoconnect, place $($placeIds -join ', ')). Verifier le port affiche par le plugin avant de tester."
  } else {
    if (-not $controlUp) { Write-Host "Pas d'auto-connexion : cible non publiee ou serveur de commande du plugin indisponible (avertissement ci-dessus)." }
    else { Write-Host "Studio ne s'est pas connecte seul en $connectWait s (Studio ferme ou en Play, place non ouverte, plugin officiel ? voir CSGO_surf_combat\tools\rojo-plugin\README.md)." }
    Write-ConnectHelp $currentPort
    $after = Get-StudioState
    if ($after -and "$($after.rev)" -ne "$($result.before.rev)") { [void](Write-ForeignConnectionAlert $after) }
  }
  return
}

if ($RegisterThread) {
  Register-Owner $RegisterThread
  Write-Host "Thread $RegisterThread inscrit pour le nettoyage de '$Branch'."
  return
}

if ($Stop -or $Remove) {
  Assert-OwnWorktree
  # -Remove refuse avant de toucher a Rojo et au verrou : un refus previsible ne fait pas perdre Studio a la tache
  # (seul un echec de `git worktree remove`, dossier ouvert ailleurs, arrive apres l'arret).
  if ($Remove -and (Test-Path $dir)) {
    if (Test-WorktreeRegistered) {
      if (git -C $dir status --porcelain) { throw "Modifications non commitees dans $dir : commiter ou annuler avant -Remove." }
    } elseif (Get-ChildItem -Path $dir -Recurse -File -Force) {
      throw "$dir n'est pas un worktree git mais contient des fichiers : a verifier et supprimer a la main."
    }
  }
  $s = Stop-Rojo $currentPort
  Write-Host $(if ($s) { "Rojo arrete (port $currentPort)." } else { "Aucun Rojo en cours pour '$Branch'." })
  $released = Release-StudioLock
  if ($null -ne $released) { Write-Host "Studio libere par '$Branch' : $(Format-Released $released)." }
  if ($Stop) { return }

  $exists = Test-Path $dir
  if ($exists) {
    if (Test-WorktreeRegistered) {
      Invoke-GitLoud -C $root worktree remove --force $dir
      if ($LASTEXITCODE -ne 0) { throw "Suppression echouee : fermer les terminaux ouverts dans $dir (y compris le repertoire courant d'une session Claude), puis relancer -Remove." }
    } elseif (-not (Get-ChildItem -Path $dir -Recurse -File -Force)) {
      # Reliquat d'un -Remove interrompu : git a deja desinscrit le worktree, il ne reste que des dossiers vides.
      Remove-Item -Recurse -Force $dir -Confirm:$false
    } else {
      throw "$dir n'est pas un worktree git mais contient des fichiers : a verifier et supprimer a la main."
    }
  }
  Remove-Item -Force -ErrorAction SilentlyContinue $portFile, $logFile
  Unregister-Owner
  Write-Host $(if ($exists) { "Worktree supprime (branche '$Branch' conservee)." } else { "Rien a supprimer : pas de worktree $dir." })
  return
}

# Cette methode permet de verifier qu'un dossier de worktree existant peut etre reutilise (worktree du depot, bonne branche).
function Assert-Reusable {
  if (-not (Test-WorktreeRegistered)) { throw "$dir existe mais n'est pas un worktree du depot (reliquat ? -Remove puis relancer)." }
  $current = Get-WorktreeBranch $dir
  if ($current -ne $Branch) { throw "$dir est sur '$current' au lieu de '$Branch'." }
}

$created = $false
if (Test-Path $dir) { Assert-Reusable }
$hasOrigin = (git -C $root remote) -contains 'origin'
# Fetch hors mutex : un reseau lent ne bloque pas les autres agents (git verrouille lui-meme ses refs).
if (-not (Test-Path $dir) -and $hasOrigin) { Invoke-GitLoud -C $root fetch origin --quiet }

# Creation du worktree puis attribution du slot, sous mutex : deux agents ne prennent ni le meme port ni le meme dossier.
# Le port n'est reserve qu'une fois le worktree en place (un echec ne laisse rien derriere lui).
$port = Invoke-Locked 'state' {
  # Slot : celui demande, sinon celui deja attribue, sinon le premier numero >= 1 libre (ports des autres worktrees
  # et ports reellement ecoutes). Un slot demande deja attribue a un autre worktree, ou ecoute par autre chose que
  # Rojo, est refuse avant toute creation.
  $others = @{}
  foreach ($f in @(Get-ChildItem -Path $runDir -Filter '*.port' -File -ErrorAction SilentlyContinue)) {
    if ($f.FullName -ne $portFile) { $others[(Read-Int $f.FullName)] = $f.BaseName }
  }
  $n = $Slot
  if ($n -gt 0) {
    $want = $basePort + $n
    if ($others.ContainsKey($want)) { throw "Port $want deja attribue au worktree '$($others[$want])' : choisir un autre -Slot." }
    $l = Get-PortListener $want
    if ($l -and -not (Test-RojoProcess $l $want)) { throw "Port $want deja pris par un autre processus (pid $l) : choisir un autre -Slot." }
  } elseif ($currentPort -gt $basePort) {
    $n = $currentPort - $basePort
  } else {
    $n = 1
    while ($others.ContainsKey($basePort + $n) -or (Get-PortListener ($basePort + $n))) { $n++ }
  }

  if (Test-Path $dir) { Assert-Reusable }
  else {
    # Branche existante (locale ou origin) : on la reprend ; sinon creee depuis la base (origin si present).
    if (Test-Ref "refs/heads/$Branch") {
      Invoke-GitLoud -C $root worktree add $dir $Branch
    } elseif ($hasOrigin -and (Test-Ref "refs/remotes/origin/$Branch")) {
      Invoke-GitLoud -C $root worktree add --track -b $Branch $dir "origin/$Branch"
    } else {
      # Base locale en avance sur origin (commits pas encore pousses) : on part de la locale pour ne pas les perdre de vue.
      $start = $Base
      if ($hasOrigin -and (Test-Ref "refs/remotes/origin/$Base")) {
        Invoke-Quiet git -C $root merge-base --is-ancestor "origin/$Base" $Base | Out-Null
        $localAhead = ($LASTEXITCODE -eq 0) -and ((git -C $root rev-parse $Base) -ne (git -C $root rev-parse "origin/$Base"))
        if ($localAhead) { Write-Warning "'$Base' local est en avance sur origin/$Base : branche creee depuis le local (penser a pousser $Base)." }
        else { $start = "origin/$Base" }
      }
      # --no-track : la nouvelle branche ne suit pas origin/<base> (un `git push` partirait sinon vers la base).
      Invoke-GitLoud -C $root worktree add --no-track -b $Branch $dir $start
    }
    if ($LASTEXITCODE -ne 0) { throw "git worktree add a echoue" }
    $script:created = $true
  }
  Write-Text $portFile "$($basePort + $n)"
  return ($basePort + $n)
}
$Slot = $port - $basePort
# Slot change par -Slot : le Rojo de l'ancien port n'aurait plus de suivi (et bloquerait -Remove), on l'arrete.
if ($currentPort -gt 0 -and $port -ne $currentPort -and (Stop-Rojo $currentPort)) {
  Write-Host "Rojo de l'ancien port $currentPort arrete (slot change)."
}

# Inscription apres la creation : un echec ne laisse pas d'entree orpheline dans le registre.
if (-not $NoRegister) { Register-Owner }
Set-AgentSettings

$rojoCode = $null
if (-not $NoUp) {
  if (-not (Test-RojoRunning $slug)) {
    $listener = Get-PortListener $port
    if ($listener -and (Test-RojoProcess $listener $port)) {
      # `rojo serve --port <port>` lance a la main (worktree cree avant ce script) : repris tel quel.
      Write-Text $pidFile "$listener"
      # Limite : Windows n'expose pas simplement le dossier courant d'un processus ; le port attribue au worktree fait foi.
      Write-Host "Rojo deja lance sur le port $port (pid $listener) : repris. Verifier qu'il a bien ete lance dans $dir."
    } elseif ($listener) {
      throw "Port $port deja pris par un autre processus (pid $listener) : liberer le port ou relancer avec -Slot <autre>."
    } else {
      $rojo = (Get-Command rojo -ErrorAction SilentlyContinue).Source
      if (-not $rojo) { throw "rojo introuvable : lancer ``rokit install`` dans $root." }
      $shell = (Get-Process -Id $PID).Path
      $proc = Start-Process -FilePath $shell -WorkingDirectory $dir -WindowStyle Hidden -PassThru `
        -ArgumentList '-NoProfile', '-NonInteractive', '-Command', "& '$($rojo -replace "'", "''")' serve default.project.json --port $port *> '$($logFile -replace "'", "''")'"
      Write-Text $pidFile "$($proc.Id)"
    }
  }
  $rojoCode = Wait-Rojo "http://localhost:$port/api/rojo"
}

Write-Host ""
Write-Host "Worktree '$Branch' : $dir (slot $Slot$(if ($created) { ', cree' } else { ', reutilise' }))"
# Cette methode permet de formater l'etat du serveur pour le resume ([OK (200)] attendu par les briefs /delegate).
function Format-State($Code) { if ($NoUp) { '' } elseif ($Code -eq 200) { '  [OK (200)]' } else { "  [NE REPOND PAS$(if ($Code) { " ($Code)" })]" } }
Write-Host "  rojo : http://localhost:$port$(Format-State $rojoCode)"
if ($NoUp) { Write-Host "Rojo non demarre (-NoUp) : relancer sans -NoUp pour le demarrer."; return }
Write-Host "  journal : $logFile"
Write-Host "  Studio : -AcquireStudio le reserve et y connecte la place (plugin Rojo autoconnect) ; sinon plugin Rojo > port $port > Connect (mode Edit)."
if ($rojoCode -ne 200) { throw "Rojo ne repond pas sur le port $port : voir $logFile." }
