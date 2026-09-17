"""Parquet okuma ve bellek optimizasyonu."""

import pandas as pd
import numpy as np
import pyarrow.parquet as pq


def optimize_dtypes(df: pd.DataFrame) -> pd.DataFrame:
    """int64 ve float64 kolonlari mumkun olan en kucuk tipe indirger."""
    for col in df.select_dtypes(include=["int64", "Int64"]).columns:
        df[col] = pd.to_numeric(df[col], downcast="integer")
    for col in df.select_dtypes(include=["float64", "Float64"]).columns:
        df[col] = df[col].astype("float32")
    return df


def load_training_set(
    path: str = "training_set.parquet",
    columns: list[str] | None = None,
    optimize: bool = True,
) -> pd.DataFrame:
    """Egitim setini okur. columns verilirse sadece o kolonlari yukler."""
    df = pd.read_parquet(path, columns=columns)
    if optimize:
        df = optimize_dtypes(df)
    return df


def list_columns(path: str = "training_set.parquet") -> list[str]:
    """Dosyayi acmadan kolon adlarini dondurur."""
    return pq.ParquetFile(path).schema.names


def memory_report(df: pd.DataFrame) -> str:
    """Bellek kullanimini GB olarak dondurur."""
    gb = df.memory_usage(deep=True).sum() / 1e9
    return f"{df.shape[0]:,} satir x {df.shape[1]} kolon — {gb:.2f} GB"
