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
  .\scripts\fad-worktree.ps1 feature/x -ReleaseStudio                # libere (aussi fait par -Stop et -Remove)
  .\scripts\fad-worktree.ps1 -StudioStatus                           # detenteur actuel et port auquel Studio est connecte
  Un verrou est repris d'office si son detenteur n'a plus de worktree, plus de Rojo, ou plus de thread T3 actif.
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
$basePort = 34900
# Control server du plugin Rojo « CSGO autoconnect » : tant qu'il n'est pas multi-projets, il peut reconnecter cette place a CSGO.
$csgoControlPort = 34870
$helper = Join-Path $PSScriptRoot 't3_threads.py'

# Cle propre a ce checkout pour les mutex : deux checkouts (ou un bac a sable de test) ne se bloquent pas entre eux.
$sha = [Security.Cryptography.SHA256]::Create()
$rootKey = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant())) | Select-Object -First 6 |
    ForEach-Object { $_.ToString('x2') })

# Cette methode permet de calculer le slug d'une branche (nom des dossiers et fichiers d'etat) : `/` et accents -> `-`.
function Get-Slug([string]$Name) { $Name -replace '[^A-Za-z0-9._-]', '-' }

# Cette methode permet de lire un fichier texte en UTF-8 (y compris sous Windows PowerShell 5.1) ; $null s'il manque.
function Read-Text([string]$Path) { if (Test-Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path) } else { $null } }

