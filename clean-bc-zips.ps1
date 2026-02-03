$rootPath = "applications"

# Find all zip files recursively
Get-ChildItem -Path $rootPath -Recurse -Filter *.zip | ForEach-Object {

    $zipPath = $_.FullName
    $parentFolder = $_.DirectoryName
    $extractFolder = Join-Path $parentFolder $_.BaseName

    # Create extraction folder
    New-Item -ItemType Directory -Path $extractFolder -Force | Out-Null

    # Extract zip
    Expand-Archive -Path $zipPath -DestinationPath $extractFolder -Force

    Write-Host "Extracted: $zipPath -> $extractFolder"

    ## Remove zip file
    Remove-Item $zipPath -Force
    Write-Host "Removed: $zipPath"
}
Write-Host "All inner zip files extracted and removed!"