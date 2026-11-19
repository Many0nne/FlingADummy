<#
.SYNOPSIS
  Libere les ressources des worktrees Fling a Dummy dont les threads T3 ne sont plus actifs (settled, archives ou
  supprimes), en deux paliers :
  - PR de la branche pas encore mergee (ou pas de PR) : arret du serveur Rojo seulement
    (reversible, relancer fad-worktree.ps1 <branche> pour reprendre) ;
  - PR de la branche mergee, ou fermee sans merge, et aucune PR encore ouverte : suppression du worktree
    (fad-worktree.ps1 -Remove) ; la branche locale est aussi supprimee si la PR est mergee, gardee si elle est fermee
    sans merge. Fermer ou archiver un thread ne supprime jamais rien a lui seul.
  Un thread settled qui recoit un nouveau message redevient actif : rien n'est touche. Une session inscrite
  pas encore rattachee a un thread (premier tour en cours) et active depuis moins de 30 min bloque aussi l'entree.
  Le lien worktree -> threads vient du registre worktrees\.owners.json, rempli par fad-worktree.ps1.
  Garde-fous : rien n'est arrete ni supprime si le helper T3 ne repond pas ; rien n'est supprime si gh ne repond pas,
  s'il reste des modifications non commitees, ou des commits absents d'origin (sauf ceux contenus dans une PR mergee,
  cas du squash-merge avec branche distante supprimee).
  A chaque passage, le checkout principal est avance en fast-forward sur origin/main s'il est sur main sans modification.
  Lance toutes les 10 minutes par la tache planifiee "Fling a Dummy worktree cleanup" (install-cleanup-task.ps1) ;
  journal dans worktrees\.cleanup.log.
  Compte GitHub : GH_CONFIG_DIR est lu dans .claude\settings.local.json du checkout principal s'il y est declare.

.EXAMPLE
  .\scripts\fad-worktree-cleanup.ps1 -DryRun
#>
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
# Racine du checkout principal, meme si le script est lance depuis la copie d'un worktree.
$root = (Resolve-Path (Split-Path -Parent (git -C $PSScriptRoot rev-parse --path-format=absolute --git-common-dir))).Path
$ownersFile = Join-Path $root 'worktrees\.owners.json'
$logFile = Join-Path $root 'worktrees\.cleanup.log'
$runDir = Join-Path $root 'worktrees\.run'
$helper = Join-Path $PSScriptRoot 't3_threads.py'
$worktreeScript = Join-Path $PSScriptRoot 'fad-worktree.ps1'
$repo = 'Many0nne/FlingADummy'
$mainBranch = 'main'

# Compte gh du projet : la tache planifiee tourne hors de Claude, elle reprend donc le GH_CONFIG_DIR declare pour Claude
# dans .claude\settings.local.json (non versionne) ; sans ce fichier, gh utilise son compte par defaut (ou le shim du poste).
$localSettings = Join-Path $root '.claude\settings.local.json'
if (-not $env:GH_CONFIG_DIR -and (Test-Path $localSettings)) {
  try {
    $ghConfigDir = ([IO.File]::ReadAllText($localSettings) | ConvertFrom-Json).env.GH_CONFIG_DIR
    if ($ghConfigDir) { $env:GH_CONFIG_DIR = $ghConfigDir }
  } catch { Write-Host "settings.local.json illisible, compte gh par defaut : $_" }
}

# Cette methode permet de tracer une decision du nettoyage (console et journal) lorsqu'un worktree est arrete, garde ou supprime ;
# avec -Once, un message deja present dans la fin du journal n'est pas repete (execution toutes les 10 minutes).
function Write-Log([string]$Message, [switch]$Once) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm') $Message"
  Write-Host $line
  if ($DryRun) { return }
  if ($Once -and (Test-Path $logFile) -and (@(Get-Content $logFile -Tail 200) -replace '^\S+ \S+ ', '') -contains $Message) { return }
  New-Item -ItemType Directory -Force (Split-Path -Parent $logFile) | Out-Null
  Add-Content $logFile $line
}

