"""
MLbaseline.py - Entrenamiento y evaluación del modelo optimizado para GearShield.
Entrena un clasificador de alta precisión (Random Forest optimizado)
con validación cruzada (5-Fold Stratified K-Fold) y exportación directa a ONNX.
"""

import os
import joblib
import numpy as np
from sklearn.model_selection import GroupShuffleSplit, StratifiedGroupKFold, cross_val_score
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import RandomForestClassifier
from sklearn.calibration import CalibratedClassifierCV
from sklearn.metrics import (
    classification_report, confusion_matrix, accuracy_score, roc_auc_score, f1_score, brier_score_loss
)

from DataSet import load_dataset_from_directory, create_dummy_dataset

MODEL_PATH = "gearshield_baseline.joblib"

def train_baseline_model(data_dir="data", model_save_path=MODEL_PATH):
    """
    Carga el dataset de audios, entrena el modelo de clasificación optimizado,
    ejecuta validación cruzada de 5 pliegues y guarda el modelo entrenado.
    El split y la CV se agrupan por archivo fuente (`groups`) para que ningún
    fragmento del mismo audio aparezca a la vez en train y test (evita leakage).
    """
    print("=== Iniciando Entrenamiento del Modelo Avanzado (GearShield) ===")

    # 1. Cargar el dataset completo (Humano, IA y IA Aumentada)
    X, y, groups = load_dataset_from_directory(data_dir)

    # Si el dataset está vacío, generar datos de prueba automáticamente
    if len(X) == 0:
        print("[INFO] No se encontró dataset existente. Generando datos de prueba...")
        create_dummy_dataset(data_dir, samples_per_class=25)
        X, y, groups = load_dataset_from_directory(data_dir)

    print(f"[INFO] Dataset cargado: {X.shape[0]} muestras totales, {X.shape[1]} características por muestra, {len(set(groups))} archivos fuente.")
    print(f"[INFO] Distribución de clases -> Humanos (0): {np.sum(y == 0)}, IA Sintética/Aumentada (1): {np.sum(y == 1)}")

    # 2. Dividir en conjuntos de entrenamiento y prueba (75% train / 25% test),
    #    agrupado por archivo fuente para que no haya fuga entre fragmentos del mismo audio.
    gss = GroupShuffleSplit(n_splits=1, test_size=0.25, random_state=42)
    train_idx, test_idx = next(gss.split(X, y, groups=groups))
    X_train, X_test = X[train_idx], X[test_idx]
    y_train, y_test = y[train_idx], y[test_idx]
    groups_train = groups[train_idx]

    # 3. Normalización de características
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)

    # 4. Construcción del Clasificador Optimizado
    print("[INFO] Entrenando Clasificador Random Forest Optimizado...")
    rf_params = dict(n_estimators=250, max_depth=14, random_state=42, class_weight="balanced")
    model = RandomForestClassifier(**rf_params)
    model.fit(X_train_scaled, y_train)

    # 5. Validación Cruzada Estratificada de 5 Pliegues agrupada por archivo (5-Fold Group CV)
    print("[INFO] Ejecutando Validación Cruzada Estratificada Agrupada (5-Fold Group CV)...")
    sgkf = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=42)
    cv_scores = cross_val_score(model, X_train_scaled, y_train, cv=sgkf, groups=groups_train, scoring='accuracy')
    print(f" -> Resultados 5-Fold Group CV Accuracy: {cv_scores.mean()*100:.2f}% (+/- {cv_scores.std()*100:.2f}%)")

    # 5b. Calibración de probabilidades (Platt/sigmoid) sobre el mismo 5-Fold
    # agrupado: RandomForest.predict_proba() NO está calibrado (las hojas de un
    # bosque tienden a votos extremos 0%/100%), y esa probabilidad cruda es
    # justo lo que la app muestra como "% de IA". Se recalibra vía K-Fold
    # agrupado (nunca se calibra con datos vistos en el propio ajuste) y se
    # ensamblan los 5 clasificadores calibrados resultantes.
    # Se usa 'sigmoid' (Platt) y no 'isotonic': isotonic introduce hasta ~5
    # puntos porcentuales de diferencia entre scikit-learn y el export ONNX
    # (interpolación por tramos que skl2onnx no reproduce con exactitud),
    # mientras que sigmoid es una sola función logística y coincide con
    # ONNX Runtime al nivel de error de punto flotante — verificado abajo.
    print("[INFO] Calibrando probabilidades del modelo (Platt Scaling, 5-Fold agrupado)...")
    calib_splits = list(sgkf.split(X_train_scaled, y_train, groups=groups_train))
    calibrated_model = CalibratedClassifierCV(
        estimator=RandomForestClassifier(**rf_params), method="sigmoid", cv=calib_splits
    )
    calibrated_model.fit(X_train_scaled, y_train)

    # 6. Evaluación en el Conjunto de Prueba: ANTES (crudo) vs DESPUÉS (calibrado)
    y_pred = model.predict(X_test_scaled)
    y_proba = model.predict_proba(X_test_scaled)[:, 1]
    y_pred_cal = calibrated_model.predict(X_test_scaled)
    y_proba_cal = calibrated_model.predict_proba(X_test_scaled)[:, 1]

    def _safe_auc(y_true, proba):
        try:
            return roc_auc_score(y_true, proba)
        except Exception:
            return 0.0

    acc, f1, auc = accuracy_score(y_test, y_pred), f1_score(y_test, y_pred), _safe_auc(y_test, y_proba)
    acc_c, f1_c, auc_c = accuracy_score(y_test, y_pred_cal), f1_score(y_test, y_pred_cal), _safe_auc(y_test, y_proba_cal)
    # Brier score: error cuadrático medio de la probabilidad contra la etiqueta
    # real (0 o 1). Es LA métrica estándar de calidad de calibración —
    # complementa a accuracy/F1, que no dicen nada sobre si "91% de riesgo"
    # significa de verdad ~91% de probabilidad real. Menor es mejor.
    brier = brier_score_loss(y_test, y_proba)
    brier_c = brier_score_loss(y_test, y_proba_cal)

    print("\n" + "=" * 65)
    print("  EVALUACION EN TEST SET -- ANTES DE CALIBRAR (RandomForest crudo)")
    print("=" * 65)
    print(f" Exactitud: {acc*100:.2f}% | F1: {f1*100:.2f}% | ROC-AUC: {auc:.4f} | Brier: {brier:.4f}")
    print(classification_report(y_test, y_pred, target_names=["Humano", "IA Sintética"]))
    cm = confusion_matrix(y_test, y_pred)
    print(f"   [Verdaderos Humanos: {cm[0,0]:3d} | Falsos IA:      {cm[0,1]:3d}]")
    print(f"   [Falsos Humanos:     {cm[1,0]:3d} | Verdaderos IA:  {cm[1,1]:3d}]")

    print("\n" + "=" * 65)
    print("  EVALUACION EN TEST SET -- DESPUES DE CALIBRAR (Platt/sigmoid)")
    print("=" * 65)
    print(f" Exactitud: {acc_c*100:.2f}% | F1: {f1_c*100:.2f}% | ROC-AUC: {auc_c:.4f} | Brier: {brier_c:.4f}")
    print(classification_report(y_test, y_pred_cal, target_names=["Humano", "IA Sintética"]))
    cm_c = confusion_matrix(y_test, y_pred_cal)
    print(f"   [Verdaderos Humanos: {cm_c[0,0]:3d} | Falsos IA:      {cm_c[0,1]:3d}]")
    print(f"   [Falsos Humanos:     {cm_c[1,0]:3d} | Verdaderos IA:  {cm_c[1,1]:3d}]")
    print("=" * 65 + "\n")

    # 7. Guardar el modelo CALIBRADO (el que de verdad se usa en inferencia
    #    vía ONNX) junto con el escalador. El RandomForest crudo queda solo
    #    como referencia de diagnóstico en los logs de arriba.
    pipeline_data = {
        "scaler": scaler,
        "model": calibrated_model,
        "n_features": X.shape[1]
    }
    joblib.dump(pipeline_data, model_save_path)
    print(f"[OK] Modelo optimizado guardado exitosamente en '{model_save_path}'.")

    # 8. Re-exportar automáticamente a ONNX para mantener el SDK listo
    try:
        from export_to_onnx import export_model_to_onnx
        print("[INFO] Re-exportando modelo a formato ONNX para Edge SDK...")
        export_model_to_onnx(joblib_path=model_save_path)
    except Exception as e:
        print(f"[WARN] No se pudo re-exportar a ONNX automáticamente: {e}")

    return calibrated_model, scaler

if __name__ == "__main__":
    train_baseline_model()
