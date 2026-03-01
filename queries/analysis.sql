-- ============================================================
-- Crypto Market Analysis - SQL Queries
-- ============================================================


-- ------------------------------------------------------------
-- Q1: What coins are we tracking?
-- ------------------------------------------------------------
SELECT coin_id, name, symbol, category
FROM coins
ORDER BY name;


-- ------------------------------------------------------------
-- Q2: How many days of data per coin?
-- ------------------------------------------------------------
SELECT
    c.name,
    COUNT(dp.price_date)    AS days_of_data,
    MIN(dp.price_date)      AS earliest_date,
    MAX(dp.price_date)      AS latest_date
FROM coins c
JOIN daily_prices dp ON c.coin_id = dp.coin_id
GROUP BY c.name
ORDER BY days_of_data DESC;


-- ------------------------------------------------------------
-- Q3: Latest price for each coin
-- ------------------------------------------------------------
SELECT
    c.name,
    c.symbol,
    dp.price_date,
    dp.close_price
FROM daily_prices dp
JOIN coins c ON dp.coin_id = c.coin_id
WHERE dp.price_date = (SELECT MAX(price_date) FROM daily_prices)
ORDER BY dp.close_price DESC;


-- ------------------------------------------------------------
-- Q4: Price summary - high, low, average per coin
-- ------------------------------------------------------------
SELECT
    c.name,
    ROUND(AVG(dp.close_price)::NUMERIC, 2)  AS avg_price,
    ROUND(MAX(dp.close_price)::NUMERIC, 2)  AS highest_price,
    ROUND(MIN(dp.close_price)::NUMERIC, 2)  AS lowest_price
FROM daily_prices dp
JOIN coins c ON dp.coin_id = c.coin_id
GROUP BY c.name
ORDER BY avg_price DESC;


-- ------------------------------------------------------------
-- Q5: 7-day moving average for Bitcoin
-- ------------------------------------------------------------
SELECT
    price_date,
    close_price,
    ROUND(AVG(close_price) OVER (
        ORDER BY price_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS ma_7day
FROM daily_prices
WHERE coin_id = 'bitcoin'
ORDER BY price_date;


-- ------------------------------------------------------------
-- Q6: 7-day moving average for Ethereum
-- ------------------------------------------------------------
SELECT
    price_date,
    close_price,
    ROUND(AVG(close_price) OVER (
        ORDER BY price_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS ma_7day
FROM daily_prices
WHERE coin_id = 'ethereum'
ORDER BY price_date;


-- ------------------------------------------------------------
-- Q7: Week over week price change per coin
-- ------------------------------------------------------------
SELECT
    c.name,
    dp.price_date,
    dp.close_price,
    ROUND(LAG(dp.close_price, 7) OVER (
        PARTITION BY dp.coin_id ORDER BY dp.price_date
    )::NUMERIC, 2) AS price_7days_ago,
    ROUND((
        (dp.close_price - LAG(dp.close_price, 7) OVER (
            PARTITION BY dp.coin_id ORDER BY dp.price_date)
        ) / LAG(dp.close_price, 7) OVER (
            PARTITION BY dp.coin_id ORDER BY dp.price_date
        ) * 100
    )::NUMERIC, 2) AS wow_pct_change
FROM daily_prices dp
JOIN coins c ON dp.coin_id = c.coin_id
ORDER BY dp.coin_id, dp.price_date;


-- ------------------------------------------------------------
-- Q8: Which coin is most volatile?
-- ------------------------------------------------------------
WITH daily_returns AS (
    SELECT
        coin_id,
        price_date,
        (close_price - LAG(close_price) OVER (
            PARTITION BY coin_id ORDER BY price_date)
        ) / LAG(close_price) OVER (
            PARTITION BY coin_id ORDER BY price_date
        ) AS daily_return
    FROM daily_prices
)
SELECT
    c.name,
    ROUND((STDDEV(dr.daily_return) * 100)::NUMERIC, 4)          AS daily_volatility_pct,
    ROUND((STDDEV(dr.daily_return) * SQRT(365) * 100)::NUMERIC, 2) AS annualised_volatility_pct
FROM daily_returns dr
JOIN coins c ON dr.coin_id = c.coin_id
WHERE dr.daily_return IS NOT NULL
GROUP BY c.name
ORDER BY annualised_volatility_pct DESC;


-- ------------------------------------------------------------
-- Q9: Maximum drawdown per coin
-- (how far did price fall from its peak?)
-- ------------------------------------------------------------
WITH running_max AS (
    SELECT
        coin_id,
        price_date,
        close_price,
        MAX(close_price) OVER (
            PARTITION BY coin_id
            ORDER BY price_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS peak_price
    FROM daily_prices
),
drawdowns AS (
    SELECT
        coin_id,
        price_date,
        close_price,
        peak_price,
        ROUND(((close_price - peak_price) / peak_price * 100)::NUMERIC, 2) AS drawdown_pct
    FROM running_max
)
SELECT
    c.name,
    ROUND(MIN(d.drawdown_pct)::NUMERIC, 2) AS max_drawdown_pct
FROM drawdowns d
JOIN coins c ON d.coin_id = c.coin_id
GROUP BY c.name
ORDER BY max_drawdown_pct;


-- ------------------------------------------------------------
-- Q10: Bitcoin price around major market events
-- ------------------------------------------------------------
SELECT
    me.event_name,
    me.event_type,
    me.event_date,
    before.close_price   AS price_30d_before,
    on_day.close_price   AS price_on_event,
    after.close_price    AS price_30d_after,
    ROUND(((after.close_price - before.close_price)
        / before.close_price * 100)::NUMERIC, 2) AS pct_change_over_window
FROM market_events me
LEFT JOIN daily_prices before  ON before.coin_id  = 'bitcoin'
    AND before.price_date = me.event_date - INTERVAL '30 days'
LEFT JOIN daily_prices on_day  ON on_day.coin_id  = 'bitcoin'
    AND on_day.price_date = me.event_date
LEFT JOIN daily_prices after   ON after.coin_id   = 'bitcoin'
    AND after.price_date  = me.event_date + INTERVAL '30 days'
ORDER BY me.event_date;