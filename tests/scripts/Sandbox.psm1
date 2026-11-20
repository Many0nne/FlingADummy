<#
  Bac a sable des tests des scripts de worktree (Pester 3.4, livre avec Windows) : un depot jetable dans %TEMP% avec son
  propre origin (depot nu), une copie des scripts du depot, et des faux pour tout ce qui sort du depot :
  - t3_threads.py remplace par un faux qui lit un JSON (sessions -> threads, etats des threads, panne simulee) ;
  - gh remplace par un gh.ps1 en tete du PATH, qui lit un JSON (branche -> PR) ;
  - rojo remplace par un rojo.ps1 qui repond 200 a toute requete HTTP sur le port demande ;
  - auto-connexion Studio : registre commun jetable (ROJO_AUTOCONNECT_DIR), serveur de commande sur le port 35870
    (FAD_CONTROL_PORT, faux /health de http.ps1), faux lune.ps1 qui en demarre un, faux plugin.ps1 qui suit la cible.
  Les scripts calculent leur racine depuis leur propre emplacement : la copie ne touche ni worktrees\.owners.json, ni
  worktrees\.run, ni la tache planifiee du vrai checkout, et leurs mutex sont propres a chaque racine.
  Limite connue : le port de base 34900 est fige dans le script ; les tests qui demarrent un faux Rojo passent -Slot >= 600.
#>

$script:SourceScripts = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts'

$fakeT3 = @'
"""Faux t3_threads.py : lit l'etat simule dans le JSON pointe par FAD_FAKE_T3."""
import json
import os
import sys

with open(os.environ["FAD_FAKE_T3"], encoding="utf-8") as f:
    data = json.load(f)
if data.get("fail"):
    sys.exit(1)
if sys.argv[1] == "thread-of":
    print(data.get("sessions", {}).get(sys.argv[2], ""))
elif sys.argv[1] == "status":
    print(json.dumps({t: data.get("threads", {}).get(t, "missing") for t in sys.argv[2:]}))
'@

$fakeGh = @'
# Faux gh : seul `gh pr list --head <branche>` est simule, a partir du JSON pointe par FAD_FAKE_GH.
$data = Get-Content $env:FAD_FAKE_GH -Raw | ConvertFrom-Json -AsHashtable
if ($data.fail) { exit 1 }
$branch = $args[[array]::IndexOf($args, '--head') + 1]
$prs = $data.prs[$branch]
if (-not $prs) { '[]' } else { ConvertTo-Json @($prs) -Compress }
'@

$fakeRojo = @'
# Faux rojo : `rojo serve ... --port N` repond 200 a toute requete HTTP (IPv4 et IPv6).
$port = [int]$args[[array]::IndexOf($args, '--port') + 1]
$listener = [System.Net.Sockets.TcpListener]::Create($port)
$listener.Start()
while ($true) {
  $client = $listener.AcceptTcpClient()
  $stream = $client.GetStream()
  $buffer = New-Object byte[] 4096
  [void]$stream.Read($buffer, 0, $buffer.Length)
  $body = '{"serverVersion":"fake"}'
  $bytes = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n$body")
  $stream.Write($bytes, 0, $bytes.Length)
  $client.Close()
}
'@

