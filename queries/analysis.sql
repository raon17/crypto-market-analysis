-- Q1: What coins are we tracking?
SELECT coin_id, name, symbol, category
FROM coins
ORDER BY name;


-- Q2: How many days of data per coin?
SELECT
    c.name,
    COUNT(dp.price_date)    AS days_of_data,
    MIN(dp.price_date)      AS earliest_date,
    MAX(dp.price_date)      AS latest_date
FROM coins c
JOIN daily_prices dp ON c.coin_id = dp.coin_id
GROUP BY c.name
ORDER BY days_of_data DESC;


-- Q3: Latest price snapshot for each coin
SELECT
    c.name,
    c.symbol,
    dp.price_date,
    dp.close_price
FROM daily_prices dp
JOIN coins c ON dp.coin_id = c.coin_id
WHERE dp.price_date = (SELECT MAX(price_date) FROM daily_prices)
ORDER BY dp.close_price DESC;


-- Q4: Price summary - high, low, average per coin
SELECT
    c.name,
    ROUND(AVG(dp.close_price)::NUMERIC, 2) AS avg_price,
    ROUND(MAX(dp.close_price)::NUMERIC, 2) AS highest_price,
    ROUND(MIN(dp.close_price)::NUMERIC, 2) AS lowest_price
FROM daily_prices dp
JOIN coins c ON dp.coin_id = c.coin_id
GROUP BY c.name
ORDER BY avg_price DESC;


-- Q5: Best and worst single day return per coin
WITH daily_returns AS (
    SELECT
        coin_id,
        price_date,
        ROUND(((close_price - LAG(close_price) OVER (
            PARTITION BY coin_id ORDER BY price_date)
        ) / LAG(close_price) OVER (
            PARTITION BY coin_id ORDER BY price_date
        ) * 100)::NUMERIC, 2) AS daily_return_pct
    FROM daily_prices
)
SELECT
    c.name,
    MAX(dr.daily_return_pct) AS best_day_pct,
    MIN(dr.daily_return_pct) AS worst_day_pct
FROM daily_returns dr
JOIN coins c ON dr.coin_id = c.coin_id
WHERE dr.daily_return_pct IS NOT NULL
GROUP BY c.name
ORDER BY best_day_pct DESC;


-- Q6: How many days were positive vs negative per coin?
WITH daily_returns AS (
    SELECT
        coin_id,
        price_date,
        (close_price - LAG(close_price) OVER (
            PARTITION BY coin_id ORDER BY price_date)
        ) AS price_change
    FROM daily_prices
)
SELECT
    c.name,
    COUNT(CASE WHEN dr.price_change > 0 THEN 1 END) AS positive_days,
    COUNT(CASE WHEN dr.price_change < 0 THEN 1 END) AS negative_days,
    ROUND((COUNT(CASE WHEN dr.price_change > 0 THEN 1 END)::NUMERIC
        / COUNT(dr.price_change) * 100), 1)          AS positive_day_pct
FROM daily_returns dr
JOIN coins c ON dr.coin_id = c.coin_id
WHERE dr.price_change IS NOT NULL
GROUP BY c.name
ORDER BY positive_day_pct DESC;


-- Q7: How many days did each coin drop more than 5% in a single day?
WITH daily_returns AS (
    SELECT
        coin_id,
        price_date,
        ROUND(((close_price - LAG(close_price) OVER (
            PARTITION BY coin_id ORDER BY price_date)
        ) / LAG(close_price) OVER (
            PARTITION BY coin_id ORDER BY price_date
        ) * 100)::NUMERIC, 2) AS daily_return_pct
    FROM daily_prices
)
SELECT
    c.name,
    COUNT(*) AS days_dropped_5pct_or_more
FROM daily_returns dr
JOIN coins c ON dr.coin_id = c.coin_id
WHERE dr.daily_return_pct <= -5
GROUP BY c.name
ORDER BY days_dropped_5pct_or_more DESC;