# Cette methode permet de savoir si une session Claude a ecrit son transcript recemment (moins de 30 min),
# lorsqu'elle n'est pas encore rattachee a un thread T3 : elle est alors consideree comme active.
function Test-RecentSession([string]$SessionId) {
  $limit = (Get-Date).AddMinutes(-30)
  [bool](Get-ChildItem (Join-Path $HOME '.claude\projects\*') -Filter "$SessionId.jsonl" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt $limit })
}

# Cette methode permet d'interroger le helper T3 ; renvoie sa sortie, ou $null s'il echoue (python absent, base illisible).
function Invoke-Helper {
  try { $out = python -I $helper @args 2>$null } catch { return $null }
  if ($LASTEXITCODE -ne 0) { return $null }
  return "$out".Trim()
}

# Cette methode permet de lister les PR d'une branche (etat, commit de tete) lorsqu'il faut savoir si son travail est merge ;
# $null si gh ne repond pas (on ne supprime alors rien).
function Get-BranchPrs([string]$Branch) {
  try { $json = gh pr list --repo $repo --head $Branch --state all --json number,state,headRefOid 2>$null } catch { return $null }
  if ($LASTEXITCODE -ne 0 -or -not "$json".Trim()) { return $null }
  try { return @("$json" | ConvertFrom-Json) } catch { return $null }
}

# Cette methode permet de dire pourquoi un worktree ne peut pas etre supprime sans perte lorsqu'il a du travail non pousse ;
# renvoie $null s'il est sur. Les commits deja contenus dans une PR mergee (squash-merge, branche distante supprimee) sont surs.
function Get-UnsafeReason([string]$Dir, [string]$Branch, $Prs) {
  if (@(git -C $Dir status --porcelain).Count -gt 0) { return 'modifications non commitees' }
  $local = @(git -C $Dir rev-list HEAD --not --remotes)
  # Branche rebasee et force-pushee : les anciennes versions des commits ont un equivalent (meme patch) sur origin.
  if ($local -and (git -C $Dir rev-parse --verify -q "refs/remotes/origin/$Branch")) {
    $alreadyPushed = @(git -C $Dir cherry "origin/$Branch" HEAD | Where-Object { $_ -like '- *' } | ForEach-Object { $_.Substring(2) })
    $local = @($local | Where-Object { $_ -notin $alreadyPushed })
  }
  foreach ($pr in @($Prs | Where-Object { $_.state -eq 'MERGED' })) {
    if (-not $local) { break }
    git -C $Dir cat-file -e "$($pr.headRefOid)^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) { continue }
    $inPr = @(git -C $Dir rev-list $pr.headRefOid)
    $local = @($local | Where-Object { $_ -notin $inPr })
  }
  if ($local.Count -eq 0) { return $null }
  return "$($local.Count) commit(s) absents d'origin"
}

if (-not (Test-Path $ownersFile)) { return }
# Tache planifiee et lancement manuel peuvent se chevaucher : une seule execution a la fois (mutex propre a ce checkout).
$sha = [Security.Cryptography.SHA256]::Create()
$rootKey = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant())) | Select-Object -First 6 |
    ForEach-Object { $_.ToString('x2') })
