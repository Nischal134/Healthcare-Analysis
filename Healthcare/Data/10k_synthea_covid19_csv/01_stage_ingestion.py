import pandas as pd
from sqlalchemy import create_engine

# 1. Database Connection
db_uri = "postgresql://postgres:postgresretro@localhost:5432/postgres"
engine = create_engine(db_uri)

# 2. Expanded Target Dictionary (Adding Encounters and Procedures)
files_to_load = {
    'stg_patients': '/Users/nischal/Documents/GitHub/Healthcare Analysis/Healthcare/Data/10k_synthea_covid19_csv/patients.csv',
    'stg_encounters': '/Users/nischal/Documents/GitHub/Healthcare Analysis/Healthcare/Data/10k_synthea_covid19_csv/encounters.csv',
    'stg_procedures': '/Users/nischal/Documents/GitHub/Healthcare Analysis/Healthcare/Data/10k_synthea_covid19_csv/procedures.csv'
}

print("Initiating batch staging ingestion...")

for table_name, file_path in files_to_load.items():
    try:
        print(f"Processing raw file: {file_path}...")
        
        # Read strictly as string to prevent truncation of codes/IDs
        df = pd.read_csv(file_path, dtype=str)
        
        # Standardize column headers to lowercase and underscores
        df.columns = [col.lower().strip().replace(' ', '_').replace('-', '_') for col in df.columns]
        
        # Stream directly into the default 'public' schema
        df.to_sql(
            name=table_name,
            con=engine,
            schema='public',
            if_exists='replace',
            index=False
        )
        print(f"Successfully loaded {len(df)} rows into public.{table_name}.\n")
        
    except Exception as e:
        print(f"CRITICAL ERROR loading {file_path}: {e}\n")

print("All base transactional data landed in staging environment.")