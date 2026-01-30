工具：python、mysql  
使用前先配置.env中openai的key
```
#建库建表
mysql -h 127.0.0.1 -P 3306 -u root -p < sql/create_db_tb.sql

pip install -r requirement.txt
# 把data目录下的原始数据data_20251205.xlsx导入到MySQL中
python scripts/load_raw_data_to_mysql.py
# 使用chatgpt翻译列material_source_and_purity中的数据为英文
python scripts/translate_column_material_source_and_purity.py
# 使用chatgpt翻译列synthesis_method和processing_route中的数据为英文
python scripts/translate_column_synthesis_method_and_processing_route.py
# 把原始的数据进行抽取清洗转换
mysql -h 127.0.0.1 -P 3306 -u root -p < sql/etl.sql
```

test_clean_data.sql文件是用来做清洗测试的，逻辑都合并在了etl.sql中
