# Cobalt backend

This project uses a self-hosted Cobalt 11 API for maximum-quality TikTok
downloads. The Flutter app reads the endpoint from `COBALT_API_URL` at build
time and defaults to `http://127.0.0.1:9000` for USB debugging.

## Local Android debugging with Podman

```bash
podman run -d --name tiktokdownload-cobalt --restart unless-stopped \
  -p 9000:9000 -e API_URL=http://127.0.0.1:9000/ \
  ghcr.io/imputnet/cobalt:11

adb reverse tcp:9000 tcp:9000
flutter run --dart-define=COBALT_API_URL=http://127.0.0.1:9000
```

## Production

Deploy `compose.yml` behind an HTTPS reverse proxy, protect the public
instance with Cobalt API keys or Turnstile, and build the app with:

```bash
flutter build apk \
  --dart-define=COBALT_API_URL=https://your-cobalt-host.example
```

