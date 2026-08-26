{{ config(materialized='table') }}

SELECT
    source_name,
    CAST(published_at AS DATE) AS article_date,
    COUNT(*) AS article_count
FROM {{ ref('stg_newsapi__articles') }}
GROUP BY 1, 2
