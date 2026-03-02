"""
dashboard.py
------------
Crypto Market Dashboard
Run with: streamlit run dashboard.py
"""

import pandas as pd
import plotly.graph_objects as go
import streamlit as st
from dotenv import load_dotenv
from src.db import get_engine

load_dotenv()

# --- PAGE SETUP ---
st.set_page_config(page_title="Crypto Dashboard", page_icon="₿", layout="wide")
st.title("₿ Crypto Market Dashboard")

# --- LOAD DATA ---
@st.cache_data
def load_data():
    engine = get_engine()

    prices = pd.read_sql("""
        SELECT dp.coin_id, dp.price_date, dp.close_price,
               c.name, c.symbol
        FROM daily_prices dp
        JOIN coins c ON dp.coin_id = c.coin_id
        ORDER BY dp.price_date
    """, engine)

    events = pd.read_sql("SELECT * FROM market_events ORDER BY event_date", engine)

    prices["price_date"] = pd.to_datetime(prices["price_date"])
    events["event_date"] = pd.to_datetime(events["event_date"])
    return prices, events

prices, events = load_data()

# Calculate moving averages
prices = prices.sort_values(["coin_id", "price_date"])
prices["ma7"]  = prices.groupby("coin_id")["close_price"].transform(lambda x: x.rolling(7).mean())
prices["ma30"] = prices.groupby("coin_id")["close_price"].transform(lambda x: x.rolling(30).mean())

COLORS = {"bitcoin": "#f7931a", "ethereum": "#627eea"}

# --- SECTION 1: LATEST PRICES ---
st.subheader("Latest Prices")

col1, col2 = st.columns(2)
for i, coin_id in enumerate(["bitcoin", "ethereum"]):
    d      = prices[prices["coin_id"] == coin_id].sort_values("price_date")
    latest = d.iloc[-1]
    prev   = d.iloc[-2]
    change = ((latest["close_price"] - prev["close_price"]) / prev["close_price"]) * 100

    col = col1 if i == 0 else col2
    col.metric(
        label=f"{latest['name']} ({latest['symbol']})",
        value=f"${latest['close_price']:,.2f}",
        delta=f"{change:+.2f}% today"
    )

# --- SECTION 2: PRICE HISTORY ---
st.subheader("Price History")

fig = go.Figure()
for coin_id, color in COLORS.items():
    d = prices[prices["coin_id"] == coin_id]
    fig.add_trace(go.Scatter(
        x=d["price_date"], y=d["close_price"],
        name=d["name"].iloc[0],
        line=dict(color=color, width=2)
    ))

fig.update_layout(height=400, xaxis_title="Date", yaxis_title="Price (USD)")
st.plotly_chart(fig, use_container_width=True)

# --- SECTION 3: MOVING AVERAGES ---
st.subheader("Moving Averages")

coin_choice = st.selectbox("Select coin", ["bitcoin", "ethereum"],
                            format_func=lambda x: x.title())

d     = prices[prices["coin_id"] == coin_choice]
color = COLORS[coin_choice]

fig2 = go.Figure()
fig2.add_trace(go.Scatter(x=d["price_date"], y=d["close_price"],
    name="Price", line=dict(color=color, width=1, dash="dot"), opacity=0.5))
fig2.add_trace(go.Scatter(x=d["price_date"], y=d["ma7"],
    name="7-Day MA", line=dict(color="#00d4aa", width=2)))
fig2.add_trace(go.Scatter(x=d["price_date"], y=d["ma30"],
    name="30-Day MA", line=dict(color="#ff6b35", width=2)))

fig2.update_layout(height=400, xaxis_title="Date", yaxis_title="Price (USD)")
st.plotly_chart(fig2, use_container_width=True)

# --- SECTION 4: MARKET EVENTS ---
st.subheader("Market Events")
st.dataframe(
    events[["event_date", "event_name", "event_type"]].rename(columns={
        "event_date": "Date",
        "event_name": "Event",
        "event_type": "Type"
    }),
    use_container_width=True,
    hide_index=True
)

st.caption("Data from CoinGecko API · Built with Python, PostgreSQL & Streamlit")