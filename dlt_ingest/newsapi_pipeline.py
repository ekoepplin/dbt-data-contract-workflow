"""NewsAPI -> DuckDB via dlt.

Trimmed from the multi-locale, dual-destination version in
`dbt-bigquery-core/dlt-data-dumper/newsapi_pipeline.py`. Kept two locales
(US-en, DE-de) to stay well within the NewsAPI free tier.
"""

import argparse
import os
from datetime import datetime, timedelta
from pathlib import Path

import dlt
from dotenv import load_dotenv
from loguru import logger
from newsapi.newsapi_client import NewsApiClient

load_dotenv()

REPO_ROOT = Path(__file__).resolve().parent.parent
DUCKDB_PATH = REPO_ROOT / "newsapi_articles.duckdb"
DATASET_NAME = "newsapi_raw"

today = datetime.utcnow().date()
window_start = today - timedelta(days=2)


def _api_key() -> str:
    key = os.getenv("NEWSAPI_KEY")
    if not key:
        raise RuntimeError(
            "NEWSAPI_KEY not set. Copy .env.example to .env and add your key."
        )
    return key


@dlt.resource(table_name="articles_us_en", write_disposition="append")
def get_articles_us_en():
    logger.info("Fetching US-en articles")
    client = NewsApiClient(api_key=_api_key())
    response = client.get_everything(
        language="en",
        q="Artificial Intelligence OR AI",
        from_param=window_start.isoformat(),
        to=today.isoformat(),
        sort_by="publishedAt",
    )
    for article in response["articles"]:
        yield article


@dlt.resource(table_name="articles_de_de", write_disposition="append")
def get_articles_de_de():
    logger.info("Fetching DE-de articles")
    client = NewsApiClient(api_key=_api_key())
    response = client.get_everything(
        language="de",
        q="Künstliche Intelligenz OR KI OR AI",
        from_param=window_start.isoformat(),
        to=today.isoformat(),
        sort_by="publishedAt",
    )
    for article in response["articles"]:
        yield article


@dlt.source
def newsapi_articles():
    return get_articles_us_en(), get_articles_de_de()


def run_pipeline(full_refresh: bool = False) -> None:
    pipeline = dlt.pipeline(
        pipeline_name="newsapi_articles",
        destination=dlt.destinations.duckdb(str(DUCKDB_PATH)),
        dataset_name=DATASET_NAME,
    )
    load_info = pipeline.run(
        newsapi_articles(),
        write_disposition="replace" if full_refresh else "append",
    )
    logger.info(f"Load info: {load_info}")
    logger.success(f"Wrote to {DUCKDB_PATH} (dataset={DATASET_NAME})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--full-refresh", action="store_true")
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args()

    logger.remove()
    logger.add(sink=lambda msg: print(msg, end=""), level=args.log_level)

    run_pipeline(full_refresh=args.full_refresh)
