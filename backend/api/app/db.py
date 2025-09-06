from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, declarative_base
from .config import settings

if settings.pg_dsn:
    conn_str = settings.pg_dsn
else:
    conn_str = (
        f"postgresql+psycopg://{settings.pg_user}:{settings.pg_password}"
        f"@{settings.pg_host}/{settings.pg_db}?sslmode={settings.pg_sslmode}"
    )

engine = create_engine(conn_str, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
Base = declarative_base()

with engine.connect() as c:
    c.execute(text("SELECT 1"))