# Cette methode permet d'ecrire un fichier d'etat en UTF-8 sans BOM, en creant son dossier au besoin.
function Write-Text([string]$Path, [string]$Text) {
  New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
  [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
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

# Cette methode permet de retrouver le thread T3 d'une session Claude ; $null si le helper echoue ou ne la connait pas.
function Get-ThreadOf([string]$Session) {
  try { $out = python -I $helper thread-of $Session 2>$null } catch { return $null }
  if ($LASTEXITCODE -ne 0) { return $null }
  $t = "$out".Trim()
  if ($t) { return $t }
  return $null
}

# Cette methode permet de connaitre l'etat de threads T3 (active, settled, archived...) lorsqu'on juge un verrou ;
# $null si le helper est en panne (on ne conclut alors rien).
function Get-ThreadStates([string[]]$Threads) {
  try { $out = python -I $helper status @Threads 2>$null } catch { return $null }
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
  git -C $root show-ref --verify --quiet $Ref
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
# apres un redemarrage : sa ligne de commande cite `rojo`, `serve` et `--port <port>`.
function Test-RojoProcess([int]$Id, [int]$Port) {
  if ($Id -le 0 -or $Port -le 0) { return $false }
  $p = Get-CimInstance Win32_Process -Filter "ProcessId = $Id" -ErrorAction SilentlyContinue
  if (-not $p) { return $false }
  $cl = "$($p.CommandLine)"
  return ($cl -match 'rojo') -and ($cl -match '\bserve\b') -and ($cl -match "--port\s+$Port\b")
}

# Cette methode permet de savoir si le serveur Rojo enregistre pour un slug (pid et port de worktrees\.run) tourne encore.
function Test-RojoRunning([string]$ForSlug) {
  Test-RojoProcess (Read-Int (Join-Path $runDir "$ForSlug.pid")) (Read-Int (Join-Path $runDir "$ForSlug.port"))
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
  $holderSlug = Get-Slug $Lock.branch
  if (-not (Test-Path (Join-Path $worktrees "fad-$holderSlug"))) { return 'worktree supprime' }
  if (-not (Test-RojoRunning $holderSlug)) { return 'Rojo arrete' }
  try { $entry = Get-Owners | Where-Object { $_.branch -eq $Lock.branch } | Select-Object -First 1 } catch { $entry = $null }
  $threads = @($entry.threads | Where-Object { $_ })
  if ($threads) {
    $states = Get-ThreadStates $threads
    if ($states -and -not @($threads | Where-Object { $states.$_ -eq 'active' })) { return 'threads T3 termines' }
  }
  return $null
}

# Cette methode permet de lister les ports Rojo (checkout principal et worktrees) auxquels Studio est connecte en ce moment,
# lorsqu'il faut dire a l'agent ou a l'utilisateur s'il doit faire Disconnect avant de se connecter ailleurs.
function Get-StudioConnectedPorts {
  $ports = @($basePort) + @(Get-ChildItem -Path $runDir -Filter '*.port' -File -ErrorAction SilentlyContinue |
      ForEach-Object { Read-Int $_.FullName })
  @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
      Where-Object { $_.LocalPort -in $ports } | Select-Object -ExpandProperty LocalPort -Unique | Sort-Object)
}

# Cette methode permet de decrire en une ligne le detenteur du verrou Studio lorsqu'on l'affiche.
function Format-StudioLock($Lock) { "'$($Lock.branch)' (port $($Lock.port), depuis $($Lock.since))" }

# Cette methode permet d'expliquer la connexion manuelle de Studio a un port (le plugin Rojo officiel, ou CSGO autoconnect,
# ne suit pas encore le verrou de ce depot) en signalant le port auquel Studio est deja connecte.
function Write-ConnectHelp([int]$Port) {
  $conn = @(Get-StudioConnectedPorts | Where-Object { $_ -ne $Port })
  $from = if ($conn) { "Disconnect dans le plugin Rojo (connecte au port $($conn -join ', ')), puis " } else { '' }
  Write-Host "Connexion (Studio en mode Edit, place 88580736516669) : $($from)plugin Rojo > port $Port > Connect."
  if (Get-PortListener $csgoControlPort) {
    Write-Host "Attention : le serveur de commande CSGO autoconnect (port $csgoControlPort) tourne et peut reconnecter cette fenetre a CSGO : verifier le port connecte avant de tester."
  }
}

# Cette methode permet de liberer le verrou Studio lorsqu'il est tenu par la branche courante (fin de verification, -Stop, -Remove).
function Release-StudioLock {
  Invoke-Locked 'studio' {
    $lock = Get-StudioLock
    if ($lock -and $lock.branch -eq $Branch) { Remove-Item -Force $studioLock; return $true }
    return $false
  }
}

if ($StudioStatus) {
  $lock = Get-StudioLock
  if ($lock) {
    $stale = Get-StudioLockStaleReason $lock
    Write-Host "Studio reserve par $(Format-StudioLock $lock)$(if ($stale) { " : abandonne ($stale), sera repris a la prochaine reservation" })."
  } else { Write-Host 'Studio libre.' }
  $conn = Get-StudioConnectedPorts
  Write-Host $(if ($conn) { "Studio connecte au(x) port(s) Rojo : $($conn -join ', ')." } else { "Studio n'est connecte a aucun serveur Rojo de ce depot." })
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
  if (Release-StudioLock) {
    Write-Host "Studio libere par '$Branch'."
    Write-Host "Pour rendre la place au checkout principal : plugin Rojo > Disconnect > port $basePort > Connect (si son Rojo tourne)."
  } else { Write-Host "Studio n'etait pas reserve par '$Branch'." }
  return
}

if ($AcquireStudio) {
  # Sans Rojo, le verrou serait aussitot considere comme abandonne (et Studio n'aurait rien a suivre).
  if (-not (Test-RojoRunning $slug)) { throw "Rojo ne tourne pas pour '$Branch' : lancer d'abord .\scripts\fad-worktree.ps1 $Branch." }
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
      $since = if ($lock -and $lock.branch -eq $Branch) { $lock.since } else { Get-Date -Format 'yyyy-MM-dd HH:mm' }
      Write-Text $studioLock ([pscustomobject]@{ branch = $Branch; port = $currentPort; since = $since } | ConvertTo-Json)
      return @{ ok = $true; taken = $taken }
    }
    if ($result.ok) { break }
    if ((Get-Date) -ge $deadline) {
      Write-Host "Studio occupe par $(Format-StudioLock $result.lock)."
      Write-Host "Continuer le travail sans Studio, puis relancer avec -AcquireStudio (ou -WaitStudio <minutes> pour attendre)."
      exit 2
    }
    Start-Sleep -Seconds 15
  }
  if ($result.taken) { Write-Host "Note : $($result.taken)." }
  Write-Host "Studio reserve pour '$Branch' (port $currentPort). Liberer des la verification finie : -ReleaseStudio."
  Write-ConnectHelp $currentPort
  return
}

