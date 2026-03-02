import os
import time
import requests
import pandas as pd
from dotenv import load_dotenv
from db import get_engine

load_dotenv()

BASE_URL = os.getenv("COINGECKO_API_URL", "https://api.coingecko.com/api/v3")

# Coins to track - extend this list anytime
COINS = [
    {"coin_id": "bitcoin",  "name": "Bitcoin",  "symbol": "BTC", "category": "Layer1"},
    {"coin_id": "ethereum", "name": "Ethereum", "symbol": "ETH", "category": "Layer1"},
]
# Market events to contextualise price movements
EVENTS = [
    {"event_date": "2022-11-11", "event_name": "FTX Collapse",          "event_type": "crash"},
    {"event_date": "2022-05-09", "event_name": "Terra Luna Collapse",    "event_type": "crash"},
    {"event_date": "2024-04-20", "event_name": "Bitcoin Halving 2024",   "event_type": "halving"},
    {"event_date": "2020-05-11", "event_name": "Bitcoin Halving 2020",   "event_type": "halving"},
    {"event_date": "2021-01-08", "event_name": "Bitcoin ATH 2021",       "event_type": "ath"},
    {"event_date": "2024-01-10", "event_name": "Bitcoin ETF Approval",   "event_type": "regulation"},
]


# ------------------------------------------------------------
# LOADERS
# ------------------------------------------------------------

def load_coins(engine):
    """Insert coin reference data."""
    df = pd.DataFrame(COINS)
    df.to_sql("coins", engine, if_exists="append", index=False, method="multi")
    print(f"  Loaded {len(df)} coins")


def load_events(engine):
    """Insert market events."""
    df = pd.DataFrame(EVENTS)
    df["event_date"] = pd.to_datetime(df["event_date"]).dt.date
    df.to_sql("market_events", engine, if_exists="append", index=False)
    print(f"  Loaded {len(df)} market events")


# ------------------------------------------------------------
# COINGECKO API CALLS
# ------------------------------------------------------------

def fetch_ohlc(coin_id: str, days: int = 365) -> pd.DataFrame:
    """Fetch OHLC price data for a coin."""
    url = f"{BASE_URL}/coins/{coin_id}/ohlc"
    params = {"vs_currency": "usd", "days": days}
    response = requests.get(url, params=params, timeout=10)
    response.raise_for_status()

    df = pd.DataFrame(
        response.json(),
        columns=["timestamp", "open_price", "high_price", "low_price", "close_price"]
    )
    df["price_date"] = pd.to_datetime(df["timestamp"], unit="ms").dt.date
    df["coin_id"] = coin_id
    return df.drop(columns=["timestamp"])


def fetch_market_chart(coin_id: str, days: int = 365) -> pd.DataFrame:
    """Fetch daily volume and market cap for a coin."""
    url = f"{BASE_URL}/coins/{coin_id}/market_chart"
    params = {"vs_currency": "usd", "days": days, "interval": "daily"}
    response = requests.get(url, params=params, timeout=10)
    response.raise_for_status()
    data = response.json()

    volumes    = pd.DataFrame(data["total_volumes"], columns=["timestamp", "volume"])
    market_cap = pd.DataFrame(data["market_caps"],   columns=["timestamp", "market_cap"])

    df = volumes.merge(market_cap, on="timestamp")
    df["price_date"] = pd.to_datetime(df["timestamp"], unit="ms").dt.date
    df["coin_id"] = coin_id
    return df.drop(columns=["timestamp"])


def load_prices(engine, days: int = 365):
    """Pull and load prices for all coins."""
    all_data = []

    for coin in COINS:
        coin_id = coin["coin_id"]
        print(f"  Fetching {coin_id}...")

        try:
            ohlc   = fetch_ohlc(coin_id, days)
            market = fetch_market_chart(coin_id, days)
            merged = ohlc.merge(market, on=["coin_id", "price_date"], how="left")
            all_data.append(merged)
        except requests.RequestException as e:
            print(f"  Warning: failed to fetch {coin_id} — {e}")

        time.sleep(15)  # respect CoinGecko free tier rate limits

    df_all = pd.concat(all_data, ignore_index=True)
    df_all = df_all.drop_duplicates(subset=["coin_id", "price_date"])

    df_all.to_sql("daily_prices", engine, if_exists="append", index=False, method="multi")
    print(f"  Loaded {len(df_all)} price records")


# ------------------------------------------------------------
# MAIN
# ------------------------------------------------------------

if __name__ == "__main__":
    engine = get_engine()

    print("\nLoading coins...")
    load_coins(engine)

    print("\nLoading market events...")
    load_events(engine)

    print(f"\nFetching price data (last 365 days)...")
    load_prices(engine, days=365)

    print("\nDone! Your database is ready for analysis.")