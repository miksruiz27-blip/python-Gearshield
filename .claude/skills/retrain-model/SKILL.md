---
name: retrain-model
description: Regenerate the GearShield training dataset and retrain/export the detection model (gearshield_baseline.joblib, gearshield_engine.onnx). Use only when the user explicitly asks to rebuild the dataset or retrain/re-export the model.
disable-model-invocation: true
---

This skill touches the large, protected `data/` / model artifacts the root CLAUDE.md says not to modify without explicit request. Only run this because the user explicitly asked to retrain/rebuild — this skill invocation IS that explicit request.

All commands run from `python GearShield/` (quote the path: `cd "python GearShield"`).

Pipeline order:

1. **Build/augment raw dataset** (only the steps the user actually asked for):
   - `python build_dataset.py` — generates synthetic AI-voice samples (edge_tts) and pulls human audio into `data/ai/` and `data/human/`.
   - `python generate_rich_dataset.py` — applies augmentation (incl. WhatsApp-style compression artifacts) to produce `data/ai_augmented/` and `data/human_augmented/`.
   - `python process_altur_dataset.py` — ingests the hackathon-provided paired `jsons/`+`wavs/` set from `data/altur_raw/`.
   - `python asvspoof_loader.py` — loads the ASVspoof2019 LA benchmark from `external_datasets/` if present (bonafide vs. spoof attack systems A01-A19). This dataset may not be fully downloaded — check `dl_watchdog.log` / `external_datasets/ASVspoof2019_LA/` size before relying on it.

2. **Extract features**: `DataSet.py` builds the ~170-220 feature acoustic dataset from the class directories above (invoked by the training script, not usually run standalone).

3. **Train baseline model**: `python MLbaseline.py` — trains a RandomForest with grouped stratified k-fold CV (grouped by source file, to avoid leakage) and writes `gearshield_baseline.joblib`.

4. **Export to ONNX**: `python export_to_onnx.py` — converts the trained sklearn pipeline (scaler + classifier) into `gearshield_engine.onnx` via skl2onnx.

5. **Sync to Flutter app**: copy the new `gearshield_engine.onnx` into `flutter_voice-master/assets/models/gearshield_engine.onnx` (the app bundles its own copy on-device) — confirm with the user before overwriting it.

Confirm with the user before running any step that downloads or deletes large data (`dl_watchdog.sh`, dataset re-extraction) — these can be multi-GB, multi-minute operations.
