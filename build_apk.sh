#!/bin/sh
set -e
flutter create --org com.sandi --project-name kasir_rumah_makan --platforms android .
flutter pub get
flutter build apk --release
echo "APK: build/app/outputs/flutter-apk/app-release.apk"
