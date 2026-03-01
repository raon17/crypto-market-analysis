
DROP TABLE IF EXISTS market_events CASCADE;
DROP TABLE IF EXISTS daily_prices CASCADE;
DROP TABLE IF EXISTS coins CASCADE;

-- ------------------------------------------------------------
-- COINS
-- Reference table for all tracked cryptocurrencies
-- ------------------------------------------------------------
CREATE TABLE coins (
    coin_id     VARCHAR(50) PRIMARY KEY,            
    name        VARCHAR(100) NOT NULL,
    symbol      VARCHAR(10)  NOT NULL,
    category    VARCHAR(50)             -- e.g. 'Layer1', 'DeFi', 'Stablecoin'
);

-- ------------------------------------------------------------
-- DAILY PRICES
-- OHLCV + market cap per coin per day
-- ------------------------------------------------------------
CREATE TABLE daily_prices (
    price_id    SERIAL PRIMARY KEY,
    coin_id     VARCHAR(50)    NOT NULL REFERENCES coins(coin_id),
    price_date  DATE           NOT NULL,
    open_price  DECIMAL(18,8),
    close_price DECIMAL(18,8),
    high_price  DECIMAL(18,8),
    low_price   DECIMAL(18,8),
    volume      DECIMAL(24,2),
    market_cap  DECIMAL(24,2),
    UNIQUE(coin_id, price_date)         -- prevent duplicate rows
);

-- ------------------------------------------------------------
-- MARKET EVENTS
-- Key events to contextualise price movements
-- ------------------------------------------------------------
CREATE TABLE market_events (
    event_id    SERIAL PRIMARY KEY,
    event_date  DATE           NOT NULL,
    event_name  VARCHAR(200)   NOT NULL,
    event_type  VARCHAR(50)             -- 'crash', 'halving', 'regulation', 'ath'
);

-- ------------------------------------------------------------
-- INDEXES
-- Speed up common query patterns
-- ------------------------------------------------------------
CREATE INDEX idx_daily_prices_date    ON daily_prices(price_date);
CREATE INDEX idx_daily_prices_coin    ON daily_prices(coin_id);
CREATE INDEX idx_market_events_date   ON market_events(event_date);