"""
Phase 0 — Cleaning script for DataCo Supply Chain dataset
Run this on your FULL CSV (180,520 rows x 39 cols).

Usage:
    python clean_dataco.py --input DataCoSupplyChainDataset.csv --output dataco_clean.csv
"""

import argparse
import pandas as pd
import numpy as np


def load_data(path):
    # DataCo's raw CSV is often latin-1 encoded (has Spanish region names,
    # accented characters like "Rajastán"). utf-8 will throw a
    # UnicodeDecodeError on this file, so latin-1 is the safe default.
    df = pd.read_csv(path, encoding="latin-1")
    print(f"[1] Loaded: {df.shape[0]} rows, {df.shape[1]} cols")
    return df


def inspect(df):
    print("\n[2] Inspection")
    print(df.dtypes.value_counts())
    print("\nNull counts (top 15):")
    print(df.isnull().sum().sort_values(ascending=False).head(15))
    print(f"\nExact duplicate rows: {df.duplicated().sum()}")


def drop_duplicates(df):
    before = len(df)
    df = df.drop_duplicates()
    print(f"[3] Dropped {before - len(df)} exact duplicate rows")
    return df


def fix_dtypes(df):
    # Dates: DataCo has two date columns, both string "M/D/YYYY H:MM"
    df["order date (DateOrders)"] = pd.to_datetime(
        df["order date (DateOrders)"], errors="coerce"
    )
    df["shipping date (DateOrders)"] = pd.to_datetime(
        df["shipping date (DateOrders)"], errors="coerce"
    )

    # IDs that are numeric but are really categorical labels, not quantities
    id_cols = [
        "Category Id", "Customer Id", "Department Id", "Order Customer Id",
        "Order Id", "Order Item Cardprod Id", "Order Item Id",
        "Order Zipcode", "Product Card Id", "Product Category Id",
        "Product Status", "Late_delivery_risk",
    ]
    for c in id_cols:
        if c in df.columns:
            df[c] = df[c].astype("Int64")  # nullable int, since some have NaNs

    print("[4] Fixed dtypes: dates parsed, ID columns cast to nullable Int64")
    return df


def handle_missing(df):
    # Order Zipcode: mostly empty in the raw file, not usable -> drop column
    if "Order Zipcode" in df.columns and df["Order Zipcode"].isna().mean() > 0.7:
        df = df.drop(columns=["Order Zipcode"])
        print("[5] Dropped 'Order Zipcode' (mostly missing)")

    # Product Description: empty for every row in the sample -> check, drop if empty
    if "Product Description" in df.columns and df["Product Description"].isna().mean() > 0.95:
        df = df.drop(columns=["Product Description"])
        print("[5] Dropped 'Product Description' (empty across dataset)")

    return df


def drop_sensitive_and_useless_columns(df):
    # Masked PII columns - every value is literally "XXXXXXXXX", zero information
    pii_cols = ["Customer Email", "Customer Password"]
    to_drop = [c for c in pii_cols if c in df.columns]

    # Product Image is a URL, not useful for KPI/stat analysis (keep if you want it for Power BI cards)
    # Leaving it in — comment out the line below if you want it dropped:
    # to_drop.append("Product Image")

    df = df.drop(columns=to_drop, errors="ignore")
    print(f"[6] Dropped columns: {to_drop}")
    return df


def standardize_text(df):
    # Country name inconsistency: dataset mixes English + Spanish labels
    country_map = {
        "EE. UU.": "United States",
        "Estados Unidos": "United States",
        "Puerto Rico": "Puerto Rico",
    }
    for col in ["Customer Country", "Order Country"]:
        if col in df.columns:
            df[col] = df[col].str.strip()
            df[col] = df[col].replace(country_map)

    # Trim whitespace on all object/string columns generally
    obj_cols = df.select_dtypes(include="object").columns
    for c in obj_cols:
        df[c] = df[c].str.strip()

    print("[7] Standardized country names and trimmed whitespace on text columns")
    return df


def engineer_features(df):
    # THE core bottleneck metric: how many days late/early was actual vs scheduled
    df["shipping_delay_days"] = (
        df["Days for shipping (real)"] - df["Days for shipment (scheduled)"]
    )

    # Boolean flag, easier to aggregate than the raw delay number
    df["is_late"] = df["shipping_delay_days"] > 0

    # Sanity cross-check: does Late_delivery_risk agree with is_late?
    # (Late_delivery_risk is DataCo's own flag - compare, don't blindly trust either)
    if "Late_delivery_risk" in df.columns:
        df["risk_flag_mismatch"] = (
            df["Late_delivery_risk"].astype(int) != df["is_late"].astype(int)
        )
        mismatch_rate = df["risk_flag_mismatch"].mean()
        print(f"[8] Engineered shipping_delay_days, is_late. "
              f"Mismatch vs Late_delivery_risk flag: {mismatch_rate:.1%}")

    return df


def validate(df):
    print("\n[9] Validation checks")
    print(f"Final shape: {df.shape}")
    print(f"Date range: {df['order date (DateOrders)'].min()} to "
          f"{df['order date (DateOrders)'].max()}")
    print(f"Negative Sales rows (should be 0): {(df['Sales'] < 0).sum()}")
    print(f"Order Item Quantity <= 0 (should be 0): {(df['Order Item Quantity'] <= 0).sum()}")
    neg_delay = (df["shipping_delay_days"] < -2).sum()
    print(f"Rows with shipping_delay_days < -2 (worth eyeballing): {neg_delay}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", default="dataco_clean.csv")
    args = parser.parse_args()

    df = load_data(args.input)
    inspect(df)
    df = drop_duplicates(df)
    df = fix_dtypes(df)
    df = handle_missing(df)
    df = drop_sensitive_and_useless_columns(df)
    df = standardize_text(df)
    df = engineer_features(df)
    validate(df)

    df.to_csv(args.output, index=False)
    print(f"\nSaved gold dataset to {args.output} — {df.shape[0]} rows, {df.shape[1]} cols")


if __name__ == "__main__":
    main()
