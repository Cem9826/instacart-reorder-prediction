"""Train/validation/test ayrimi — KULLANICI BAZINDA."""

import numpy as np
import pandas as pd


def user_level_split(
    df: pd.DataFrame,
    val_fraction: float = 0.15,
    test_fraction: float = 0.15,
    seed: int = 42,
    user_col: str = "user_id",
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """
    Kullanicilari UCE ayirir; bir kullanicinin TUM satirlari
    tek bir sette olur.

    Satir bazinda bolme YAPILMAZ: ayni kullanicinin bazi urunleri
    train'de bazilari validation'da olursa model kullaniciyi
    train'den ogrenip validation'da ayni kullaniciyi tahmin eder.
    Bu yalanci yuksek skor uretir.

    NEDEN UC SET:
      train : model egitimi
      valid : erken durdurma, esik optimizasyonu, kalibrasyon
      test  : YALNIZCA son raporlama — bu sette hicbir karar alinmaz
    Tek validation setinde hem karar alip hem rapor verilirse
    skor iyimser cikar (esik ve kalibrasyon o sete uydurulmus olur).

    NOT: view dondurur, .copy() yapilmaz — 8,5M satirda bellek iki katina cikar.
    """
    users = df[user_col].unique()
    rng = np.random.default_rng(seed)
    rng.shuffle(users)

    n_val = int(len(users) * val_fraction)
    n_test = int(len(users) * test_fraction)
    val_users = set(users[:n_val])
    test_users = set(users[n_val:n_val + n_test])

    u = df[user_col]
    is_val = u.isin(val_users)
    is_test = u.isin(test_users)

    return df[~(is_val | is_test)], df[is_val], df[is_test]


def verify_split(
    train: pd.DataFrame,
    val: pd.DataFrame,
    test: pd.DataFrame,
    user_col: str = "user_id",
) -> dict:
    """Uc set arasinda kullanici sizintisi olmadigini dogrular."""
    tr = set(train[user_col].unique())
    va = set(val[user_col].unique())
    te = set(test[user_col].unique())

    return {
        "train_users": len(tr),
        "val_users": len(va),
        "test_users": len(te),
        "overlap_train_val": len(tr & va),
        "overlap_train_test": len(tr & te),
        "overlap_val_test": len(va & te),
        "train_rows": len(train),
        "val_rows": len(val),
        "test_rows": len(test),
        "train_positive_rate": train["target"].mean(),
        "val_positive_rate": val["target"].mean(),
        "test_positive_rate": test["target"].mean(),
    }
