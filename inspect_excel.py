import pandas as pd
import os

file_path = "DailyHuddle/Revenue meeting_Daily huddle.xlsx"

print(f"--- Inspecting {file_path} ---")
try:
    xl = pd.ExcelFile(file_path)
    print("Sheet Names:", xl.sheet_names)
    
    for sheet in xl.sheet_names:
        print(f"\n--- Sheet: {sheet} (First 5 rows) ---")
        df = xl.parse(sheet, nrows=5)
        print(df.to_string())
except Exception as e:
    print(f"Error reading excel: {e}")
