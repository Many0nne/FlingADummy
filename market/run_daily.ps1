# Relevé quotidien du marché Roblox : collecte des classements puis note du jour dans le vault Obsidian.
# Lancé par la tâche planifiée « Roblox market daily » (18 h) ; journal dans market/logs/<date>.log.
param([string]$Vault = "C:\Users\tbarillon\Documents\Obsidian Vault")

Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force "logs" | Out-Null
$log = Join-Path "logs" ("{0:yyyy-MM-dd}.log" -f (Get-Date))
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { "python introuvable" | Out-File -Append $log; exit 1 }

"== collect $(Get-Date -Format s)" | Out-File -Append -Encoding utf8 $log
& $py -I collect.py *>&1 | Out-File -Append -Encoding utf8 $log
$collect = $LASTEXITCODE

"== analyze $(Get-Date -Format s)" | Out-File -Append -Encoding utf8 $log
& $py -I analyze.py --obsidian $Vault *>&1 | Out-File -Append -Encoding utf8 $log
$analyze = $LASTEXITCODE

"== fin $(Get-Date -Format s) collect=$collect analyze=$analyze" | Out-File -Append -Encoding utf8 $log
exit ([Math]::Max($collect, $analyze))
