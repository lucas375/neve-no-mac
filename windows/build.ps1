param(
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64"
)
$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot
try {
    & dotnet run --project Neve.Core.Checks/Neve.Core.Checks.csproj --configuration Release
    if ($LASTEXITCODE -ne 0) { throw "Falha nos testes do núcleo." }
    & dotnet publish Neve.Windows/Neve.Windows.csproj --configuration Release --runtime $Runtime --self-contained false --output "artifacts/$Runtime"
    if ($LASTEXITCODE -ne 0) { throw "Falha na compilação Windows." }
    Write-Output "Aplicativo gerado em artifacts/$Runtime/NeveNoWindows.exe"
} finally {
    Pop-Location
}