-- Q8: Average monthly return per coin
SELECT
    c.name,
    TO_CHAR(DATE_TRUNC('month', dp.price_date), 'YYYY-MM') AS month,
    ROUND(AVG((dp.close_price - LAG(dp.close_price) OVER (
        PARTITION BY dp.coin_id ORDER BY dp.price_date)
    ) / LAG(dp.close_price) OVER (
        PARTITION BY dp.coin_id ORDER BY dp.price_date
    ) * 100)::NUMERIC, 2) AS avg_monthly_return_pct
FROM daily_prices dp
JOIN coins c ON dp.coin_id = c.coin_id
GROUP BY c.name, DATE_TRUNC('month', dp.price_date)
ORDER BY c.name, month;


-- Q9: Which coin is most volatile? (annualised)
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
    ROUND((STDDEV(dr.daily_return) * 100)::NUMERIC, 4)              AS daily_volatility_pct,
    ROUND((STDDEV(dr.daily_return) * SQRT(365) * 100)::NUMERIC, 2)  AS annualised_volatility_pct
FROM daily_returns dr
JOIN coins c ON dr.coin_id = c.coin_id
WHERE dr.daily_return IS NOT NULL
GROUP BY c.name
ORDER BY annualised_volatility_pct DESC;


-- Q10: Risk adjusted return (basic Sharpe ratio concept)
-- Higher = better return per unit of risk
WITH daily_returns AS (
    SELECT
        coin_id,
        (close_price - LAG(close_price) OVER (
            PARTITION BY coin_id ORDER BY price_date)
        ) / LAG(close_price) OVER (
            PARTITION BY coin_id ORDER BY price_date
        ) AS daily_return
    FROM daily_prices
)
SELECT
    c.name,
    ROUND((AVG(dr.daily_return) / NULLIF(STDDEV(dr.daily_return), 0) * SQRT(365))::NUMERIC, 4) AS sharpe_ratio
FROM daily_returns dr
JOIN coins c ON dr.coin_id = c.coin_id
WHERE dr.daily_return IS NOT NULL
GROUP BY c.name
ORDER BY sharpe_ratio DESC;


-- Q11: Maximum drawdown per coin
-- (how far did price fall from its peak?)
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


-- Q12: 7-day moving average for Bitcoin
SELECT
    price_date,
    close_price,
    ROUND(AVG(close_price) OVER (
        ORDER BY price_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    )::NUMERIC, 2) AS ma_7day,
    ROUND(AVG(close_price) OVER (
        ORDER BY price_date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    )::NUMERIC, 2) AS ma_30day
FROM daily_prices
WHERE coin_id = 'bitcoin'
ORDER BY price_date;


-- Q13: Week over week price change per coin
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


-- Q14: Bitcoin price around major market events
SELECT
    me.event_name,
    me.event_type,
    me.event_date,
    before.close_price  AS price_30d_before,
    on_day.close_price  AS price_on_event,
    after.close_price   AS price_30d_after,
    ROUND(((after.close_price - before.close_price)
        / before.close_price * 100)::NUMERIC, 2) AS pct_change_over_window
FROM market_events me
LEFT JOIN daily_prices before ON before.coin_id = 'bitcoin'
    AND before.price_date = me.event_date - INTERVAL '30 days'
LEFT JOIN daily_prices on_day ON on_day.coin_id = 'bitcoin'
    AND on_day.price_date = me.event_date
LEFT JOIN daily_prices after  ON after.coin_id  = 'bitcoin'
    AND after.price_date  = me.event_date + INTERVAL '30 days'
ORDER BY me.event_date;


-- Q15: Which market event caused the biggest single day drop?
SELECT
    me.event_name,
    me.event_date,
    on_day.close_price                                          AS price_on_event,
    day_before.close_price                                      AS price_day_before,
    ROUND(((on_day.close_price - day_before.close_price)
        / day_before.close_price * 100)::NUMERIC, 2)           AS single_day_drop_pct
FROM market_events me
LEFT JOIN daily_prices on_day    ON on_day.coin_id    = 'bitcoin'
    AND on_day.price_date    = me.event_date
LEFT JOIN daily_prices day_before ON day_before.coin_id = 'bitcoin'
    AND day_before.price_date = me.event_date - INTERVAL '1 day'
WHERE on_day.close_price IS NOT NULL
ORDER BY single_day_drop_pct;