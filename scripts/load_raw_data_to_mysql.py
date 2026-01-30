import pandas as pd
from sqlalchemy import create_engine
from sqlalchemy.types import Text
import os
from dotenv import load_dotenv


load_dotenv()
user = os.getenv("DB_USER")
password = os.getenv("DB_PASSWORD")
host =  os.getenv("DB_HOST", "127.0.0.1")
port = int(os.getenv("DB_PORT", "3306"))
database = os.getenv("DB_NAME")




def load_raw_data_to_mysql():
    current_dir = os.path.dirname(os.path.abspath("__file__"))
    parent_dir = os.path.dirname(current_dir)
    data_dir = os.path.join(parent_dir, "data")
    file_name = "sample_data.xlsx"
    data_file = os.path.join(data_dir, file_name)

    # --- 核心修改：dtype=str ---
    # 强制所有列都作为字符串读取。
    # keep_default_na=False 的作用是：Excel里的空单元格会被读成空字符串 ""，
    # 而不是 NaN。这样就是纯粹的文本，连 NULL 都不用处理。
    df = pd.read_excel(data_file, dtype=str, keep_default_na=False)

    # 2. 列名映射
    rename_map = {
        "序号": "sample_id",
        "文献来源": "reference",
        "原材料来源及纯度": "material_source_and_purity",
        "材料制备方法": "synthesis_method",
        "制备工艺": "processing_route",
        "热处理（烧结）温度/℃": "sintering_temperature",
        "热处理时间": "sintering_duration",
        "掺杂元素": "dopant_element",
        "掺杂元素离子半径（pm）": "dopant_ionic_radius",
        "掺杂元素价态": "dopant_valence",
        "掺杂比例\n（对应形成的氧化物占总氧化物的摩尔比）": "dopant_molar_fraction",
        "晶型(c/t/m/o)": "crystal_phase",
        "工作温度(℃)": "operating_temperature",
        "电导率(S/cm)": "conductivity",
    }

    df = df.rename(columns=rename_map)

    # 3. 筛选列
    columns_in_table = [
        "sample_id", "reference", "material_source_and_purity", "synthesis_method",
        "processing_route", "sintering_temperature", "sintering_duration",
        "dopant_element", "dopant_ionic_radius", "dopant_valence",
        "dopant_molar_fraction", "crystal_phase", "operating_temperature", "conductivity",
    ]
    df = df[columns_in_table]

    # 4. 建立连接
    engine = create_engine(
        f"mysql+pymysql://{user}:{password}@{host}:{port}/{database}?charset=utf8mb4"
    )

    # 5. 写入数据库
    # 这里的 dtype 参数是告诉数据库：所有列都给我建成 Text 类型（长文本），
    # 哪怕里面看起来是数字，也当作文本存。
    # 注意：如果表已经存在且包含 int/float 列，追加可能会报错，建议删表重建。
    df.to_sql(
        "raw_conductivity_samples",
        con=engine,
        if_exists="replace",  # 建议用 replace 重新建表，确保数据库字段也是 Text
        index=False,
        dtype={col: Text for col in df.columns}  # 强制所有列在 MySQL 中都创建为 TEXT 类型
    )

    print("所有数据已作为【纯文本】插入数据库")


if __name__ == '__main__':
    load_raw_data_to_mysql()
