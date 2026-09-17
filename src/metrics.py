"""Degerlendirme metrikleri."""

import numpy as np
import pandas as pd


def user_f1(
    df: pd.DataFrame,
    y_true_col: str = "target",
    y_pred_col: str = "prediction",
    user_col: str = "user_id",
) -> float:
    """
    Kullanici bazli ortalama F1.

    Her kullanici icin tahmin edilen urun kumesi ile gercek urun
    kumesi karsilastirilir, kullanici basina F1 hesaplanir,
    sonra kullanicilar uzerinden ortalama alinir.

    Global F1 DEGIL: is problemi "her kullaniciya dogru sepeti
    onermek", tum tahminler havuzunda iyi olmak degil.

    NOT — bos tahmin: n_true = 0 olan kullanicida F1 = 0 kalir, 1.0 DEGIL.
    Aday seti yalnizca prior'da alinmis urunlerden olustugu icin
    8.602 kullanicinin (%6,6) ulasilabilir pozitifi yok; bunlarin
    macro F1 tavani zaten 0. Bos tahmine 1.0 vermek esik
    optimizasyonunu bozar (yuksek esik bedava puan toplar) ve
    modelin 0,6986 olan tavani asmasina yol acar.

    2 * tp / (n_true + n_pred) formulu precision/recall'i ayri
    hesaplamakla ayni sonucu verir, sifira bolme riski yoktur.
    """
    t = df[y_true_col].to_numpy()
    p = df[y_pred_col].to_numpy()

    tmp = pd.DataFrame({
        user_col: df[user_col].to_numpy(),
        "tp": (t == 1) & (p == 1),
        "n_true": t == 1,
        "n_pred": p == 1,
    })
    g = tmp.groupby(user_col, sort=False)[["tp", "n_true", "n_pred"]].sum()

    denom = (g["n_true"] + g["n_pred"]).to_numpy()
    f1 = np.zeros(len(denom), dtype=float)
    nz = denom > 0
    f1[nz] = 2 * g["tp"].to_numpy()[nz] / denom[nz]
    return float(f1.mean())


def user_precision_recall(
    df: pd.DataFrame,
    y_true_col: str = "target",
    y_pred_col: str = "prediction",
    user_col: str = "user_id",
) -> tuple[float, float]:
    """
    Kullanici bazli ortalama precision ve recall.

    user_f1 ile ayni mantik: her kullanici icin ayri hesaplanir,
    sonra kullanicilar uzerinden ortalama alinir.
    Hicbir urun tahmin edilmemis kullanicida precision = 0,
    ulasilabilir pozitifi olmayan kullanicida recall = 0.
    """
    t = df[y_true_col].to_numpy()
    p = df[y_pred_col].to_numpy()

    tmp = pd.DataFrame({
        user_col: df[user_col].to_numpy(),
        "tp": (t == 1) & (p == 1),
        "n_true": t == 1,
        "n_pred": p == 1,
    })
    g = tmp.groupby(user_col, sort=False)[["tp", "n_true", "n_pred"]].sum()

    tp = g["tp"].to_numpy()
    n_true = g["n_true"].to_numpy()
    n_pred = g["n_pred"].to_numpy()

    prec = np.zeros(len(tp))
    rec = np.zeros(len(tp))
    prec[n_pred > 0] = tp[n_pred > 0] / n_pred[n_pred > 0]
    rec[n_true > 0] = tp[n_true > 0] / n_true[n_true > 0]

    return float(prec.mean()), float(rec.mean())


def global_accuracy(
    df: pd.DataFrame,
    y_true_col: str = "target",
    y_pred_col: str = "prediction",
) -> float:
    """
    Genel dogruluk.

    UYARI: Verinin ~%90'i negatif sinif. Hicbir sey tahmin etmeyen
    bir model %90 dogruluk alir ve bu tamamen anlamsizdir.
    Bu metrik yalnizca referans olarak raporlanir, karar icin
    ASLA kullanilmaz.
    """
    return float((df[y_true_col] == df[y_pred_col]).mean())


def baseline_accuracy(df: pd.DataFrame, y_true_col: str = "target") -> float:
    """Hicbir sey tahmin etmeyen modelin dogrulugu — karsilastirma icin."""
    return float((df[y_true_col] == 0).mean())


def evaluation_report(
    df: pd.DataFrame,
    y_true_col: str = "target",
    y_pred_col: str = "prediction",
    user_col: str = "user_id",
) -> dict:
    """Tum metrikleri tek sozlukte dondurur."""
    prec, rec = user_precision_recall(df, y_true_col, y_pred_col, user_col)
    return {
        "user_f1": user_f1(df, y_true_col, y_pred_col, user_col),
        "user_precision": prec,
        "user_recall": rec,
        "global_accuracy": global_accuracy(df, y_true_col, y_pred_col),
        "baseline_accuracy": baseline_accuracy(df, y_true_col),
        "n_users": df[user_col].nunique(),
        "n_rows": len(df),
        "predicted_positives": int(df[y_pred_col].sum()),
        "actual_positives": int(df[y_true_col].sum()),
    }
