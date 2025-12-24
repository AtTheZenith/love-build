# MIT License

# Copyright (c) 2025 AtTheZenith

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Script Version 1.5.0

if ($PSVersionTable.PSVersion.Major -ne 7) {
    Write-Warning "PowerShell 7 is required to run this script. Please update your PowerShell version."
    exit 1
}

# -------------------
# Configuration
# -------------------
$appName = "game"
$requireFiles = @("main.lua")
$requireFolders = @("slick", "demo")

$buildFolder = "build"
$versionsFolder = Join-Path $buildFolder "version"
$releaseFolder = Join-Path $buildFolder "release"
$loveZip = Join-Path $releaseFolder "${appName}.love"

$loveVersion = "11.5"
$setup = $false # LEAVE FALSE, the script will auto-check for necessary files.
$buildWindows = $true
$buildLinux = $true

# Windows specific files required for build
$windowsRequiredFiles = @(
    "game.ico", "license.txt", "love.dll", "love.exe", "love.ico",
    "lovec.exe", "lua51.dll", "mpg123.dll", "msvcp120.dll",
    "msvcr120.dll", "OpenAL32.dll", "SDL2.dll"
)

# OS-specific binary paths
$basePath = Join-Path $versionsFolder "$loveVersion"
$binaries = @{
    "win32" = (Join-Path $basePath "win32") -replace '\\', '/'
    "win64" = (Join-Path $basePath "win64") -replace '\\', '/'
    "linux" = (Join-Path $basePath "linux.AppImage") -replace '\\', '/' # NO 32-BIT VERSION
}

# -------------------
# Fetch Parameters
# -------------------
# b for build, s for setup, w for windows, l for linux
# foreach ($arg in $args) {
#     if ($arg -like "-*") {
#         $arg = $arg -replace '-', ''
#         $chars = $arg.ToCharArray()
#         $setup = "s" -in $chars
#         $buildWindows = ("w" -in $chars) -or ("b" -in $chars)
#         $buildLinux = ("l" -in $chars) -or ("b" -in $chars)
#     }
# }

# -------------------
# Info
# -------------------
Write-Output "Starting build for LOVE version $loveVersion."
Write-Output "Setup is $($setup ? 'enabled' : 'disabled')."
switch ("$buildWindows$buildLinux") {
    "TrueTrue"   { Write-Output "Building for Windows and Linux." }
    "TrueFalse"  { Write-Output "Building for Windows only." }
    "FalseTrue"  { Write-Output "Building for Linux only." }
    default      { Write-Output "Building for none." }
}

# -------------------
# Helper Functions
# -------------------
Add-Type -AssemblyName "System.IO.Compression.FileSystem"
function appendGameToFile($filePath, $outputFolder, $name) {
    $outPath = (Join-Path $outputFolder "$name") -replace '\\', '/'
    Write-Output "Processing $outPath."

    try {
        $outputStream = [System.IO.File]::Open($outPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)

        $fileStream = [System.IO.File]::OpenRead($filePath)
        $fileStream.CopyTo($outputStream)
        $fileStream.Dispose()

        $gameStream = [System.IO.File]::OpenRead($loveZip)
        $gameStream.CopyTo($outputStream)
        $gameStream.Dispose()

        $outputStream.Dispose()
    } catch {
        Write-Error "Failed to append files: $($_.Exception.Message)"
        return
    }

    Write-Success "$appName.love appended to $outPath."
}

function createZIPFrom($filesToInclude, $foldersToInclude, $zipFilePath) {
    $zip = [System.IO.Compression.ZipFile]::Open($zipFilePath, 'Create')
    if ($null -eq $filesToInclude) { $filesToInclude = @() }
    if ($null -eq $foldersToInclude) { $foldersToInclude = @() }

    foreach ($file in $filesToInclude) {
        if (Test-Path $file) {
            $zipEntryName = ($file -replace '\\', '/') -replace '^\./', ''
            $zipFilePath = ($zipFilePath -replace '\\', '/') -replace '^\./', ''
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file, $zipEntryName) | Out-Null
            Write-Success "Added $file to $zipFilePath."
        } else {
            Write-Warning "File not found: $file."
        }
    }

    foreach ($folder in $foldersToInclude) {
        if (Test-Path $folder) {
            Get-ChildItem -Path $folder -Recurse -File | ForEach-Object {
                $relative = [System.IO.Path]::GetRelativePath((Get-Location), $_.FullName)
                $zipEntryName = ($relative -replace '\\', '/') -replace '^\./', ''
                $zipFilePath = ($zipFilePath -replace '\\', '/') -replace '^\./', ''
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_, $zipEntryName) | Out-Null
                Write-Output "Added $zipEntryName to $zipFilePath."
            }
        } else {
            Write-Warning "Folder not found: $folder."
        }
    }
    $zip.Dispose()
}

