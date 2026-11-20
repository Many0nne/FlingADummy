<#
.SYNOPSIS
  Installe (ou met a jour) la tache planifiee Windows "Fling a Dummy worktree cleanup" qui lance fad-worktree-cleanup.ps1
  toutes les 10 minutes et a l'ouverture de session, sans fenetre (conhost --headless).
  Idempotent ; -Uninstall retire la tache. Le chemin fige est celui du script du checkout principal, meme lance depuis
  un worktree : ce script doit donc y exister (branche mergee dans main).
  -Gh : gh a figer dans la tache (defaut : le premier gh du PATH de cette session). La tache tourne sans profil
  PowerShell : un shim que seul le profil ajoute au PATH (ex. ~\bin\gh.exe, qui choisit le compte du depot) n'y serait pas.

.EXAMPLE
  .\scripts\install-cleanup-task.ps1
  .\scripts\install-cleanup-task.ps1 -Gh "$HOME\bin\gh.exe"
  .\scripts\install-cleanup-task.ps1 -Uninstall
#>
param([switch]$Uninstall, [string]$Gh)

$ErrorActionPreference = 'Stop'
$taskName = 'Fling a Dummy worktree cleanup'

if ($Uninstall) {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
  Write-Host "Tache '$taskName' retiree."
  return
}

# Toujours le script du checkout principal (avance en fast-forward a chaque passage), meme lance depuis un worktree.
$root = (Resolve-Path (Split-Path -Parent (git -C $PSScriptRoot rev-parse --path-format=absolute --git-common-dir))).Path
$script = Join-Path $root 'scripts\fad-worktree-cleanup.ps1'
if (-not (Test-Path $script)) { throw "$script absent du checkout principal : merger la branche de l'outillage dans main, puis relancer." }
# Un script de main anterieur a #35 refuserait -Gh a chaque passage (erreur de liaison) : la tache ne tournerait plus du tout.
if (-not (Get-Command $script).Parameters.ContainsKey('Gh')) { throw "$script ne connait pas -Gh : merger #35 dans main, puis relancer." }
$pwsh = (Get-Command pwsh).Source
# La tache tourne sans profil (-NoProfile), donc sans ce qu'il ajoute au PATH (ex. ~\bin\gh.exe, shim qui choisit le compte
# GitHub du depot) : le gh de cette session (ou -Gh) est fige dans la tache (#35). Le relancer apres avoir change de gh.
# -Gh accepte un chemin ou un nom de commande ; sans -Gh, premier executable gh du PATH.
$name = if ($Gh) { $Gh } else { 'gh' }
$gh = (Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $gh) { throw "gh introuvable ($name) : l'installer, charger le profil qui l'ajoute au PATH, ou passer -Gh <chemin>, puis relancer." }
# Un alias ou une fonction gh du profil (ex. enveloppe du shim) passe avant l'executable dans la session, pas dans la tache.
$first = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
if ($first -and $first.CommandType -ne 'Application') { Write-Warning "gh est un(e) $($first.CommandType) dans cette session, mais la tache utilisera l'executable $gh : passer -Gh si ce n'est pas le bon." }
# Plusieurs gh dans le PATH (shim + installation officielle) : rappeler lequel est fige, au cas ou le shim manquerait.
$others = @(Get-Command gh -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object Source | Where-Object { $_ -ne $gh })
if ($others) { Write-Warning "gh fige : $gh (autres dans le PATH : $($others -join ', ')). Passer -Gh pour en choisir un autre." }
# conhost --headless : pas de fenetre qui clignote toutes les 10 minutes.
$action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless `"$pwsh`" -NoProfile -NonInteractive -File `"$script`" -Gh `"$gh`""
$triggers = @(
  New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10)
)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
  -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Settings $settings `
  -Description 'Arrete le Rojo des worktrees Fling a Dummy dont les threads T3 sont termines, supprime ceux dont la PR est mergee ou fermee.' -Force | Out-Null
Write-Host "Tache '$taskName' installee (toutes les 10 minutes et a l'ouverture de session), gh : $gh"
