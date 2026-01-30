import os
import json
import pandas as pd
from tenacity import retry, wait_random_exponential, stop_after_attempt
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import JsonOutputParser

# =========================
# 0. 配置与初始化
# =========================
load_dotenv()

# 数据库配置
user = os.getenv("DB_USER", "root")
password = os.getenv("DB_PASSWORD")
host = os.getenv("DB_HOST", "127.0.0.1")
port = int(os.getenv("DB_PORT", "3306"))
database = os.getenv("DB_NAME")

DB_CONNECTION_STR = f"mysql+pymysql://{user}:{password}@{host}:{port}/{database}"

# API配置 (建议从环境变量读取)
API_KEY = os.getenv("OPENAI_API_KEY")
model_name=os.getenv("MODEL_NAME")

# LLM 初始化
llm = ChatOpenAI(
    api_key=API_KEY,
    model=model_name, # 建议使用稳定版本
    temperature=0
)

# Prompt 定义
prompt = ChatPromptTemplate.from_messages([
    ("system",
     "You are a professional materials-science translator.\n"
     "Translate items to English.\n"
     "- Keep technical meaning.\n"
     "- If an item is already English, keep it unchanged.\n"
     "- Return ONLY a valid JSON array of strings, same length and same order as the input array.\n"),
    ("human", "Input JSON array:\n{items_json}")
])

chain = prompt | llm | JsonOutputParser()

# =========================
# 1. 辅助函数 (复用你的逻辑)
# =========================
def chunked(lst, size):
    for i in range(0, len(lst), size):
        yield lst[i:i+size]

def translate_unique(values, chunk_size=50, max_concurrency=5):
    """
    提取唯一值 -> 批量翻译 -> 返回字典映射
    """
    # 过滤非字符串和空值
    values = [v for v in values if isinstance(v, str) and v.strip()]
    if not values:
        return {}

    print(f"Translating {len(values)} unique terms...")

    chunks = list(chunked(values, chunk_size))
    inputs = [{"items_json": json.dumps(c, ensure_ascii=False)} for c in chunks]

    # 批量并发调用
    try:
        outputs = chain.batch(inputs, config={"max_concurrency": max_concurrency})
    except Exception as e:
        print(f"Batch translation failed: {e}")
        return {}

    translated = []
    for out in outputs:
        if isinstance(out, list):
            translated.extend(out)
        else:
            # 容错处理：如果模型偶尔没返回 List
            translated.extend(["Error"] * chunk_size)

    # 长度校验
    if len(translated) != len(values):
        print(f"Warning: Length mismatch {len(values)} vs {len(translated)}. Truncating/Padding.")
        # 简单对齐，防止报错
        min_len = min(len(values), len(translated))
        values = values[:min_len]
        translated = translated[:min_len]

    return dict(zip(values, translated))

# =========================
# 2. 主流程
# =========================
def main():
    # 1. 连接数据库
    print(f"Connecting to database: {database}...")
    engine = create_engine(DB_CONNECTION_STR)

    # 2. 从原始表读取需要翻译的字段 (id 用于后续 Update 对齐)
    # 我们需要 raw 表的原始中文，以及 id
    read_sql = """
               SELECT sample_id, synthesis_method, processing_route
               FROM raw_conductivity_samples \
               """
    print("Reading raw data...")
    df = pd.read_sql(read_sql, engine)
    print(f"Loaded {len(df)} rows.")

    # 3. 提取唯一值并翻译 (synthesis_method)
    print("\n--- Processing Synthesis Methods ---")
    sm_unique = df["synthesis_method"].dropna().unique().tolist()
    sm_map = translate_unique(sm_unique, chunk_size=50, max_concurrency=3)

    # 4. 提取唯一值并翻译 (processing_route)
    print("\n--- Processing Processing Routes ---")
    pr_unique = df["processing_route"].dropna().unique().tolist()
    pr_map = translate_unique(pr_unique, chunk_size=50, max_concurrency=3)

    # 5. 映射回 DataFrame
    # 注意：这里我们生成用于 Update 的数据
    # map 如果找不到key会变成 NaN，我们需要处理成 None 以便 SQL 识别为 NULL
    df["synthesis_method_en"] = df["synthesis_method"].map(sm_map).replace({pd.NA: None, float('nan'): None})
    df["processing_route_en"] = df["processing_route"].map(pr_map).replace({pd.NA: None, float('nan'): None})

    # 6. 准备批量更新数据
    # 构造包含参数的字典列表
    update_data = []
    for _, row in df.iterrows():
        # 只有当至少有一个字段有值时才更新
        if row["synthesis_method_en"] or row["processing_route_en"]:
            update_data.append({
                "s_en": row["synthesis_method_en"],
                "p_en": row["processing_route_en"],
                "sid": row["sample_id"]
            })

    print(f"\nPreparing to update {len(update_data)} rows in 'tmp_translate_result'...")

    # 7. 执行批量 Update
    if update_data:
        # 定义 SQL 语句 (使用绑定参数 :name)
        update_stmt = text("""
                           UPDATE tmp_translate_result
                           SET synthesis_method = :s_en,
                               processing_route = :p_en
                           WHERE sample_id = :sid
                           """)

        with engine.begin() as conn:  # begin() 自动管理事务
            # SQLAlchemy 会自动优化这种列表形式的 execute 为 executemany
            # 分批执行以防 Packet Too Large 错误 (每批 1000 条)
            batch_size = 1000
            for i in tqdm(range(0, len(update_data), batch_size), desc="Updating DB"):
                batch = update_data[i : i + batch_size]
                conn.execute(update_stmt, batch)

        print("Database update completed successfully.")
    else:
        print("No data to update.")

if __name__ == "__main__":
    from tqdm import tqdm # 进度条
    main()