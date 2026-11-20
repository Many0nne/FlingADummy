<#
.SYNOPSIS
  Installe (ou met a jour) la tache planifiee Windows "Fling a Dummy worktree cleanup" qui lance fad-worktree-cleanup.ps1
  toutes les 10 minutes et a l'ouverture de session, sans fenetre (conhost --headless).
  Idempotent ; -Uninstall retire la tache. Le chemin fige est celui du script du checkout principal, meme lance depuis
  un worktree : ce script doit donc y exister (branche mergee dans main).

.EXAMPLE
  .\scripts\install-cleanup-task.ps1
  .\scripts\install-cleanup-task.ps1 -Uninstall
#>
param([switch]$Uninstall)

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
$pwsh = (Get-Command pwsh).Source
# La tache tourne sans profil (-NoProfile), donc sans ce qu'il ajoute au PATH (ex. ~\bin\gh.exe, shim qui choisit le compte
# GitHub du depot) : le gh de cette session est fige dans la tache (#35). Le relancer apres avoir change de gh.
$gh = (Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $gh) { throw "gh introuvable dans le PATH de cette session : l'installer (ou charger le profil qui l'ajoute), puis relancer." }
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
