<#
  Tests de limites des scripts de worktree (fad-worktree.ps1, fad-worktree-cleanup.ps1), dans un bac a sable jetable
  (voir Sandbox.psm1). Chaque test decrit le comportement attendu : un echec signale un bug, pas un test a ajuster.
  Lancement (Windows, pwsh 7, Pester 3.4 livre avec Windows), depuis la racine du depot ou d'un worktree :
    Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester tests/scripts
  Les tests qui demarrent un faux Rojo ou declarent un pid passent -Slot >= 600 pour rester loin des ports reels.
#>
Import-Module (Join-Path $PSScriptRoot 'Sandbox.psm1') -Force

Describe 'fad-worktree.ps1 : cycle nominal' {
  $sb = New-Sandbox
  Set-FakeT3 $sb -Sessions @{ 'S-nom' = 'T-nom' } -Threads @{ 'T-nom' = 'active' }
  $p = Get-SbPaths $sb 'feature/1-nominal'

  It 'cree le worktree, reserve le port du slot et inscrit le thread T3' {
    $r = Invoke-Wt $sb @('feature/1-nominal', '-NoUp', '-Slot', '600') 'S-nom'
    $r.Code | Should Be 0
    $p.Dir | Should Exist
    (Get-Content $p.Port) | Should Be '35500'
    $entry = Get-SbOwners $sb | Where-Object { $_.branch -eq 'feature/1-nominal' }
    @($entry.threads) -contains 'T-nom' | Should Be $true
  }

  It 'la nouvelle branche ne suit pas origin/main (un push simple ne partirait pas vers la base)' {
    & git -C $p.Dir rev-parse --abbrev-ref '@{u}' 2>$null
    $LASTEXITCODE | Should Not Be 0
  }

  It 'est idempotent : relance sur le meme worktree garde le slot' {
    $r = Invoke-Wt $sb @('feature/1-nominal', '-NoUp') 'S-nom'
    $r.Code | Should Be 0
    $r.Output | Should Match 'reutilise'
    (Get-Content $p.Port) | Should Be '35500'
    @((Get-SbOwners $sb | Where-Object { $_.branch -eq 'feature/1-nominal' }).threads).Count | Should Be 1
  }

  It 'demarre Rojo et repond 200, puis -Stop l''arrete' {
    $r = Invoke-Wt $sb @('feature/1-nominal') 'S-nom'
    $r.Output | Should Match 'OK \(200\)'
    $rojoPid = Get-SbRojoPid $sb 'feature/1-nominal'
    (Invoke-Wt $sb @('feature/1-nominal', '-Stop')).Code | Should Be 0
    Start-Sleep -Milliseconds 500
    Test-Alive $rojoPid | Should Be $false
  }

  It 'refuse -Remove avec des modifications non commitees' {
    Set-Content (Join-Path $p.Dir 'brouillon.txt') 'x'
    (Invoke-Wt $sb @('feature/1-nominal', '-Remove')).Code | Should Not Be 0
    $p.Dir | Should Exist
    Remove-Item (Join-Path $p.Dir 'brouillon.txt')
  }

  It '-Remove supprime le worktree, le port et l''entree du registre' {
    (Invoke-Wt $sb @('feature/1-nominal', '-Remove')).Code | Should Be 0
    $p.Dir | Should Not Exist
    $p.Port | Should Not Exist
    @(Get-SbOwners $sb | Where-Object { $_.branch -eq 'feature/1-nominal' }).Count | Should Be 0
  }

  It 'autorise la session du worktree a ecrire dans .briefs et %TEMP%, sans salir git status' {
    $r = Invoke-Wt $sb @('feature/3-reglages', '-NoUp', '-Slot', '602')
    $r.Code | Should Be 0
    $d = (Get-SbPaths $sb 'feature/3-reglages').Dir
    $dirs = @((Get-Content -Raw (Join-Path $d '.claude\settings.local.json') | ConvertFrom-Json).permissions.additionalDirectories)
    $dirs -contains (Join-Path $sb.Repo 'worktrees\.briefs') | Should Be $true
    $dirs -contains [IO.Path]::GetTempPath().TrimEnd('\', '/') | Should Be $true
    Invoke-Git $d status --porcelain | Should BeNullOrEmpty
  }

  It 'garde les reglages deja presents dans settings.local.json et ne duplique rien a la relance' {
    $d = (Get-SbPaths $sb 'feature/3-reglages').Dir
    $f = Join-Path $d '.claude\settings.local.json'
    Set-Content $f '{ "env": { "X": "1" }, "permissions": { "additionalDirectories": ["C:\\autre"] } }'
    (Invoke-Wt $sb @('feature/3-reglages', '-NoUp')).Code | Should Be 0
    (Invoke-Wt $sb @('feature/3-reglages', '-NoUp')).Code | Should Be 0
    $s = Get-Content -Raw $f | ConvertFrom-Json
    $s.env.X | Should Be '1'
    @($s.permissions.additionalDirectories).Count | Should Be 3
    @($s.permissions.additionalDirectories)[0] | Should Be 'C:\autre'
  }

  It 'accepte une branche avec des accents' {
    $r = Invoke-Wt $sb @('feature/2-réglages', '-NoUp', '-Slot', '601')
    $r.Code | Should Be 0
    (Get-SbPaths $sb 'feature/2-réglages').Dir | Should Exist
    $r = Invoke-Wt $sb @('feature/2-réglages', '-NoUp')
    $r.Code | Should Be 0
    $r.Output | Should Match 'reutilise'
  }

  It '-StudioStatus marche sans branche' {
    $r = Invoke-Wt $sb @('-StudioStatus')
    $r.Code | Should Be 0
    $r.Output | Should Match 'Studio libre'
  }

  Remove-Sandbox $sb
}

Describe 'fad-worktree.ps1 : reprise d''un worktree cree a la main' {
  $sb = New-Sandbox
  $branch = 'feature/11-main'
  $p = Get-SbPaths $sb $branch
  Invoke-Git $sb.Repo worktree add --quiet -b $branch $p.Dir | Out-Null
  Set-Content (Join-Path $p.Dir 'en-cours.txt') 'travail non commite'
  $settings = Join-Path $p.Dir '.claude\settings.local.json'
  New-Item -ItemType Directory -Force (Split-Path $settings) | Out-Null
  $before = @{ permissions = @{ additionalDirectories = @((Join-Path $sb.Repo 'worktrees\.briefs'), [IO.Path]::GetTempPath().TrimEnd('\', '/')) } } |
    ConvertTo-Json -Depth 4
  Set-Content $settings $before

  It 'reprend le dossier tel quel : modifications, reglages et branche gardes' {
    $r = Invoke-Wt $sb @($branch, '-NoUp', '-NoRegister', '-Slot', '630')
    $r.Code | Should Be 0
    $r.Output | Should Match 'reutilise'
    (Get-Content (Join-Path $p.Dir 'en-cours.txt')) | Should Be 'travail non commite'
    (Get-Content -Raw $settings).Trim() | Should Be $before.Trim()
    (Invoke-Git $p.Dir branch --show-current) | Should Be $branch
    (Get-Content $p.Port) | Should Be '35530'
  }

  It 'reprend un rojo serve lance a la main sur le port du worktree' {
    $manual = Start-ManualRojo $sb $p.Dir 35530
    $r = Invoke-Wt $sb @($branch)
    $r.Output | Should Match 'repris'
    $r.Output | Should Match 'OK \(200\)'
    Get-SbRojoPid $sb $branch | Should Be $manual
    Invoke-Wt $sb @($branch, '-Stop') | Out-Null
    Start-Sleep -Milliseconds 500
    Test-Alive $manual | Should Be $false
  }

  It 'refuse un slot deja attribue a un autre worktree, sans rien creer' {
    $r = Invoke-Wt $sb @('feature/12-collision', '-NoUp', '-Slot', '630')
    $r.Code | Should Not Be 0
    $r.Output | Should Match 'deja attribue'
    (Get-SbPaths $sb 'feature/12-collision').Dir | Should Not Exist
    (Get-SbPaths $sb 'feature/12-collision').Port | Should Not Exist
  }

  It 'refuse un slot impose dont le port est pris par un processus qui n''est pas Rojo, sans rien reserver' {
    $tcp = [System.Net.Sockets.TcpListener]::Create(35531)
    $tcp.Start()
    try {
      (Invoke-Wt $sb @('feature/13-port-pris', '-Slot', '631')).Output | Should Match 'deja pris'
      (Get-SbPaths $sb 'feature/13-port-pris').Port | Should Not Exist
      (Get-SbPaths $sb 'feature/13-port-pris').Dir | Should Not Exist
    } finally { $tcp.Stop() }
  }

  It 'changer de slot arrete le Rojo de l''ancien port' {
    (Invoke-Wt $sb @($branch)).Output | Should Match 'OK \(200\)'
    $old = Get-SbRojoPid $sb $branch
    $r = Invoke-Wt $sb @($branch, '-Slot', '632')
    $r.Output | Should Match 'ancien port 35530 arrete'
    Start-Sleep -Milliseconds 500
    Test-Alive $old | Should Be $false
    (Get-Content $p.Port) | Should Be '35532'
    Invoke-Wt $sb @($branch, '-Stop') | Out-Null
  }

  Remove-Sandbox $sb
}

Describe 'fad-worktree.ps1 : entrees qui se chevauchent ou echouent' {
  $sb = New-Sandbox
  Set-FakeT3 $sb -Sessions @{ 'S-c' = 'T-c' } -Threads @{ 'T-c' = 'active' }

  It 'deux branches au meme slug : -Stop et -Remove de l''une ne touchent pas l''autre' {
    (Invoke-Wt $sb @('feature/a-b', '-Slot', '640')).Code | Should Be 0
    $rojo = Get-SbRojoPid $sb 'feature/a-b'
    (Invoke-Wt $sb @('feature-a/b', '-Stop')).Code | Should Not Be 0
    (Invoke-Wt $sb @('feature-a/b', '-Remove')).Code | Should Not Be 0
    (Get-SbPaths $sb 'feature/a-b').Dir | Should Exist
    Test-Alive $rojo | Should Be $true
  }

  It 'une creation qui echoue (base inexistante) ne laisse ni port reserve ni entree au registre' {
    $r = Invoke-Wt $sb @('feature/3-base', '-Base', 'nexistepas', '-NoUp', '-Slot', '603') 'S-c'
    $r.Code | Should Not Be 0
    (Get-SbPaths $sb 'feature/3-base').Port | Should Not Exist
    @(Get-SbOwners $sb | Where-Object { $_.branch -eq 'feature/3-base' }).Count | Should Be 0
  }

  It 'un registre .owners.json illisible ne bloque pas la creation d''un worktree et n''est pas ecrase' {
    $p = Get-SbPaths $sb 'feature/4-registre'
    New-Item -ItemType Directory -Force (Split-Path $p.Owners) | Out-Null
    Set-Content $p.Owners '[{"branch": "feature/x", tronque'
    $r = Invoke-Wt $sb @('feature/4-registre', '-NoUp', '-Slot', '604') 'S-c'
    $r.Code | Should Be 0
    $p.Dir | Should Exist
    (Get-Content $p.Owners -Raw) | Should Match 'tronque'
  }

  It 'une branche existante seulement sur origin est reprise en suivi' {
    Invoke-Git $sb.Repo branch 'feature/5-distante' | Out-Null
    Invoke-Git $sb.Repo push --quiet origin 'feature/5-distante' | Out-Null
    Invoke-Git $sb.Repo branch -D 'feature/5-distante' | Out-Null
    (Invoke-Wt $sb @('feature/5-distante', '-NoUp', '-Slot', '605')).Code | Should Be 0
    (Invoke-Git (Get-SbPaths $sb 'feature/5-distante').Dir rev-parse --abbrev-ref '@{u}') | Should Be 'origin/feature/5-distante'
  }

  It 'un dossier existant sur une autre branche est refuse' {
    $d = (Get-SbPaths $sb 'feature/5-distante').Dir
    Invoke-Git $d switch --quiet -c 'feature/5-autre' | Out-Null
    (Invoke-Wt $sb @('feature/5-distante', '-NoUp')).Code | Should Not Be 0
  }

  Remove-Sandbox $sb
}

# Repris de CSGO (issue #111) : l'inscription plantait selon la forme du registre ou le shell.
Describe 'fad-worktree.ps1 : inscription quelle que soit la forme du registre' {
  $sb = New-Sandbox
  Set-FakeT3 $sb -Sessions @{ 'S-r' = 'T-r' } -Threads @{ 'T-r' = 'active' }
  $owners = (Get-SbPaths $sb 'x').Owners
  New-Item -ItemType Directory -Force (Split-Path $owners) | Out-Null
  $hasPs5 = [bool](Get-Command powershell -ErrorAction SilentlyContinue)

  It 'registre vide : la session est inscrite, sans entree nulle' {
    Set-Content $owners ''
    (Invoke-Wt $sb @('feature/5-vide', '-NoUp', '-Slot', '620') 'S-r').Code | Should Be 0
    $all = @(Get-SbOwners $sb)
    $all.Count | Should Be 1
    @($all[0].sessions) -contains 'S-r' | Should Be $true
  }

  It 'entree sans propriete sessions (ancien format) : la session est ajoutee, les threads gardes' {
    Set-Content $owners '[{"branch":"feature/6-ancien","threads":["T-old"]}]'
    (Invoke-Wt $sb @('feature/6-ancien', '-NoUp', '-Slot', '621') 'S-r').Code | Should Be 0
    $entry = Get-SbOwners $sb | Where-Object { $_.branch -eq 'feature/6-ancien' }
    @($entry.sessions) -contains 'S-r' | Should Be $true
    @($entry.threads) -contains 'T-old' | Should Be $true
    @($entry.threads) -contains 'T-r' | Should Be $true
  }

  It '-RegisterThread inscrit seulement le thread, sans creer de worktree' {
    (Invoke-Wt $sb @('feature/9-delegue', '-RegisterThread', 'T-del') 'S-r').Code | Should Be 0
    $entry = Get-SbOwners $sb | Where-Object { $_.branch -eq 'feature/9-delegue' }
    @($entry.threads) -contains 'T-del' | Should Be $true
    @($entry.sessions).Count | Should Be 0
    (Get-SbPaths $sb 'feature/9-delegue').Dir | Should Not Exist
  }

  It '-NoRegister n''inscrit pas la session courante' {
    (Invoke-Wt $sb @('feature/9-norg', '-NoUp', '-NoRegister', '-Slot', '624') 'S-r').Code | Should Be 0
    @(Get-SbOwners $sb | Where-Object { $_.branch -eq 'feature/9-norg' }).Count | Should Be 0
  }

  It 'Windows PowerShell 5.1, branche deja inscrite : la relance reussit' {
    if (-not $hasPs5) { return }
    Set-Content $owners '[{"branch":"feature/7-ps5","sessions":["S-a"],"threads":[]},{"branch":"feature/autre","sessions":[],"threads":[]}]'
    $r = Invoke-Wt $sb @('feature/7-ps5', '-NoUp', '-Slot', '622') 'S-r' 'powershell'
    $r.Output | Should Not Match 'sessions'
    $r.Code | Should Be 0
    $entry = Get-SbOwners $sb | Where-Object { $_.branch -eq 'feature/7-ps5' }
    @($entry.sessions) -contains 'S-a' | Should Be $true
    @($entry.sessions) -contains 'S-r' | Should Be $true
  }

  It 'Windows PowerShell 5.1, branche accentuee : le registre reste en UTF-8 et les entrees existantes intactes' {
    if (-not $hasPs5) { return }
    Set-Content $owners '[{"branch":"feature/autre","sessions":["S-a"],"threads":[]}]'
    (Invoke-Wt $sb @('feature/8-réglé', '-NoUp', '-Slot', '623') 'S-r' 'powershell').Code | Should Be 0
    $branches = @(Get-SbOwners $sb | ForEach-Object { $_.branch })
    ($branches -join ',') | Should Be 'feature/autre,feature/8-réglé'
  }

  Remove-Sandbox $sb
}

Describe 'fad-worktree.ps1 : creations simultanees (plusieurs agents)' {
  $sb = New-Sandbox
  $branches = 1..4 | ForEach-Object { "feature/5$_-parallele" }
  $sessions = @{}; $threads = @{}
  foreach ($i in 1..4) { $sessions["S-p$i"] = "T-p$i"; $threads["T-p$i"] = 'active' }
  Set-FakeT3 $sb -Sessions $sessions -Threads $threads
  $results = Invoke-WtParallel $sb @(1..4 | ForEach-Object { @{ Args = @($branches[$_ - 1], '-NoUp'); Session = "S-p$_" } })

  It 'les quatre creations reussissent' {
    @($results | Where-Object { $_.Code -ne 0 }).Count | Should Be 0
  }

  It 'chaque worktree recoit un port different' {
    $ports = @($branches | ForEach-Object { $f = (Get-SbPaths $sb $_).Port; if (Test-Path $f) { Get-Content $f } })
    @($ports | Select-Object -Unique).Count | Should Be 4
  }

  It 'le registre garde les quatre branches' {
    $known = @(Get-SbOwners $sb | ForEach-Object { $_.branch })
    @($branches | Where-Object { $_ -notin $known }).Count | Should Be 0
  }

  Remove-Sandbox $sb
}

Describe 'fad-worktree.ps1 : pid recycle par Windows (apres un redemarrage)' {
  $sb = New-Sandbox
  $p = Get-SbPaths $sb 'feature/6-pid'
  (Invoke-Wt $sb @('feature/6-pid', '-NoUp', '-Slot', '605')).Code | Out-Null

  It '-Stop ne tue pas un processus sans rapport qui a recupere le pid de l''ancien Rojo' {
    $dummy = Start-Dummy $sb
    Set-Content $p.Pid $dummy
    Invoke-Wt $sb @('feature/6-pid', '-Stop') | Out-Null
    Test-Alive $dummy | Should Be $true
  }

  It 'le demarrage relance Rojo meme si le pid enregistre appartient a un autre processus' {
    $dummy = Start-Dummy $sb
    Set-Content $p.Pid $dummy
    $r = Invoke-Wt $sb @('feature/6-pid')
    $r.Output | Should Match 'OK \(200\)'
    Get-SbRojoPid $sb 'feature/6-pid' | Should Not Be $dummy
  }

  Remove-Sandbox $sb
}

Describe 'fad-worktree.ps1 : verrou Studio' {
  $sb = New-Sandbox
  Set-FakeT3 $sb -Sessions @{ 'S-a' = 'T-a'; 'S-b' = 'T-b' } -Threads @{ 'T-a' = 'active'; 'T-b' = 'active' }
  $a = 'feature/7-studio-a'
  $b = 'feature/7-studio-b'
  $lockFile = (Get-SbPaths $sb $a).Lock
  Invoke-Wt $sb @($a, '-Slot', '606') 'S-a' | Out-Null
  Invoke-Wt $sb @($b, '-Slot', '607') 'S-b' | Out-Null
  # Cette methode permet de lire la branche qui detient le verrou ($null s'il est libre).
  function Get-Holder { if (Test-Path $lockFile) { (Get-Content $lockFile -Raw | ConvertFrom-Json).branch } }

  It 'refuse la reservation d''une branche dont Rojo ne tourne pas' {
    Invoke-Wt $sb @('feature/7-sans-rojo', '-NoUp', '-Slot', '608') | Out-Null
    (Invoke-Wt $sb @('feature/7-sans-rojo', '-AcquireStudio')).Code | Should Not Be 0
    Get-Holder | Should BeNullOrEmpty
  }

  It 'reserve Studio pour la premiere branche et affiche le port a connecter' {
    $r = Invoke-Wt $sb @($a, '-AcquireStudio')
    $r.Code | Should Be 0
    $r.Output | Should Match 'port 35506'
    Get-Holder | Should Be $a
  }

  It 'refuse la seconde branche (code 2) tant que la premiere est active' {
    $r = Invoke-Wt $sb @($b, '-AcquireStudio')
    $r.Code | Should Be 2
    $r.Output | Should Match $a
  }

  It '-StudioStatus nomme le detenteur' {
    (Invoke-Wt $sb @('-StudioStatus')).Output | Should Match "reserve par '$a'"
  }

  It '-ReleaseStudio d''une autre branche ne libere pas le verrou' {
    Invoke-Wt $sb @($b, '-ReleaseStudio') | Out-Null
    Get-Holder | Should Be $a
  }

  It 'liberation puis reprise par la seconde branche' {
    (Invoke-Wt $sb @($a, '-ReleaseStudio')).Output | Should Match 'libere'
    Get-Holder | Should BeNullOrEmpty
    (Invoke-Wt $sb @($b, '-AcquireStudio')).Code | Should Be 0
    Get-Holder | Should Be $b
  }

  It '-WaitStudio attend la liberation du detenteur' {
    $script = Join-Path $sb.Repo 'scripts\fad-worktree.ps1'
    $out = Join-Path $sb.Root 'wait.log'
    $proc = Use-SandboxEnv $sb $null {
      Start-Process pwsh -PassThru -WindowStyle Hidden -RedirectStandardOutput $out `
        -ArgumentList '-NoProfile', '-NonInteractive', '-File', $script, $a, '-AcquireStudio', '-WaitStudio', '1'
    }
    Start-Sleep -Seconds 3
    Invoke-Wt $sb @($b, '-ReleaseStudio') | Out-Null
    $proc.WaitForExit(40000) | Should Be $true
    $proc.ExitCode | Should Be 0
    Get-Holder | Should Be $a
  }

  It 'reprend le verrou quand le Rojo du detenteur est mort' {
    Stop-Process -Id (Get-SbRojoPid $sb $a) -Force; Start-Sleep -Milliseconds 300
    $r = Invoke-Wt $sb @($b, '-AcquireStudio')
    $r.Code | Should Be 0
    $r.Output | Should Match 'repris \(Rojo arrete\)'
    Get-Holder | Should Be $b
  }

  It 'reprend le verrou quand le pid du detenteur a ete recycle par un autre processus' {
    Invoke-Wt $sb @($a) | Out-Null
    Set-Content (Get-SbPaths $sb $b).Pid (Start-Dummy $sb)
    $r = Invoke-Wt $sb @($a, '-AcquireStudio')
    $r.Code | Should Be 0
    $r.Output | Should Match 'repris'
  }

  It 'reprend le verrou quand les threads du detenteur sont termines' {
    Invoke-Wt $sb @($b) | Out-Null
    Set-FakeT3 $sb -Sessions @{ 'S-a' = 'T-a'; 'S-b' = 'T-b' } -Threads @{ 'T-a' = 'settled'; 'T-b' = 'active' }
    $r = Invoke-Wt $sb @($b, '-AcquireStudio')
    $r.Code | Should Be 0
    $r.Output | Should Match 'threads T3 termines'
  }

  It 'helper T3 en panne : le verrou d''un detenteur au Rojo vivant n''est pas repris' {
    Set-FakeT3 $sb -Fail
    (Invoke-Wt $sb @($a, '-AcquireStudio')).Code | Should Be 2
    Get-Holder | Should Be $b
  }

  It 'thread du detenteur inconnu de T3 (missing) : le verrou n''est pas repris' {
    Set-FakeT3 $sb -Sessions @{ 'S-a' = 'T-a' } -Threads @{ 'T-a' = 'active' }
    (Invoke-Wt $sb @($a, '-AcquireStudio')).Code | Should Be 2
    Get-Holder | Should Be $b
  }

  It 'reprend le verrou quand le worktree du detenteur est supprime' {
    Set-FakeT3 $sb -Sessions @{ 'S-a' = 'T-a'; 'S-b' = 'T-b' } -Threads @{ 'T-a' = 'active'; 'T-b' = 'active' }
    Set-Content $lockFile '{"branch":"feature/7-disparue","port":35599,"since":"2026-01-01 00:00"}'
    $r = Invoke-Wt $sb @($a, '-AcquireStudio')
    $r.Code | Should Be 0
    $r.Output | Should Match 'worktree supprime'
  }

  It 'un verrou illisible est considere comme libre' {
    Set-Content $lockFile '{tronque'
    (Invoke-Wt $sb @($b, '-AcquireStudio')).Code | Should Be 0
    Get-Holder | Should Be $b
  }

  It 'detenteur inscrit pendant son premier tour (session seule) : reconnu fini une fois sa session resolue' {
    $c = 'feature/7-studio-c'
    Set-FakeT3 $sb -Sessions @{ 'S-b' = 'T-b' } -Threads @{ 'T-b' = 'active'; 'T-c' = 'active' }
    Invoke-Wt $sb @($c, '-Slot', '609') 'S-c' | Out-Null
    @((Get-SbOwners $sb | Where-Object { $_.branch -eq $c }).threads).Count | Should Be 0
    Invoke-Wt $sb @($b, '-ReleaseStudio') | Out-Null
    (Invoke-Wt $sb @($c, '-AcquireStudio')).Code | Should Be 0
    Set-FakeT3 $sb -Sessions @{ 'S-b' = 'T-b'; 'S-c' = 'T-c' } -Threads @{ 'T-b' = 'active'; 'T-c' = 'settled' }
    (Invoke-Wt $sb @($b, '-AcquireStudio')).Output | Should Match 'threads T3 termines'
  }

  It '-Remove refuse avec des modifications non commitees garde Rojo et le verrou' {
    $d = (Get-SbPaths $sb $b).Dir
    Set-Content (Join-Path $d 'brouillon.txt') 'x'
    (Invoke-Wt $sb @($b, '-Remove')).Code | Should Not Be 0
    Get-Holder | Should Be $b
    Test-Alive (Get-SbRojoPid $sb $b) | Should Be $true
    Remove-Item (Join-Path $d 'brouillon.txt')
  }

  It '-Stop libere le verrou de la branche' {
    Invoke-Wt $sb @($b, '-Stop') | Out-Null
    Get-Holder | Should BeNullOrEmpty
  }

  Remove-Sandbox $sb
}

Describe 'fad-worktree.ps1 : verrou Studio tenu par le checkout principal' {
  $sb = New-Sandbox
  # Port de base deplace pour le bac a sable : le checkout principal reel occupe 34900.
  $env:FAD_BASE_PORT = '35700'
  Set-FakeT3 $sb -Sessions @{ 'S-w' = 'T-w' } -Threads @{ 'T-w' = 'active' }
  $w = 'feature/14-studio-wt'
  Invoke-Wt $sb @($w, '-Slot', '1') 'S-w' | Out-Null
  $lockFile = (Get-SbPaths $sb $w).Lock

  It 'refuse la reservation par main si son Rojo ne tourne pas' {
    (Invoke-Wt $sb @('main', '-AcquireStudio')).Code | Should Not Be 0
  }

  It 'main reserve Studio sur le port de base, un worktree est alors refuse (code 2)' {
    $script:mainRojo = Start-ManualRojo $sb $sb.Repo 35700
    (Invoke-Wt $sb @('main', '-AcquireStudio')).Code | Should Be 0
    (Get-Content $lockFile -Raw | ConvertFrom-Json).port | Should Be 35700
    (Invoke-Wt $sb @($w, '-AcquireStudio')).Code | Should Be 2
  }

  It 'agent du checkout principal parti sans liberer (thread termine) : le verrou est repris malgre son Rojo' {
    Invoke-Wt $sb @($w, '-ReleaseStudio') | Out-Null
    Set-FakeT3 $sb -Sessions @{ 'S-w' = 'T-w'; 'S-m' = 'T-m' } -Threads @{ 'T-w' = 'active'; 'T-m' = 'active' }
    (Invoke-Wt $sb @('main', '-AcquireStudio') 'S-m').Code | Should Be 0
    (Get-Content $lockFile -Raw | ConvertFrom-Json).thread | Should Be 'T-m'
    (Invoke-Wt $sb @($w, '-AcquireStudio')).Code | Should Be 2
    Set-FakeT3 $sb -Sessions @{ 'S-w' = 'T-w'; 'S-m' = 'T-m' } -Threads @{ 'T-w' = 'active'; 'T-m' = 'settled' }
    $r = Invoke-Wt $sb @($w, '-AcquireStudio')
    $r.Code | Should Be 0
    $r.Output | Should Match 'threads T3 termines'
    Invoke-Wt $sb @($w, '-ReleaseStudio') | Out-Null
    (Invoke-Wt $sb @('main', '-AcquireStudio')).Code | Should Be 0
  }

  It 'Rojo du checkout principal arrete : le verrou est repris' {
    Stop-Process -Id $script:mainRojo -Force; Start-Sleep -Milliseconds 300
    $r = Invoke-Wt $sb @($w, '-AcquireStudio')
    $r.Code | Should Be 0
    $r.Output | Should Match 'Rojo arrete'
  }

  $env:FAD_BASE_PORT = $null
  Remove-Sandbox $sb
}

Describe 'fad-worktree-cleanup.ps1 : decisions' {
  $sb = New-Sandbox
  $threads = @{ 'T-act' = 'active'; 'T-fin' = 'settled'; 'T-mrg' = 'settled'; 'T-unp' = 'archived'; 'T-clo' = 'settled'; 'T-off' = 'active' }
  $sessions = @{}; foreach ($t in $threads.Keys) { $sessions["S$($t.Substring(1))"] = $t }
  Set-FakeT3 $sb -Sessions $sessions -Threads $threads
  $slot = 610
  $pidOf = @{}
  foreach ($k in 'act', 'fin', 'mrg', 'unp', 'clo', 'off') {
    Invoke-Wt $sb @("feature/8-$k", '-Slot', "$slot") "S-$k" | Out-Null
    $slot++
    $pidOf[$k] = Get-SbRojoPid $sb "feature/8-$k"
  }
  $shaMrg = Add-SbCommit $sb 'feature/8-mrg' -Push
  $shaUnp = Add-SbCommit $sb 'feature/8-unp' -Push
  Set-Content (Join-Path (Get-SbPaths $sb 'feature/8-unp').Dir 'oubli.txt') 'pas commite'
  $shaClo = Add-SbCommit $sb 'feature/8-clo' -Push
  Set-FakeGh $sb -Prs @{
    'feature/8-mrg' = @(@{ number = 1; state = 'MERGED'; headRefOid = $shaMrg })
    'feature/8-unp' = @(@{ number = 2; state = 'MERGED'; headRefOid = $shaUnp })
    'feature/8-clo' = @(@{ number = 3; state = 'CLOSED'; headRefOid = $shaClo })
  }

  It 'helper T3 en panne : aucun Rojo n''est arrete et rien n''est supprime' {
    Set-FakeT3 $sb -Fail
    (Invoke-Cleanup $sb).Code | Should Be 0
    foreach ($k in $pidOf.Keys) { Test-Alive $pidOf[$k] | Should Be $true }
    (Get-SbPaths $sb 'feature/8-mrg').Dir | Should Exist
    Set-FakeT3 $sb -Sessions $sessions -Threads $threads
  }

  It 'gh en panne : Rojo des threads termines arrete, mais rien n''est supprime' {
    Set-FakeGh $sb -Fail
    (Invoke-Cleanup $sb).Code | Should Be 0
    Start-Sleep -Milliseconds 500
    Test-Alive $pidOf['mrg'] | Should Be $false
    (Get-SbPaths $sb 'feature/8-mrg').Dir | Should Exist
    (Get-SbPaths $sb 'feature/8-clo').Dir | Should Exist
    Set-FakeGh $sb -Prs @{
      'feature/8-mrg' = @(@{ number = 1; state = 'MERGED'; headRefOid = $shaMrg })
      'feature/8-unp' = @(@{ number = 2; state = 'MERGED'; headRefOid = $shaUnp })
      'feature/8-clo' = @(@{ number = 3; state = 'CLOSED'; headRefOid = $shaClo })
    }
  }

  It 'le nettoyage se termine sans erreur' {
    (Invoke-Cleanup $sb).Code | Should Be 0
  }

  It 'thread actif : Rojo garde' {
    Test-Alive $pidOf['act'] | Should Be $true
    Test-Alive $pidOf['off'] | Should Be $true
  }
  It 'thread termine, pas de PR : Rojo arrete, worktree garde' {
    Test-Alive $pidOf['fin'] | Should Be $false
    (Get-SbPaths $sb 'feature/8-fin').Dir | Should Exist
  }
  It 'PR mergee, tout pousse : worktree et branche locale supprimes' {
    (Get-SbPaths $sb 'feature/8-mrg').Dir | Should Not Exist
    (git -C $sb.Repo branch --list 'feature/8-mrg') | Should BeNullOrEmpty
    @(Get-SbOwners $sb | Where-Object { $_.branch -eq 'feature/8-mrg' }).Count | Should Be 0
  }
  It 'PR mergee mais modification non commitee : worktree garde et signale dans le journal' {
    (Get-SbPaths $sb 'feature/8-unp').Dir | Should Exist
    (Get-Content (Get-SbPaths $sb 'x').Log -Raw) | Should Match 'GARDE feature/8-unp'
  }
  It 'PR fermee sans merge : worktree supprime, branche locale gardee' {
    (Get-SbPaths $sb 'feature/8-clo').Dir | Should Not Exist
    (git -C $sb.Repo branch --list 'feature/8-clo') | Should Not BeNullOrEmpty
  }

  It 'thread settled qui redevient actif : rien n''est touche' {
    Set-FakeT3 $sb -Sessions $sessions -Threads @{ 'T-act' = 'active'; 'T-fin' = 'active'; 'T-unp' = 'active'; 'T-off' = 'active' }
    Invoke-Wt $sb @('feature/8-fin') | Out-Null
    $fin = Get-SbRojoPid $sb 'feature/8-fin'
    Invoke-Cleanup $sb | Out-Null
    Test-Alive $fin | Should Be $true
  }

  It 'branche sans PR : pas de faux message de panne de gh' {
    Set-FakeT3 $sb -Sessions $sessions -Threads $threads
    Remove-Item (Get-SbPaths $sb 'x').Log -ErrorAction SilentlyContinue
    Invoke-Cleanup $sb | Out-Null
    "$(Get-Content (Get-SbPaths $sb 'x').Log -Raw -ErrorAction SilentlyContinue)" | Should Not Match 'gh sans reponse'
  }

  It 'thread inconnu de T3 (missing) : Rojo garde' {
    Invoke-Wt $sb @('feature/8-perdu', '-Slot', '620', '-NoRegister') | Out-Null
    Invoke-Wt $sb @('feature/8-perdu', '-RegisterThread', 'T-perdu') | Out-Null
    $perdu = Get-SbRojoPid $sb 'feature/8-perdu'
    Invoke-Cleanup $sb | Out-Null
    Test-Alive $perdu | Should Be $true
  }

  It 'PR mergee, worktree deja supprime a la main, commits locaux non pousses : branche locale gardee' {
    $br = 'feature/8-sansdossier'
    Invoke-Wt $sb @($br, '-NoUp', '-Slot', '621', '-NoRegister') | Out-Null
    $sha = Add-SbCommit $sb $br -Push
    Add-SbCommit $sb $br 'apres-merge.txt' | Out-Null
    Invoke-Git $sb.Repo worktree remove --force (Get-SbPaths $sb $br).Dir | Out-Null
    Invoke-Wt $sb @($br, '-RegisterThread', 'T-fin') | Out-Null
    Set-FakeT3 $sb -Sessions $sessions -Threads $threads
    Set-FakeGh $sb -Prs @{ $br = @(@{ number = 9; state = 'MERGED'; headRefOid = $sha }) }
    Invoke-Cleanup $sb | Out-Null
    (git -C $sb.Repo branch --list $br) | Should Not BeNullOrEmpty
  }

  It 'nom de branche reutilise : une ancienne PR mergee ne fait pas supprimer le nouveau travail, meme pousse' {
    $br = 'feature/8-reprise'
    Invoke-Wt $sb @($br, '-NoUp', '-Slot', '622', '-NoRegister') | Out-Null
    $old = Add-SbCommit $sb $br -Push
    Add-SbCommit $sb $br 'suite.txt' -Push | Out-Null
    Invoke-Wt $sb @($br, '-RegisterThread', 'T-fin') | Out-Null
    Set-FakeT3 $sb -Sessions $sessions -Threads $threads
    Set-FakeGh $sb -Prs @{ $br = @(@{ number = 10; state = 'MERGED'; headRefOid = $old }) }
    Invoke-Cleanup $sb | Out-Null
    (Get-SbPaths $sb $br).Dir | Should Exist
    (git -C $sb.Repo branch --list $br) | Should Not BeNullOrEmpty
  }

  It 'registre illisible : le nettoyage le signale dans son journal sans planter' {
    $p = Get-SbPaths $sb 'feature/8-act'
    Set-Content $p.Owners '[{"branch": tronque'
    (Invoke-Cleanup $sb).Code | Should Be 0
    (Get-Content $p.Log -Raw) | Should Match 'owners'
  }

  Remove-Sandbox $sb
}