if ($RegisterThread) {
  Register-Owner $RegisterThread
  Write-Host "Thread $RegisterThread inscrit pour le nettoyage de '$Branch'."
  return
}

if ($Stop -or $Remove) {
  Assert-OwnWorktree
  $s = Stop-Rojo $currentPort
  Write-Host $(if ($s) { "Rojo arrete (port $currentPort)." } else { "Aucun Rojo en cours pour '$Branch'." })
  if (Release-StudioLock) { Write-Host "Studio libere par '$Branch'." }
  if ($Stop) { return }

  $exists = Test-Path $dir
  if ($exists) {
    if (Test-WorktreeRegistered) {
      if (git -C $dir status --porcelain) { throw "Modifications non commitees dans $dir : commiter ou annuler avant -Remove." }
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

# Creation du worktree puis attribution du slot, sous mutex : deux agents ne prennent ni le meme port ni le meme dossier.
# Le port n'est reserve qu'une fois le worktree en place (un echec ne laisse rien derriere lui).
$port = Invoke-Locked 'state' {
  # Slot : celui demande, sinon celui deja attribue, sinon le premier numero >= 1 libre (ports des autres worktrees
  # et ports reellement ecoutes). Un slot demande deja attribue a un autre worktree est refuse avant toute creation.
  $others = @{}
  foreach ($f in @(Get-ChildItem -Path $runDir -Filter '*.port' -File -ErrorAction SilentlyContinue)) {
    if ($f.FullName -ne $portFile) { $others[(Read-Int $f.FullName)] = $f.BaseName }
  }
  $n = $Slot
  if ($n -le 0 -and $currentPort -gt $basePort) { $n = $currentPort - $basePort }
  if ($n -gt 0) {
    if ($others.ContainsKey($basePort + $n)) { throw "Port $($basePort + $n) deja attribue au worktree '$($others[$basePort + $n])' : choisir un autre -Slot." }
  } else {
    $n = 1
    while ($others.ContainsKey($basePort + $n) -or (Get-PortListener ($basePort + $n))) { $n++ }
  }

  if (Test-Path $dir) { Assert-Reusable }
  else {
    $hasOrigin = (git -C $root remote) -contains 'origin'
    if ($hasOrigin) { Invoke-GitLoud -C $root fetch origin --quiet }
    # Branche existante (locale ou origin) : on la reprend ; sinon creee depuis la base (origin si present).
    if (Test-Ref "refs/heads/$Branch") {
      Invoke-GitLoud -C $root worktree add $dir $Branch
    } elseif ($hasOrigin -and (Test-Ref "refs/remotes/origin/$Branch")) {
      Invoke-GitLoud -C $root worktree add --track -b $Branch $dir "origin/$Branch"
    } else {
      # Base locale en avance sur origin (commits pas encore pousses) : on part de la locale pour ne pas les perdre de vue.
      $start = $Base
      if ($hasOrigin -and (Test-Ref "refs/remotes/origin/$Base")) {
        git -C $root merge-base --is-ancestor "origin/$Base" $Base 2>$null
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
      Write-Host "Rojo deja lance sur le port $port (pid $listener) : repris."
    } elseif ($listener) {
      throw "Port $port deja pris par un autre processus (pid $listener) : liberer le port ou relancer avec -Slot <autre>."
    } else {
      $rojo = (Get-Command rojo -ErrorAction SilentlyContinue).Source
      if (-not $rojo) { throw "rojo introuvable : lancer ``rokit install`` dans $root." }
      $shell = (Get-Process -Id $PID).Path
      $proc = Start-Process -FilePath $shell -WorkingDirectory $dir -WindowStyle Hidden -PassThru `
        -ArgumentList '-NoProfile', '-NonInteractive', '-Command', "& '$rojo' serve default.project.json --port $port *> '$logFile'"
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
Write-Host "  Studio : reserver d'abord (-AcquireStudio), puis plugin Rojo > port $port > Connect (mode Edit)."
if ($rojoCode -ne 200) { throw "Rojo ne repond pas sur le port $port : voir $logFile." }
