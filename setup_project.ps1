# Setup script for TikTok Downloader
$flutterPath = "C:\Users\alexander\flutter_sdk\flutter\bin\flutter"

# Backup existing files
Write-Host "Backing up code files..."
New-Item -ItemType Directory -Force -Path "temp_backup"
Copy-Item -Path "lib" -Destination "temp_backup/lib" -Recurse -Force
Copy-Item -Path "pubspec.yaml" -Destination "temp_backup/pubspec.yaml" -Force

# 1. Run flutter create
Write-Host "Running flutter create..."
& $flutterPath create . --project-name tiktok_downloader --platforms=android,ios --force

# Restore files
Write-Host "Restoring code files..."
Copy-Item -Path "temp_backup/lib/*" -Destination "lib" -Recurse -Force
Copy-Item -Path "temp_backup/pubspec.yaml" -Destination "pubspec.yaml" -Force
Remove-Item -Path "temp_backup" -Recurse -Force

# 2. Add dependencies
Write-Host "Fetching dependencies..."
& $flutterPath pub get

# 3. Add Android Permissions
$manifestPath = "android/app/src/main/AndroidManifest.xml"
if (Test-Path $manifestPath) {
    Write-Host "Updating Android permissions..."
    $content = Get-Content $manifestPath -Raw
    $permissions = '    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29" />
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />'
    
    if ($content -notmatch "android.permission.INTERNET") {
        $content = $content -replace '<manifest xmlns:android="http://schemas.android.com/apk/res/android">', "<manifest xmlns:android=`"http://schemas.android.com/apk/res/android`">`n$permissions"
        $content | Set-Content $manifestPath
    }
}

# 4. Add iOS Permissions
$plistPath = "ios/Runner/Info.plist"
if (Test-Path $plistPath) {
    Write-Host "Updating iOS permissions..."
    $content = Get-Content $plistPath -Raw
    $iosPermissions = '	<key>NSPhotoLibraryAddUsageDescription</key>
	<string>This app needs access to your photo library to save TikTok videos.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>This app needs access to your photo library to save TikTok videos.</string>'
    
    if ($content -notmatch "NSPhotoLibraryAddUsageDescription") {
        $content = $content -replace '</dict>', "$iosPermissions`n</dict>"
        $content | Set-Content $plistPath
    }
}

Write-Host "Setup complete! You can now run the app using 'flutter run'."
