@echo off
echo === Menyiapkan folder Android ===
call flutter create --org com.sandi --project-name kasir_rumah_makan --platforms android .
echo === Mengambil paket ===
call flutter pub get
echo === Build APK ===
call flutter build apk --release
echo.
echo Selesai. APK ada di: build\app\outputs\flutter-apk\app-release.apk
pause
