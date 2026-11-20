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
  Garde-fous : rien n'est arrete ni supprime si le helper T3 ne repond pas ou ne connait pas un des threads (missing) ;
  rien n'est supprime si gh ne repond pas, s'il reste des modifications non commitees, ou si la branche a des commits
  absents d'origin, meme quand son worktree a deja disparu (sauf ceux contenus dans une PR mergee, cas du squash-merge
  avec branche distante supprimee).
  A chaque passage, le checkout principal est avance en fast-forward sur origin/main s'il est sur main sans modification.
  Lance toutes les 10 minutes par la tache planifiee "Fling a Dummy worktree cleanup" (install-cleanup-task.ps1) ;
  journal dans worktrees\.cleanup.log.
  Compte GitHub : GH_CONFIG_DIR est lu dans .claude\settings.local.json du checkout principal s'il y est declare.
  -Gh : chemin de gh a utiliser (defaut : celui du PATH). La tache planifiee tourne sans profil PowerShell, donc sans
  les ajouts au PATH qu'il fait (ex. un shim qui choisit le compte) : install-cleanup-task.ps1 y fige le gh de la session
  qui l'installe. Quand gh echoue, son code de retour et sa sortie d'erreur sont journalises.

.EXAMPLE
  .\scripts\fad-worktree-cleanup.ps1 -DryRun
  .\scripts\fad-worktree-cleanup.ps1 -Gh "$HOME\bin\gh.exe"
#>
param([switch]$DryRun, [string]$Gh = 'gh')

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

# Cette methode permet de savoir si Studio a ete connecte a la main au Rojo du checkout principal (port 34900) lorsqu'on
# veut avancer main : un test y est sans doute en cours. Une connexion due a une liberation (cible publiee 34900) n'en est pas un.
function Test-StudioOnBase {
  # Meme port de base que fad-worktree.ps1 (FAD_BASE_PORT et FAD_FAKE_STUDIO_PORTS ne servent qu'aux tests).
  $basePort = if ($env:FAD_BASE_PORT) { [int]$env:FAD_BASE_PORT } else { 34900 }
  $onBase = if ($env:FAD_FAKE_STUDIO_PORTS) { "$basePort" -in ($env:FAD_FAKE_STUDIO_PORTS -split ',') }
  else {
    [bool](Get-NetTCPConnection -State Established -RemotePort $basePort -ErrorAction SilentlyContinue |
      Where-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName -like 'RobloxStudio*' })
  }
  if (-not $onBase) { return $false }
  try { $target = [IO.File]::ReadAllText((Join-Path $runDir 'studio.target')) | ConvertFrom-Json } catch { $target = $null }
  return "$($target.port)" -ne "$basePort"
}

# Cette methode permet de lire la branche qui detient le verrou Studio ($null s'il est libre ou illisible).
function Get-LockHolder {
  $f = Join-Path $runDir 'studio.lock'
  if (-not (Test-Path $f)) { return $null }
  try { return ([IO.File]::ReadAllText($f) | ConvertFrom-Json).branch } catch { return $null }
}

# Cette methode permet de savoir si une PR (mergee ou fermee) porte bien le travail actuel de la branche (sa pointe est
# contenue dans la tete de la PR), lorsqu'un nom de branche a pu servir a une tache plus ancienne.
function Test-PrCoversBranch([string]$Branch, $Pr) {
  git -C $root rev-parse --verify -q "refs/heads/$Branch" *> $null
  if ($LASTEXITCODE -ne 0) { return $true }  # branche locale deja supprimee : rien a perdre
  git -C $root cat-file -e "$($Pr.headRefOid)^{commit}" *> $null
  if ($LASTEXITCODE -ne 0) { return $false }
  git -C $root merge-base --is-ancestor "refs/heads/$Branch" $Pr.headRefOid *> $null
  return ($LASTEXITCODE -eq 0)
}

