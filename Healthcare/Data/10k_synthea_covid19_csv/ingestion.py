import pandas as pd
from sqlalchemy import create_engine, text

# 1. Update the connection string with your actual local database password
db_uri = "postgresql://postgres:passwordHere@localhost:5432/postgres"
engine = create_engine(db_uri)

# 2. Test the connection first before loading data
try:
    with engine.connect() as conn:
        result = conn.execute(text("SELECT version();"))
        print(f"Connection Successful! Database Version: {result.fetchone()[0]}")
except Exception as e:
    print(f"Connection failed. Error: {e}")

# 3. If the connection works, let's load just PATIENTS as our test run
try:
    print("Reading patients.csv...")
    df_patients = pd.read_csv('FILEPATH/patients.csv', dtype=str)
    
    # Sanitize column names (lowercase and underscores)
    df_patients.columns = [col.lower().strip().replace(' ', '_') for col in df_patients.columns]
    
    # Push to a staging schema inside Postgres
    df_patients.to_sql(
        name='stg_patients',
        con=engine,
        schema='public', # Using public schema for a simple test
        if_exists='replace',
        index=False
    )
    print(f"Success! Loaded {len(df_patients)} rows into public.stg_patients.")
except Exception as e:
    print(f"Data load failed. Error: {e}")