$mutex = [System.Threading.Mutex]::new($false, "Local\fad-cleanup-$rootKey")
try { if (-not $mutex.WaitOne(0)) { return } } catch [System.Threading.AbandonedMutexException] { }
try {
  $ErrorActionPreference = 'Continue'
  git -C $root fetch origin --quiet 2>$null
  $ErrorActionPreference = 'Stop'
  # Scripts du checkout principal (dont celui-ci) a jour apres un merge : fast-forward de main, seulement si le checkout
  # est sur main sans modification suivie. Pris en compte des le -Remove ci-dessous, et pour ce script au passage suivant.
  if (-not $DryRun -and (git -C $root branch --show-current) -eq $mainBranch -and -not (git -C $root status --porcelain --untracked-files=no)) {
    $ErrorActionPreference = 'Continue'
    git -C $root merge --ff-only --quiet "origin/$mainBranch" *>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { Write-Log "MAJ $mainBranch impossible en fast-forward (checkout principal diverge d'origin/$mainBranch)" -Once }
  }
  try { $owners = @(foreach ($o in ([IO.File]::ReadAllText($ownersFile) | ConvertFrom-Json)) { if ($o.branch) { $o } }) }
  catch { Write-Log "Registre $ownersFile illisible : rien n'est nettoye tant qu'il n'est pas repare ($($_.Exception.Message))" -Once; return }
  foreach ($entry in $owners) {
    $branch = [string]$entry.branch
    $slug = $branch -replace '[^A-Za-z0-9._-]', '-'
    $dir = Join-Path $root "worktrees\fad-$slug"

    # Threads connus, completes par les sessions resolues depuis (session lancee avant la creation de son thread).
    $threads = @($entry.threads | Where-Object { $_ })
    $recentUnresolved = $false
    foreach ($s in @($entry.sessions | Where-Object { $_ })) {
      $t = Invoke-Helper thread-of $s
      if ($t) { if ($t -notin $threads) { $threads += $t } }
      elseif (Test-RecentSession $s) { $recentUnresolved = $true }
    }
    # Thread T3 tout juste lance : le lien session -> thread n'est ecrit qu'apres son premier tour.
    if ($recentUnresolved) { continue }
    if (-not $threads) { continue }  # session hors T3 (terminal) : jamais nettoye automatiquement
    $statesJson = Invoke-Helper status @threads
    $states = if ($statesJson) { try { $statesJson | ConvertFrom-Json } catch { $null } }
    if (-not $states) { Write-Log "GARDE $branch : helper T3 sans reponse" -Once; continue }
    if (@($threads | Where-Object { $states.$_ -eq 'active' })) { continue }

    # Travail clos : PR mergee (ou fermee sans merge) et aucune PR encore ouverte sur la branche -> suppression.
    $prs = Get-BranchPrs $branch
    $open = @($prs | Where-Object { $_.state -eq 'OPEN' })
    $delivered = $null -ne $prs -and @($prs | Where-Object { $_.state -eq 'MERGED' }) -and -not $open
    $abandoned = $null -ne $prs -and -not $delivered -and @($prs | Where-Object { $_.state -eq 'CLOSED' }) -and -not $open

    # Palier 1 : threads termines mais travail non clos (PR ouverte ou absente, ou gh muet) -> arret de Rojo seulement.
    if (-not ($delivered -or $abandoned)) {
      if ($null -eq $prs) { Write-Log "gh sans reponse pour $branch : suppression impossible, Rojo seulement" -Once }
      if (-not (Test-Path (Join-Path $runDir "$slug.pid"))) { continue }
      if ($DryRun) { Write-Host "A ARRETER $branch"; continue }
      try {
        & $worktreeScript $branch -Stop *>&1 | Out-Null
        Write-Log "ARRETE $branch (threads termines, PR non mergee)"
      } catch { Write-Log "ECHEC arret $branch : $($_.Exception.Message)" -Once }
      continue
    }

    # Dossier sans .git : reliquat vide d'un -Remove interrompu, git status y lirait le checkout principal.
    if (Test-Path (Join-Path $dir '.git')) {
      $reason = Get-UnsafeReason $dir $branch $prs
      if ($reason) { Write-Log "GARDE $branch (threads termines) : $reason" -Once; continue }
    }
    $why = if ($delivered) { 'PR mergee, threads termines' } else { 'PR fermee sans merge, threads termines' }
    if ($DryRun) { Write-Host "A SUPPRIMER $branch ($why) : fad-worktree.ps1 $branch -Remove"; continue }
    try {
      & $worktreeScript $branch -Remove *>&1 | Out-Null
      # PR mergee : la branche locale n'a plus d'usage (son travail est sur origin, verifie ci-dessus). Fermee sans merge : gardee.
      if ($delivered) {
        $ErrorActionPreference = 'Continue'
        git -C $root branch -D $branch *>&1 | Out-Null
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -eq 0) { $why += ', branche locale supprimee' }
      }
      Write-Log "SUPPRIME $branch ($why)"
    } catch {
      $ErrorActionPreference = 'Stop'
      Write-Log "ECHEC $branch : $($_.Exception.Message)" -Once
    }
  }
} finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