$fakeHttp = @'
# Faux serveur HTTP : `http.ps1 <port> <corps> [marqueur]` repond 200 text/plain <corps> a toute requete (faux serveur de
# commande du plugin : /health). Le marqueur (ex. control-server.luau) ne sert qu'a la ligne de commande du processus.
$port = [int]$args[0]
$body = [string]$args[1]
$listener = [System.Net.Sockets.TcpListener]::Create($port)
$listener.Start()
while ($true) {
  $client = $listener.AcceptTcpClient()
  $stream = $client.GetStream()
  $buffer = New-Object byte[] 4096
  [void]$stream.Read($buffer, 0, $buffer.Length)
  $bytes = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: text/plain`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n$body")
  $stream.Write($bytes, 0, $bytes.Length)
  $client.Close()
}
'@

$fakeLune = @'
# Faux lune : `lune run <control-server.luau> <dossier> <port>` demarre un faux serveur de commande v3 sur le port
# passe en argument, comme le vrai serveur. Sans port, le vrai prendrait 34870 (celui du poste) : le faux refuse.
if ($args.Count -lt 4) { exit 1 }
& (Join-Path $PSScriptRoot 'http.ps1') $args[3] 'rojo-control 3' 'control-server.luau'
'@

$fakePlugin = @'
# Faux plugin autoconnect : `plugin.ps1 <target> <status>` suit la cible comme le plugin (au changement de rev) et
# signale aussitot l'etat obtenu dans le fichier status.
$target = $args[0]; $status = $args[1]; $last = $null
while ($true) {
  try { $t = [IO.File]::ReadAllText($target) | ConvertFrom-Json } catch { $t = $null }
  if ($t -and "$($t.rev)" -ne $last) {
    $last = "$($t.rev)"
    $state = if ("$($t.port)") { 'connected' } else { 'disconnected' }
    [IO.File]::WriteAllText($status, (@{ rev = $last; state = $state; port = "$($t.port)" } | ConvertTo-Json -Compress))
  }
  Start-Sleep -Milliseconds 200
}
'@

# Cette methode permet de lancer git dans le bac a sable en echouant au premier code de sortie non nul.
# Fonction simple (sans param) : les options git comme --quiet passent telles quelles dans $args.
function Invoke-Git {
  $Dir = $args[0]
  $GitArgs = @($args | Select-Object -Skip 1)
  $ErrorActionPreference = 'Continue'
  $out = & git -C $Dir @GitArgs 2>&1
  if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') : $out" }
  $out
}

# Cette methode permet de creer un bac a sable complet (depot, origin, faux gh/t3/rojo) lorsqu'un groupe de tests demarre ;
# renvoie un objet avec ses chemins.
function New-Sandbox {
  $rootDir = Join-Path ([IO.Path]::GetTempPath()) "fad-sbx-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
  $sb = [pscustomobject]@{
    Root = $rootDir
    Origin = Join-Path $rootDir 'origin.git'
    Repo = Join-Path $rootDir 'repo'
    Bin = Join-Path $rootDir 'bin'
    T3File = Join-Path $rootDir 't3.json'
    GhFile = Join-Path $rootDir 'gh.json'
    # Registre commun et serveur de commande du plugin : jamais ceux du poste (%LOCALAPPDATA%\RojoAutoconnect, 34870).
    ControlDir = Join-Path $rootDir 'autoconnect'
    ControlPort = 35870
    Dummies = [System.Collections.Generic.List[int]]::new()
  }
  New-Item -ItemType Directory -Force $sb.Root, $sb.Bin, $sb.Repo | Out-Null
  Invoke-Git $sb.Root init --quiet --bare --initial-branch=main $sb.Origin | Out-Null
  Invoke-Git $sb.Repo init --quiet --initial-branch=main | Out-Null
  Invoke-Git $sb.Repo config user.name 'Sandbox' | Out-Null
  Invoke-Git $sb.Repo config user.email 'sandbox@example.invalid' | Out-Null
  Invoke-Git $sb.Repo config commit.gpgsign false | Out-Null
  New-Item -ItemType Directory -Force (Join-Path $sb.Repo 'scripts') | Out-Null
  Copy-Item (Join-Path $script:SourceScripts '*.ps1') (Join-Path $sb.Repo 'scripts')
  Set-Content (Join-Path $sb.Repo 'scripts\t3_threads.py') $fakeT3
  Set-Content (Join-Path $sb.Repo '.gitignore') '/worktrees/'
  Set-Content (Join-Path $sb.Repo 'default.project.json') '{ "name": "sandbox", "tree": { "$className": "DataModel" } }'
  Invoke-Git $sb.Repo add -A | Out-Null
  Invoke-Git $sb.Repo commit --quiet -m init | Out-Null
  Invoke-Git $sb.Repo remote add origin $sb.Origin | Out-Null
  Invoke-Git $sb.Repo push --quiet -u origin main | Out-Null
  Set-Content (Join-Path $sb.Bin 'gh.ps1') $fakeGh
  Set-Content (Join-Path $sb.Bin 'rojo.ps1') $fakeRojo
  Set-Content (Join-Path $sb.Bin 'http.ps1') $fakeHttp
  Set-Content (Join-Path $sb.Bin 'lune.ps1') $fakeLune
  Set-Content (Join-Path $sb.Bin 'plugin.ps1') $fakePlugin
  Set-FakeT3 $sb
  Set-FakeGh $sb
  $sb
}

# Cette methode permet de simuler la base T3 (session -> thread, etat de chaque thread, ou panne du helper).
function Set-FakeT3($Sb, [hashtable]$Sessions = @{}, [hashtable]$Threads = @{}, [switch]$Fail) {
  @{ sessions = $Sessions; threads = $Threads; fail = [bool]$Fail } | ConvertTo-Json -Depth 4 | Set-Content $Sb.T3File
}

# Cette methode permet de simuler les PR GitHub par branche (liste de @{ number; state; headRefOid }), ou une panne de gh.
function Set-FakeGh($Sb, [hashtable]$Prs = @{}, [switch]$Fail) {
  @{ prs = $Prs; fail = [bool]$Fail } | ConvertTo-Json -Depth 5 | Set-Content $Sb.GhFile
}

# Cette methode permet de preparer l'environnement d'un script du bac a sable (faux en tete du PATH, session Claude simulee)
# et de le restaurer apres ; $null pour la session = lancement hors Claude.
function Use-SandboxEnv($Sb, [string]$Session, [scriptblock]$Action) {
  $vars = @{
    PATH = "$($Sb.Bin);$env:PATH"; FAD_FAKE_T3 = $Sb.T3File; FAD_FAKE_GH = $Sb.GhFile
    CLAUDE_CODE_SESSION_ID = $(if ($Session) { $Session } else { $null }); GH_CONFIG_DIR = $null
    ROJO_AUTOCONNECT_DIR = $Sb.ControlDir; FAD_CONTROL_PORT = "$($Sb.ControlPort)"; FAD_CONNECT_WAIT = '2'
    # Connexions de Studio simulees ('0' = aucune) : le vrai Studio du poste, connecte a 34900, ne compte jamais.
    FAD_FAKE_STUDIO_PORTS = $(if ($env:FAD_FAKE_STUDIO_PORTS) { $env:FAD_FAKE_STUDIO_PORTS } else { '0' })
  }
  $saved = @{}
  foreach ($k in $vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $vars[$k]) }
  try { & $Action } finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
}

# Cette methode permet de lancer un script du bac a sable dans un shell separe (un throw ou un exit n'arrete pas les tests) ;
# renvoie le code de sortie et la sortie complete. -Shell powershell : Windows PowerShell 5.1 (lancement depuis un vieux shell).
function Invoke-SandboxScript($Sb, [string]$Name, [string[]]$ArgList = @(), [string]$Session, [string]$Shell = 'pwsh') {
  Use-SandboxEnv $Sb $Session {
    $shellArgs = @('-NoProfile', '-NonInteractive')
    if ($Shell -eq 'powershell') { $shellArgs += @('-ExecutionPolicy', 'Bypass') }
    $out = & $Shell @shellArgs -File (Join-Path $Sb.Repo "scripts\$Name") @ArgList 2>&1 | Out-String
    [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
  }
}

# Cette methode permet de lancer fad-worktree.ps1 du bac a sable.
function Invoke-Wt($Sb, [string[]]$ArgList, [string]$Session, [string]$Shell = 'pwsh') {
  Invoke-SandboxScript $Sb 'fad-worktree.ps1' $ArgList $Session $Shell
}

# Cette methode permet de lancer la copie de fad-worktree.ps1 d'un worktree du bac a sable (et non celle du checkout
# principal), comme le fait l'agent d'une tache depuis son worktree.
function Invoke-WtFrom($Sb, [string]$Dir, [string[]]$ArgList) {
  Use-SandboxEnv $Sb $null {
    $out = & pwsh -NoProfile -NonInteractive -File (Join-Path $Dir 'scripts\fad-worktree.ps1') @ArgList 2>&1 | Out-String
    [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
  }
}

# Cette methode permet de lancer un faux serveur de commande du plugin (reponse <Body> a /health) sur le port du bac a
# sable, avec `control-server.luau` dans sa ligne de commande comme le vrai ; renvoie son pid une fois le port ecoute.
function Start-FakeControl($Sb, [string]$Body = 'rojo-control 3') {
  $p = Start-Process pwsh -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-NonInteractive',
    '-File', (Join-Path $Sb.Bin 'http.ps1'), "$($Sb.ControlPort)", "`"$Body`"", 'control-server.luau'
  $Sb.Dummies.Add($p.Id)
  for ($i = 0; $i -lt 50 -and -not (Get-NetTCPConnection -LocalPort $Sb.ControlPort -State Listen -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 200 }
  $p.Id
}

# Cette methode permet d'arreter tout serveur qui ecoute sur le port de commande du bac a sable.
function Stop-FakeControl($Sb) {
  Get-NetTCPConnection -LocalPort $Sb.ControlPort -State Listen -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
  for ($i = 0; $i -lt 25 -and (Get-NetTCPConnection -LocalPort $Sb.ControlPort -State Listen -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 200 }
}

# Cette methode permet de lire la reponse /health du port de commande du bac a sable ($null si rien ne repond).
function Get-FakeHealth($Sb) {
  try { "$((Invoke-WebRequest "http://127.0.0.1:$($Sb.ControlPort)/health" -TimeoutSec 3 -UseBasicParsing).Content)".Trim() } catch { $null }
}

# Cette methode permet de lancer un faux plugin autoconnect qui suit la cible du bac a sable ; renvoie son pid.
function Start-FakePlugin($Sb) {
  $run = Join-Path $Sb.Repo 'worktrees\.run'
  $p = Start-Process pwsh -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-NonInteractive',
    '-File', (Join-Path $Sb.Bin 'plugin.ps1'), (Join-Path $run 'studio.target'), (Join-Path $run 'studio.status')
  $Sb.Dummies.Add($p.Id)
  $p.Id
}

# Cette methode permet de lancer le nettoyage du bac a sable (son mutex est propre au bac a sable).
function Invoke-Cleanup($Sb, [string[]]$ArgList = @()) {
  Invoke-SandboxScript $Sb 'fad-worktree-cleanup.ps1' $ArgList
}

# Cette methode permet de lancer plusieurs appels de fad-worktree.ps1 en meme temps (courses entre agents) ;
# chaque element de $Calls est @{ Args = @(...); Session = '...' }. Renvoie code et sortie de chacun.
function Invoke-WtParallel($Sb, [object[]]$Calls) {
  $script = Join-Path $Sb.Repo 'scripts\fad-worktree.ps1'
  $procs = foreach ($c in $Calls) {
    $out = Join-Path $Sb.Root "par-$([guid]::NewGuid().ToString('N')).log"
    $p = Use-SandboxEnv $Sb $c.Session {
      Start-Process pwsh -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError "$out.err" `
        -ArgumentList (@('-NoProfile', '-NonInteractive', '-File', $script) + $c.Args)
    }
    [pscustomobject]@{ Process = $p; Out = $out }
  }
  foreach ($p in $procs) {
    $p.Process.WaitForExit()
    [pscustomobject]@{ Code = $p.Process.ExitCode; Output = (Get-Content $p.Out, "$($p.Out).err" -Raw -ErrorAction SilentlyContinue) -join "`n" }
  }
}

# Cette methode permet de lancer un processus sans rapport avec Rojo (ping), pour simuler un pid recycle par Windows.
function Start-Dummy($Sb) {
  $p = Start-Process ping -ArgumentList '-n', '900', '127.0.0.1' -WindowStyle Hidden -PassThru
  $Sb.Dummies.Add($p.Id)
  $p.Id
}

# Cette methode permet de lancer un faux `rojo serve --port N` a la main (hors script), comme sur un worktree cree a la
# main ; renvoie son pid une fois le port ecoute.
function Start-ManualRojo($Sb, [string]$Dir, [int]$Port) {
  $p = Start-Process pwsh -WorkingDirectory $Dir -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-NonInteractive',
    '-File', (Join-Path $Sb.Bin 'rojo.ps1'), 'serve', 'default.project.json', '--port', "$Port"
  $Sb.Dummies.Add($p.Id)
  for ($i = 0; $i -lt 50 -and -not (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 200 }
  $p.Id
}

# Cette methode permet de savoir si un processus tourne encore.
function Test-Alive([int]$ProcessId) { [bool](Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) }

# Cette methode permet de calculer le slug d'une branche comme le font les scripts.
function Get-Slug([string]$Branch) { $Branch -replace '[^A-Za-z0-9._-]', '-' }

# Cette methode permet de connaitre les chemins d'etat d'une branche du bac a sable (worktree, port, pid, registre, verrou).
function Get-SbPaths($Sb, [string]$Branch) {
  $slug = Get-Slug $Branch
  $run = Join-Path $Sb.Repo 'worktrees\.run'
  [pscustomobject]@{
    Dir = Join-Path $Sb.Repo "worktrees\fad-$slug"; Port = Join-Path $run "$slug.port"; Pid = Join-Path $run "$slug.pid"
    Run = $run; Owners = Join-Path $Sb.Repo 'worktrees\.owners.json'; Lock = Join-Path $run 'studio.lock'
    Log = Join-Path $Sb.Repo 'worktrees\.cleanup.log'
    Target = Join-Path $run 'studio.target'; Status = Join-Path $run 'studio.status'
    Registry = Join-Path $Sb.ControlDir 'projects\fad.json'
  }
}

# Cette methode permet de lire le pid du Rojo enregistre pour une branche du bac a sable (0 si aucun).
function Get-SbRojoPid($Sb, [string]$Branch) {
  $f = (Get-SbPaths $Sb $Branch).Pid
  if (Test-Path $f) { return [int](Get-Content $f) }
  return 0
}

# Cette methode permet de lire le registre des proprietaires du bac a sable en UTF-8 (tableau vide s'il manque).
function Get-SbOwners($Sb) {
  $f = Join-Path $Sb.Repo 'worktrees\.owners.json'
  if (-not (Test-Path $f)) { return @() }
  @(foreach ($o in ([IO.File]::ReadAllText($f) | ConvertFrom-Json)) { $o })
}

# Cette methode permet de commiter un fichier dans un worktree du bac a sable, et de le pousser si demande ; renvoie le sha.
function Add-SbCommit($Sb, [string]$Branch, [string]$File = 'travail.txt', [switch]$Push) {
  $dir = (Get-SbPaths $Sb $Branch).Dir
  Add-Content (Join-Path $dir $File) "ligne $(Get-Random)"
  Invoke-Git $dir add -A | Out-Null
  Invoke-Git $dir -c user.name=Sandbox -c user.email=sandbox@example.invalid commit --quiet -m "travail sur $Branch" | Out-Null
  if ($Push) { Invoke-Git $dir push --quiet -u origin $Branch | Out-Null }
  (Invoke-Git $dir rev-parse HEAD | Select-Object -First 1).Trim()
}

# Cette methode permet de detruire le bac a sable : processus factices, faux Rojo lances depuis ses worktrees, worktrees, dossiers.
function Remove-Sandbox($Sb) {
  foreach ($id in $Sb.Dummies) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
  # Faux Rojo : seulement les processus dont la ligne de commande cite le bac a sable.
  Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe' OR Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like "*$($Sb.Root)*" -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Milliseconds 300
  if ($Sb.Root -notlike "$([IO.Path]::GetTempPath())fad-sbx-*") { throw "Refus de supprimer $($Sb.Root) : hors du dossier temporaire." }
  Remove-Item -Recurse -Force $Sb.Root -ErrorAction SilentlyContinue
}

Export-ModuleMember -Function *
