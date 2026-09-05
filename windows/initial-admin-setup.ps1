if (-not ( [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544") ))
{
    Write-Output "Run this Script with regular user permissions not Admin."
    Exit
}

winget install "Microsoft.WindowsTerminal"
winget install "Git.Git"

[System.Environment]::SetEnvironmentVariable("CHROME_EXECUTABLE",'C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe','User')

$Env:Path  = 'D:\git-home\bin;'
$Env:Path += 'C:\Users\gudem\AppData\Local\Programs\Python\Python311\Scripts;'
$Env:Path += 'C:\Users\gudem\AppData\Local\Programs\Python\Python311;'
$Env:Path += 'C:\Users\gudem\AppData\Local\Programs\Python\Launcher;'
$Env:Path += 'C:\Users\gudem\AppData\Local\Microsoft\WindowsApps;'
$Env:Path += 'C:\Users\gudem\AppData\Local\Programs\Microsoft VS Code\bin;'
$Env:Path += 'C:\Users\gudem\AppData\Local\Programs\Microsoft VS Code\bin;'
$Env:Path += 'C:\Users\gudem\AppData\Roaming\npm;'
$Env:Path += 'C:\Users\gudem\AppData\Local\Programs\Ollama;'
$Env:Path += 'c:\users\gudem\.local\bin;'
$Env:Path += 'c:\users\gudem\appdata\roaming\python\python311\scripts;'

[System.Environment]::SetEnvironmentVariable("Path",$Env:Path,'User')


Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart

Restart-Computer
