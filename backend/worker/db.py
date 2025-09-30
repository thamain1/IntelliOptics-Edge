import os

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

PG_DSN = os.getenv("POSTGRES_DSN") or (
    f"postgresql+psycopg://{os.getenv('PG_USER','postgres')}:{os.getenv('PG_PASSWORD','')}"
    f"@{os.getenv('PG_HOST','localhost')}/{os.getenv('PG_DB','intellioptics')}?sslmode={os.getenv('PG_SSLMODE','require')}"
)
engine = create_engine(PG_DSN, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)

with engine.connect() as c:
    c.execute(text("SELECT 1"))