function Write-Success {
    param([string]$Message)
    Write-Output "$($PSStyle.Foreground.Green)SUCCESS: $Message$($PSStyle.Reset)"
}

# -------------------
# Prepare Directories
# -------------------
$versionsFolder = ($versionsFolder -replace '\\','/').TrimEnd('/')
$releaseFolder  = ($releaseFolder  -replace '\\','/').TrimEnd('/')
$loveZip        = ($loveZip        -replace '\\','/').TrimEnd('/')


foreach ($folder in @($buildFolder, $versionsFolder, $releaseFolder)) {
    if (!(Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder | Out-Null
        Write-Output "Created folder: $folder."
    }
}

if (-not $setup) {
    # Check if version's folder exists, i.e. $versionsFolder + $loveVersion
    if (!(Test-Path (Join-Path $versionsFolder $loveVersion))) {
        $setup = $true
    }

    # Check Windows build integrity
    # https://github.com/love2d/love/releases/download/11.5/love-11.5-win64.zip as reference
    if ($buildWindows) {
        # 1. Check Windows folder i.e. $binaries["win$arch"]
        # 2. Check Windows files and enable setup flag if missing any files
        foreach ($arch in @("32", "64")) {
            if (!(Test-Path $binaries["win$arch"])) {
                $setup = $true
            } else {
                foreach ($file in $windowsRequiredFiles) {
                    if (!(Test-Path (Join-Path $binaries["win$arch"] $file))) {
                        $setup = $true
                        Write-Warning "Missing win$arch files, installing..."
                        break
                    }
                }
            }
        }
    }

    # Check Linux AppImage integrity
    # https://github.com/love2d/love/releases/download/11.5/love-11.5-x86_64.AppImage as reference (no 32 bit)
    if ($buildLinux) {
        if (!(Test-Path $binaries["linux"])) {
            $setup = $true
            Write-Warning "Missing Linux files, installing..."
        }
    }
}

# -------------------
# Setup
# -------------------
if ($setup) {
    Write-Output "Starting setup..."
    # Create Folders
    if (Test-Path $basePath) {
        Remove-Item -Path $basePath -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $basePath | Out-Null
    Write-Output "Created folder: $basePath."

    # Windows
    # https://github.com/love2d/love/releases/download/11.5/love-11.5-win64.zip as reference
    # 1. Download
    # 2. Extract
    # 3. Rename folder to $binaries["win$arch"]
    if ($buildWindows) {
        foreach ($arch in @("32", "64")) {
            $url = "https://github.com/love2d/love/releases/download/$loveVersion/love-$loveVersion-win$arch.zip"
            $zipPath = Join-Path $basePath "love-$loveVersion-win$arch.zip"
            $expectedPath = Join-Path $basePath "love-$loveVersion-win$arch"

            Write-Output "Downloading $url..."
            try {
                Invoke-WebRequest -Uri $url -OutFile $zipPath -ErrorAction Stop
            } catch {
                Write-Error "Failed to download $($url): $($_.Exception.Message)"
                exit 1
            }
            Write-Success "Downloaded $url to $zipPath." 

            Write-Output "Extracting $zipPath to $basePath..."
            Expand-Archive -Path $zipPath -DestinationPath $basePath -Force
            Write-Success "Extracted $zipPath to $basePath."

            Write-Output "Renaming $expectedPath to $($binaries["win$arch"])..."
            Move-Item -Path $expectedPath -Destination $binaries["win$arch"] -Force
            Write-Success "Renamed $expectedPath to $($binaries["win$arch"])."
        }
    }

    # Linux
    # https://github.com/love2d/love/releases/download/11.5/love-11.5-x86_64.AppImage as reference (no 32 bit)
    # 1. Download
    # 2. Rename file to $binaries["linux"]
    if ($buildLinux) {
        $url = "https://github.com/love2d/love/releases/download/$loveVersion/love-$loveVersion-x86_64.AppImage"
        $zipPath = Join-Path $basePath "love-$loveVersion-x86_64.AppImage"
        $expectedPath = Join-Path $basePath "love-$loveVersion-x86_64.AppImage"

        Write-Output "Downloading $url..."
        try {
            Invoke-WebRequest -Uri $url -OutFile $zipPath -ErrorAction Stop
        } catch {
            Write-Error "Failed to download $($url): $($_.Exception.Message)"
            exit 1
        }
        Write-Success "Downloaded $url to $zipPath."

        Write-Output "Renaming $expectedPath to $($binaries["linux"])..."
        Move-Item -Path $expectedPath -Destination $binaries["linux"] -Force
        Write-Success "Renamed $expectedPath to $($binaries["linux"])."
    }
}

# -------------------
# Prepare game.love
# -------------------
if (Test-Path $loveZip) { Remove-Item $loveZip }

createZIPFrom $requireFiles $requireFolders $loveZip

Write-Success "Created $appName.love file."

# -------------------
# Build Windows
# -------------------
if ($buildWindows) {
    Write-Output "Starting Windows build..."

    foreach ($arch in @("32", "64")) {
        Write-Output "Building for win$arch..."
        # Prepare release folder for Windows
        $folder = (Join-Path $releaseFolder "win$arch") -replace '\\', '/'
        if (Test-Path $folder) { Remove-Item $folder -Recurse -Force }
        New-Item -ItemType Directory -Path $folder | Out-Null
        Write-Output "Cleared previous win$arch builds."

        # Copy DLLs and support files
        Get-ChildItem $binaries["win$arch"] -Exclude "*.exe" -File -Recurse | ForEach-Object {
            Copy-Item $_.FullName -Destination $folder -Force
            Write-Output "Copied $($binaries["win$arch"])/$($_.Name) to $folder."
        }

        # Append game.love to executables
        $exeFiles = @("love.exe", "lovec.exe")
        foreach ($exe in $exeFiles) {
            $exePath = Join-Path $binaries["win$arch"] $exe
            if (Test-Path $exePath) {
                $outputName = if ($exe -eq "lovec.exe") { "$appName-debug.exe" } else { "$appName.exe" }
                appendGameToFile $exePath $folder $outputName
            } else {
                Write-Warning "$exe not found in $($binaries["win$arch"]), skipping."
            }
        }
        Write-Output "Finished win$arch build."

        # Create release ZIP
        Write-Output "Creating win$arch release ZIP..."
        $zipName = Join-Path $releaseFolder "$appName-win$arch.zip"
        if (Test-Path $zipName) { Remove-Item $zipName -Force }

        # Leave first argument empty 
        createZIPFrom $null $folder $zipName
        Write-Success "Created win$arch release ZIP: $zipName."
    }
}

# -------------------
# Build Linux
# -------------------
if ($buildLinux) {
    Write-Output "Starting Linux build..."

    # Clear previous Linux AppImage
    $finalAppImagePath = Join-Path $releaseFolder "$appName.AppImage"
    if (Test-Path $finalAppImagePath) {
        Remove-Item $finalAppImagePath -Force 
        Write-Output "Cleared previous Linux build."
    }

    $tempAppImagePath = Join-Path $releaseFolder "$appName.AppImage.tmp"
    if (Test-Path $tempAppImagePath) {
        Remove-Item $tempAppImagePath -Force
    }

    Copy-Item $binaries["linux"] -Destination $tempAppImagePath -Force

    appendGameToFile $tempAppImagePath $releaseFolder "$appName.AppImage"
    Remove-Item $tempAppImagePath -Force

    # Try to set executable bit on Linux only
    if ($IsLinux)  {
        if (Get-Command chmod -ErrorAction SilentlyContinue) {
            & chmod +x $finalAppImagePath
        }
    }

    Write-Success "Finished Linux build."
}