-- Q1 SQL
CREATE TABLE driver_periodic_summary AS
WITH periods AS (
    SELECT driver_id, txn_tms, txn_id, txn_type, txn_amt_usd, balance_before, balance_after, related_order_id,
           DATE_TRUNC('day', txn_tms) AS day_period,
           DATE_TRUNC('month', txn_tms) AS month_period,
           DATE_TRUNC('quarter', txn_tms) AS quarter_period
    FROM driver_wallet_transaction
), period_summary AS (
    SELECT 
        p.driver_id,
        unnest(ARRAY[day_period, month_period, quarter_period]) AS time_period,
        unnest(ARRAY['day', 'month', 'quarter']) AS time_period_type,
        MIN(balance_before) AS starting_balance,
        SUM(txn_amt_usd) AS txn_amt_usd,
        MAX(balance_after) AS ending_balance,
        COUNT(CASE WHEN txn_type = 'ORDER' THEN 1 END) AS order_cnt,
        COUNT(CASE WHEN txn_type = 'CASHOUT' THEN 1 END) AS cashout_cnt,
        COUNT(CASE WHEN txn_type = 'OTHER_REWARD' THEN 1 END) AS other_txn_cnt,
        MIN(txn_id) AS first_txn_id,
        MAX(txn_id) AS last_txn_id,
        MIN(related_order_id) AS first_related_order_id,
        MAX(related_order_id) AS last_related_order_id,
        SUM(COALESCE(oi.gmv_usd, 0)) - SUM(CASE WHEN txn_type = 'ORDER' THEN txn_amt_usd ELSE 0 END) AS commission_paid_usd
    FROM periods p
    LEFT JOIN order_info oi ON p.related_order_id = oi.order_id
    GROUP BY p.driver_id, time_period, time_period_type
)
SELECT 
    time_period::DATE AS time_period,
    time_period_type,
    driver_id,
    starting_balance,
    txn_amt_usd,
    ending_balance,
    order_cnt,
    cashout_cnt,
    other_txn_cnt,
    first_txn_id,
    last_txn_id,
    commission_paid_usd,
    first_related_order_id,
    last_related_order_id
FROM period_summary
WHERE time_period IS NOT NULL
ORDER BY time_period, time_period_type, driver_id;

ALTER TABLE driver_periodic_summary ADD PRIMARY KEY (time_period_type, time_period, driver_id);


;
-- Q2 SQL
UPDATE driver_wallet_transaction
SET 
    balance_before = COALESCE((
        SELECT SUM(txn_amt_usd) 
        FROM driver_wallet_transaction prev
        WHERE prev.driver_id = driver_wallet_transaction.driver_id
        AND prev.txn_tms < driver_wallet_transaction.txn_tms
        AND prev.txn_tms >= '2024-08-01' 
        AND prev.txn_tms < '2024-09-01'
    ), 0),
    balance_after = COALESCE((
        SELECT SUM(txn_amt_usd) 
        FROM driver_wallet_transaction prev
        WHERE prev.driver_id = driver_wallet_transaction.driver_id
        AND prev.txn_tms < driver_wallet_transaction.txn_tms
        AND prev.txn_tms >= '2024-08-01' 
        AND prev.txn_tms < '2024-09-01'
    ), 0) + txn_amt_usd
WHERE 
    txn_tms >= '2024-08-01' 
    AND txn_tms < '2024-09-01'
    AND balance_before IS NULL 
    AND balance_after IS NULL;


;
-- Q3 SQL
SELECT 
    DATE_TRUNC('month', oi.order_date)::DATE AS month,
    m.market_code AS market,
    oi.item,
    COALESCE(SUM(ds.day_cnt) FILTER (WHERE ds.day_type = 'WORKING_DAY'), 0) AS total_working_days_in_month,
    COALESCE(MAX(us.active_online_user), 0) AS active_online_user,
    COALESCE(SUM(oi.gmv_usd), 0) AS total_gmv
FROM order_info oi
LEFT JOIN market m ON oi.market_id = m.market_id
LEFT JOIN day_summary ds ON DATE_TRUNC('month', ds.month) = DATE_TRUNC('month', oi.order_date) 
    AND ds.market_id = oi.market_id
LEFT JOIN user_summary us ON DATE_TRUNC('month', us.month) = DATE_TRUNC('month', oi.order_date) 
    AND us.market_id = oi.market_id
WHERE oi.order_date < CURRENT_DATE  -- Exclude future dates
GROUP BY DATE_TRUNC('month', oi.order_date), m.market_code, oi.item
ORDER BY month, market, item;


;
