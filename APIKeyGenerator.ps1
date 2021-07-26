# Function for getting a folder location, used for saving json files
Function Get-Folder($initialDirectory="", $description = "Select a folder")
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms")|Out-Null

    $foldername = New-Object System.Windows.Forms.FolderBrowserDialog
    $foldername.Description = $description
    $foldername.rootfolder = "MyComputer"
    $foldername.SelectedPath = $initialDirectory

    if($foldername.ShowDialog() -eq "OK")
    {
        $folder += $foldername.SelectedPath
    }
    return $folder
}

##########
##  Start Code
##########
Write-Host "Welcome to the API Key Generator. This will create a new API Key for the IT Glue API Forwarder." -ForegroundColor Yellow -BackgroundColor Black
Write-Host ""

# Determine if we are generating multiple keys or not
$MultipleKeys = Read-Host "Would you like to generate multiple keys? Yes or No? (N)"
if ($MultipleKeys -eq "Y" -or $MultipleKeys -eq "Yes") {
	$MultipleKeys = $true
	Write-Host "Multi-Key generation commencing. Type " -NoNewline
	Write-Host "`"exit`"" -ForegroundColor Red -NoNewline
	Write-Host " at any time to stop generating keys and show the results."
} else {
	$MultipleKeys = $false
}

$Initials = ""
$ApiKeys = @()

# Run a loop creating new keys until all have been created
while ($Initials -ne "exit") {
	Write-Host ""
	Write-Host "What are the initials / short name of the company? " -ForegroundColor Green -NoNewline
	$Initials = Read-Host

	if ($Initials -eq "exit") {
		break
	}

	Write-Host "Thank you. Creating a new API Key using the initials `"$Initials`"."
	Write-Host "Generating...  " -NoNewline
	$UUID = [guid]::NewGuid().ToString()

	$ApiKeys += [pscustomobject]@{
		Name = "APIKey_" + $Initials
		Key = $Initials + "." + $UUID
	}

	Write-Host "Key Generated!"

	if (!$MultipleKeys) {
		break
	}

	Write-Host ""
	$Continue = Read-Host "Would you like to generate another key? (Y)"
	if ($Continue -eq "N" -or $Continue -eq "No" -or $Continue -eq "exit") {
		break
	}
}

if ($MultipleKeys) {
	$KeyCount = ($ApiKeys | Measure-Object).Count
	Write-Host "Generation complete. $KeyCount keys were generated."
}

$ApiKeys = $ApiKeys | Sort-Object { $_.Name }

# Display the key(s), either directly or as JSON.
Write-Host ""
$DisplayJson = Read-Host "Would you like to display the API key(s) in JSON format? (Y)"

if ($DisplayJson -eq "N" -or $DisplayJson -eq "No") {
	$ApiKeys | Select-Object Name, Key | Out-GridView
} else {
	$LocalSettingsJson = [ordered]@{}
	$ApiKeys | ForEach-Object {
		$LocalSettingsJson.Add($_.Name, $_.Key)
	}

	$AzureSettingsJson = @()
	$ApiKeys | ForEach-Object {
		$ApiKey = [ordered]@{
			name = $_.Name
			value = $_.Key
			slotSetting = $false
		}
		$AzureSettingsJson += $ApiKey
	}

	# Lets save the JSON files as well. By default to the desktop but we'll let the user change this location.
	$DesktopPath = [Environment]::GetFolderPath("Desktop")
	$saveLoc = Get-Folder -initialDirectory $DesktopPath -description "Where would you like to save the JSON files?"
	$saveLocLocalSettings = $saveLoc + "\APIKeys-LocalSettings.txt"
	$saveLocAzureSettings = $saveLoc + "\APIKeys-AzureSettings.txt"

	Write-Host "Saving JSON files...  " -NoNewline
	$LocalSettingsJson | ConvertTo-Json | Out-File $saveLocLocalSettings
	$AzureSettingsJson | ConvertTo-Json | Out-File $saveLocAzureSettings
	Write-Host "Saved!"

	notepad $saveLocLocalSettings
	notepad $saveLocAzureSettings
}

Write-Host ""
Read-Host "Key generation complete. Press ENTER to close."