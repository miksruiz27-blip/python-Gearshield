---
name: run-dev
description: Start the GearShield Python FastAPI backend for local development, and remind how the Flutter app connects to it. Use when the user wants to run/start/launch the backend or "the app" locally.
disable-model-invocation: true
---

Start the GearShield backend for local development:

1. From the project root, run the server:
   ```
   cd "python GearShield"
   python main.py
   ```
   (equivalently: `uvicorn main:app --reload` from inside `python GearShield/`)
2. It serves on `http://127.0.0.1:8000`. Confirm it's up with `GET /health`.
3. The Flutter app (`flutter_voice-master/`) is hardcoded to call `http://127.0.0.1:8000` (see `lib/services/gearshield_service.dart`). This works for desktop/web and for an emulator/device on the same machine as the server only if using `127.0.0.1`; **Android emulator needs `10.0.2.2`** instead — that swap is not currently wired into the code, so note it if the user is testing on an Android emulator and the app can't reach the backend.
4. If the backend can't start, check `requirements.txt` deps are installed (`pip install -r requirements.txt` from `python GearShield/`) — no venv is checked in.
5. If asked to also run the Flutter app: standard `flutter run` from `flutter_voice-master/`.

Do not touch anything under `data/`, `external_datasets/`, or the `.joblib`/`.onnx` model files as part of just starting the dev server — see the root CLAUDE.md policy on those.
