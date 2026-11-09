# Switches the installed addon between the dev folder and the latest published release.
#   dev     -> AddOns\CSCoder_QuestIndicator is a junction to this source folder (edits are live)
#   release -> AddOns\CSCoder_QuestIndicator is a plain copy of the latest GitHub release zip
# Run through mode-dev.bat / mode-release.bat. Close the game or /reload afterwards.
param([Parameter(Mandatory)][ValidateSet("dev", "release")][string]$Mode)
$ErrorActionPreference = "Stop"

$name = "CSCoder_QuestIndicator"
$source = Split-Path -Parent $PSScriptRoot
$addons = "D:\Games\Battlenet\World of Warcraft\_forever_\Interface\AddOns"
$target = Join-Path $addons $name

function Remove-Installed {
	if (-not (Test-Path $target)) { return }
	$item = Get-Item $target -Force
	if ($item.LinkType -eq "Junction") {
		# rmdir removes only the link, never the dev files behind it.
		cmd /c rmdir "$target" | Out-Null
	} else {
		Remove-Item $target -Recurse -Force
	}
}

if ($Mode -eq "dev") {
	Remove-Installed
	New-Item -ItemType Junction -Path $target -Target $source | Out-Null
	Write-Host "DEV mode: the game now loads $source"
} else {
	$release = Invoke-RestMethod "https://api.github.com/repos/cscoder69/$name/releases/latest" -Headers @{ "User-Agent" = "switch-mode-script" }
	$asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
	if (-not $asset) { throw "No zip in release $($release.tag_name)" }
	$temp = Join-Path $env:TEMP "cqi_release_$([guid]::NewGuid().ToString('N'))"
	New-Item -ItemType Directory -Path $temp | Out-Null
	$zip = Join-Path $temp $asset.name
	Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
	Expand-Archive $zip -DestinationPath $temp
	Remove-Installed
	Move-Item (Join-Path $temp $name) $target
	Remove-Item $temp -Recurse -Force
	Write-Host "RELEASE mode: installed $($release.tag_name) ($($asset.name))"
}
