{{ config(materialized='table') }}

WITH us_en AS (
    SELECT
        source__name AS source_name,
        author,
        title,
        description,
        url,
        url_to_image AS image_url,
        published_at,
        content,
        'en' AS language_code,
        _dlt_load_id,
        _dlt_id
    FROM {{ source('newsapi_raw', 'articles_us_en') }}
),

de_de AS (
    SELECT
        source__name AS source_name,
        author,
        title,
        description,
        url,
        url_to_image AS image_url,
        published_at,
        content,
        'de' AS language_code,
        _dlt_load_id,
        _dlt_id
    FROM {{ source('newsapi_raw', 'articles_de_de') }}
)

SELECT * FROM us_en
UNION ALL
SELECT * FROM de_de