# Cette methode permet de lister les PR d'une branche (etat, commit de tete) lorsqu'il faut savoir si son travail est merge ;
# $null si gh ne repond pas (on ne supprime alors rien), la cause (code de retour, debut de la sortie d'erreur) dans $script:ghError.
function Get-BranchPrs([string]$Branch) {
  $script:ghError = $null
  $ErrorActionPreference = 'Continue'  # stderr de gh capture (2>&1) sans devenir une erreur bloquante
  try { $out = @(& $Gh pr list --repo $repo --head $Branch --state all --json number,state,headRefOid 2>&1) }
  catch { $script:ghError = "$Gh introuvable ou en erreur : $($_.Exception.Message)"; return $null }
  $code = $LASTEXITCODE
  $stderr = @($out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
  $json = ($out | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
  if ($code -ne 0 -or -not $json.Trim()) {
    # Une ligne, bornee : le message de gh ne contient pas de jeton, mais le journal reste lisible.
    $detail = (($stderr -join ' | ') -replace '\s+', ' ')
    if ($detail.Length -gt 200) { $detail = $detail.Substring(0, 200) + '...' }
    $script:ghError = "code $code$(if ($detail) { " : $detail" } else { ', sans sortie d''erreur' })"
    return $null
  }
  # La virgule garde un tableau vide (branche sans PR) : sans elle, l'appelant recevrait $null, comme une panne de gh.
  try { return , @($json | ConvertFrom-Json) } catch { $script:ghError = "sortie JSON illisible : $($_.Exception.Message)"; return $null }
}

# Cette methode permet de dire pourquoi un worktree ou sa branche locale ne peuvent pas etre supprimes sans perte
# (modifications non commitees, commits non pousses) ; renvoie $null s'il n'y a rien a perdre. Les commits sont lus sur
# la branche elle-meme, meme si le dossier du worktree a disparu. Ceux deja contenus dans une PR mergee (squash-merge,
# branche distante supprimee) sont surs.
function Get-UnsafeReason([string]$Dir, [string]$Branch, $Prs) {
  # Dossier sans .git : reliquat vide d'un -Remove interrompu, git status y lirait le checkout principal.
  if ((Test-Path (Join-Path $Dir '.git')) -and @(git -C $Dir status --porcelain).Count -gt 0) { return 'modifications non commitees' }
  git -C $root rev-parse --verify -q "refs/heads/$Branch" *> $null
  if ($LASTEXITCODE -ne 0) { return $null }
  $local = @(git -C $root rev-list "refs/heads/$Branch" --not --remotes)
  # Branche rebasee et force-pushee : les anciennes versions des commits ont un equivalent (meme patch) sur origin.
  git -C $root rev-parse --verify -q "refs/remotes/origin/$Branch" *> $null
  if ($local -and $LASTEXITCODE -eq 0) {
    $alreadyPushed = @(git -C $root cherry "origin/$Branch" "refs/heads/$Branch" | Where-Object { $_ -like '- *' } | ForEach-Object { $_.Substring(2) })
    $local = @($local | Where-Object { $_ -notin $alreadyPushed })
  }
  foreach ($pr in @($Prs | Where-Object { $_.state -eq 'MERGED' })) {
    if (-not $local) { break }
    git -C $root cat-file -e "$($pr.headRefOid)^{commit}" *> $null
    if ($LASTEXITCODE -ne 0) { continue }
    $inPr = @(git -C $root rev-list $pr.headRefOid)
    $local = @($local | Where-Object { $_ -notin $inPr })
  }
  if ($local.Count -eq 0) { return $null }
  return "$($local.Count) commit(s) absents d'origin"
}

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
  # Pas pendant un test sur le checkout principal (Studio connecte au port de base, ou verrou tenu par main) : Rojo
  # pousserait le nouveau code dans la place en plein test.
  $mainInUse = (Test-StudioOnBase) -or ((Get-LockHolder) -eq $mainBranch)
  if ($mainInUse) { Write-Log "MAJ $mainBranch reportee : Studio utilise le checkout principal" -Once }
  if (-not $DryRun -and -not $mainInUse -and (git -C $root branch --show-current) -eq $mainBranch -and -not (git -C $root status --porcelain --untracked-files=no)) {
    $ErrorActionPreference = 'Continue'
    git -C $root merge --ff-only --quiet "origin/$mainBranch" *>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { Write-Log "MAJ $mainBranch impossible en fast-forward (checkout principal diverge d'origin/$mainBranch)" -Once }
  }
  if (-not (Test-Path $ownersFile)) { return }
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
    # Seuls des etats certains comptent : un thread `missing` (base T3 deplacee, id errone) n'est pas un thread fini.
    $unknown = @($threads | Where-Object { $states.$_ -notin 'active', 'settled', 'archived', 'deleted' })
    if ($unknown) { Write-Log "GARDE $branch : thread(s) inconnu(s) de T3 ($($unknown -join ', '))" -Once; continue }
    if (@($threads | Where-Object { $states.$_ -eq 'active' })) { continue }

    # Travail clos : PR mergee (ou fermee sans merge) et aucune PR encore ouverte sur la branche -> suppression.
    $prs = Get-BranchPrs $branch
    $open = @($prs | Where-Object { $_.state -eq 'OPEN' })
    # Une ancienne PR mergee sous le meme nom de branche ne compte pas : il faut qu'elle contienne la pointe actuelle.
    $delivered = $null -ne $prs -and @($prs | Where-Object { $_.state -eq 'MERGED' -and (Test-PrCoversBranch $branch $_) }) -and -not $open
    $abandoned = $null -ne $prs -and -not $delivered -and @($prs | Where-Object { $_.state -eq 'CLOSED' -and (Test-PrCoversBranch $branch $_) }) -and -not $open

    # Palier 1 : threads termines mais travail non clos (PR ouverte ou absente, ou gh muet) -> arret de Rojo seulement.
    if (-not ($delivered -or $abandoned)) {
      if ($null -eq $prs) { Write-Log "gh sans reponse pour $branch : suppression impossible, Rojo seulement ($script:ghError)" -Once }
      if (-not (Test-Path (Join-Path $runDir "$slug.pid"))) { continue }
      if ($DryRun) { Write-Host "A ARRETER $branch"; continue }
      try {
        & $worktreeScript $branch -Stop *>&1 | Out-Null
        Write-Log "ARRETE $branch (threads termines, PR non mergee)"
      } catch { Write-Log "ECHEC arret $branch : $($_.Exception.Message)" -Once }
      continue
    }

    # Verifie meme sans dossier de worktree : la branche locale est supprimee juste apres (PR mergee).
    $reason = Get-UnsafeReason $dir $branch $prs
    if ($reason) { Write-Log "GARDE $branch (threads termines) : $reason" -Once; continue }
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
