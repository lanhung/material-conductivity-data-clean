Tools: Python, MySQL
Configure the OpenAI key in `.env` before use.
```
# Create database and tables
mysql -h 127.0.0.1 -P 3306 -u root -p < sql/create_db_tb.sql

pip install -r requirement.txt
# Import the raw data file data_20251205.xlsx from the data directory into MySQL
python scripts/load_raw_data_to_mysql.py
# Use ChatGPT to translate the data in the material_source_and_purity column into English
python scripts/translate_column_material_source_and_purity.py
# Use ChatGPT to translate the data in the synthesis_method and processing_route columns into English
python scripts/translate_column_synthesis_method_and_processing_route.py
# Extract, clean, and transform the raw data
mysql -h 127.0.0.1 -P 3306 -u root -p < sql/etl.sql
```

The `test_clean_data.sql` file is used for data cleaning tests; its logic has been merged into `etl.sql`.
