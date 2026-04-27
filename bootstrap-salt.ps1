# Enable TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Pin the upstream salt-bootstrap script release that successfully installed
# Salt 3007.13 in Kitchen; this is separate from the Salt package version.
# Override with -BootstrapScriptUrl <url>; all other args pass through upstream.
$scriptUrl = "https://github.com/saltstack/salt-bootstrap/releases/download/v2026.01.22/bootstrap-salt.ps1"
$upstreamArgs = [System.Collections.Generic.List[String]]::new()

for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq "-BootstrapScriptUrl") {
        if ($i + 1 -ge $args.Count) {
            Write-Host "Missing value for -BootstrapScriptUrl" -ForegroundColor Red
            exit 1
        }
        $scriptUrl = $args[$i + 1]
        $i++
    } else {
        $upstreamArgs.Add($args[$i])
    }
}

function Repair-BootstrapScript {
    param(
        [Parameter(Mandatory=$true)]
        [String]$Content
    )

    # The upstream script currently exits when any version directory name is
    # longer than 8 characters. Broadcom's Windows package listing now includes
    # pre-release directories such as 3008.0rc1, which trips that check even
    # when bootstrapping a stable version like 3007.
    $lengthCheckPattern = '(?ms)\s*\$response\.links\s*\|\s*ForEach-Object\s*\{\s*if\s*\(\s*\$_.href\.Length\s+-gt\s+8\s*\)\s*\{.*?exit 1\s*\}\s*\}'
    $patchedContent = [regex]::Replace($Content, $lengthCheckPattern, "")

    $oldVersionFilter = '$filtered = $response.Links | Where-Object -Property href -NE "../"'
    $newVersionFilter = '$filtered = $response.Links | Where-Object { $_.href -ne "../" -and $_.href.Trim("/") -match "^\d+\.\d+(\.\d+)?$" }'

    if ($patchedContent.Contains($oldVersionFilter)) {
        $patchedContent = $patchedContent.Replace($oldVersionFilter, $newVersionFilter)
    }

    if ($patchedContent -ne $Content) {
        Write-Host "Applied compatibility patch for Salt bootstrap version parsing"
    } else {
        Write-Host "Salt bootstrap version parsing patch was not applied" -ForegroundColor Yellow
    }

    return $patchedContent
}

# Download the script using Invoke-RestMethod
Write-Host "Downloading Bootstrap Script"
try {
    $scriptContent = Invoke-RestMethod -Uri $scriptUrl -MaximumRedirection 5 -ContentType "text/plain"
} catch {
    Write-Host "Error downloading script: $_" -ForegroundColor Red
    exit 1
}

# Display the script content
# Write-Host "Downloaded Script Content:"
# Write-Host $scriptContent

$scriptContent = Repair-BootstrapScript -Content $scriptContent

# Save the script to a temporary file
$tempScriptPath = [System.IO.Path]::GetTempFileName() + ".ps1"
Set-Content -Path $tempScriptPath -Value $scriptContent

Write-Host "Executing Bootstrap Script"
# Execute the downloaded script with the same parameters
$process =  Start-Process powershell -ArgumentList "-File `"$tempScriptPath`" $($upstreamArgs -join ' ')" -Verb RunAs -Wait  -PassThru

# Check the exit code and raise an error if it's not 0
if ($process.ExitCode -ne 0) {
    Write-Host "Bootstrap script failed with exit code $($process.ExitCode)" -ForegroundColor red
    exit 1
}

Write-Host "Clean up the temporary file"
# Clean up the temporary file
Remove-Item -Path $tempScriptPath

# Check For Salt Pip and Innstall Credstash
$path = "C:\Program Files\Salt Project\Salt\salt-pip.exe"
$timeout = 300  # Timeout in seconds
$interval = 5   # Interval between checks in seconds
$elapsed = 0

while (-not (Test-Path $path) -and ($elapsed -lt $timeout)) {
    Write-Host "Waiting for $path to become valid..."  -ForegroundColor Yellow
    Start-Sleep -Seconds $interval
    $elapsed += $interval
}

if (Test-Path $path) {
    Write-Host "$path is now valid."
    # Proceed with your command
    $saltPipInstall = Start-Process -FilePath $path -WorkingDirectory "C:\Program Files\Salt Project\Salt" -ArgumentList "install credstash" -NoNewWindow -Wait -PassThru
    if ($saltPipInstall.ExitCode -ne 0) {
        Write-Host "Credstash install failed with exit code $($saltPipInstall.ExitCode)" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "-------------------------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host "Credstash install succeeded" -ForegroundColor Green
        Write-Host "===============================================================================" -ForegroundColor Yellow
    }
} else {
    Write-Host "Timeout reached. $path is still not valid."  -ForegroundColor Red
    exit 1
}
exit 0
