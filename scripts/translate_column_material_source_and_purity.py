import os
import pandas as pd
from tqdm import tqdm
from sqlalchemy import create_engine
from dotenv import load_dotenv  # 导入 dotenv
from langchain_openai import ChatOpenAI
from langchain_core.prompts import PromptTemplate

# =========================
# 0. 加载配置信息
# =========================
# 加载 .env 文件
load_dotenv()

# 读取 OpenAI API Key
API_KEY = os.getenv("OPENAI_API_KEY")
if not API_KEY:
    raise ValueError("请在 .env 文件中配置 OPENAI_API_KEY")
model_name=os.getenv("MODEL_NAME")

# 读取数据库配置 (您提供的代码)
user = os.getenv("DB_USER")
password = os.getenv("DB_PASSWORD")
host = os.getenv("DB_HOST", "127.0.0.1")
port = int(os.getenv("DB_PORT", "3306"))
database = os.getenv("DB_NAME")

# 拼接 SQLAlchemy 连接字符串
# 格式: mysql+pymysql://user:password@host:port/database
DB_CONNECTION_STR = f"mysql+pymysql://{user}:{password}@{host}:{port}/{database}"

# =========================
# 1. 连接数据库 & 读取数据
# =========================
print(f"Connecting to database '{database}' at {host}...")
engine = create_engine(DB_CONNECTION_STR)

# 读取源数据
read_sql = """
           SELECT sample_id, material_source_and_purity
           FROM raw_conductivity_samples \
           """
try:
    df = pd.read_sql(read_sql, engine)
    print(f"Loaded {len(df)} rows from database.")
except Exception as e:
    print(f"Database connection failed: {e}")
    exit(1)

# =========================
# 2. 定义 Prompt (只做翻译)
# =========================
TRANSLATION_PROMPT = """You are a materials science data normalization assistant.

Your task is to rewrite raw material descriptions into ONE concise, neutral, technical English sentence.

Strict rules:
- Do NOT add or infer any information
- Preserve chemical formulas exactly as written
- Do NOT expand abbreviations (e.g., YSZ must stay YSZ)
- If purity or concentration is not explicitly stated, do not mention it
- If supplier is not stated, do not invent one
- Do NOT mention applications, performance, or properties
- Use neutral scientific tone
- Output exactly ONE sentence without quotes.

Examples:

Input: YSZ，商品化材料(Toyo Soda)，>99%
Output: Commercial YSZ powder supplied by Toyo Soda with purity higher than 99%.

Input: Sc2O3, 商品化材料(Adventech, Korea)，6.8 mol%
Output: Commercial Sc2O3 powder supplied by Adventech (Korea) with a concentration of 6.8 mol%.

Input: {input_text}
Output:"""

prompt = PromptTemplate(
    input_variables=["input_text"],
    template=TRANSLATION_PROMPT
)

# =========================
# 3. LLM Setup
# =========================
llm = ChatOpenAI(
    api_key=API_KEY,
    model=model_name, # 建议使用最新模型
    temperature=0.0
)

chain = prompt | llm

# =========================
# 4. 批量处理
# =========================
results = []

print("Starting translation...")
for index, row in tqdm(df.iterrows(), total=df.shape[0]):
    text_input = str(row['material_source_and_purity']).strip()
    sample_id = row['sample_id']

    # 结果字典：synthesis_method 和 processing_route 设为 None (NULL)
    row_result = {
        "sample_id": sample_id,
        "material_source_and_purity": "",
        "synthesis_method": None,
        "processing_route": None
    }

    # 空值检查
    if not text_input or text_input.lower() == 'nan':
        results.append(row_result)
        continue

    try:
        # 执行翻译
        response = chain.invoke({"input_text": text_input})
        translation = response.content.strip()

        row_result["material_source_and_purity"] = translation
        results.append(row_result)

    except Exception as e:
        print(f"Error processing ID {sample_id}: {e}")
        # 出错保留原文，防止中断
        row_result["material_source_and_purity"] = text_input
        results.append(row_result)

# =========================
# 5. 写入数据库
# =========================
if results:
    result_df = pd.DataFrame(results)

    # 确保列顺序
    cols = ["sample_id", "material_source_and_purity", "synthesis_method", "processing_route"]
    result_df = result_df[cols]

    print("Writing to database table 'tmp_translate_result'...")

    try:
        result_df.to_sql(
            name='tmp_translate_result',
            con=engine,
            if_exists='append',
            index=False,
            chunksize=1000 # 如果数据量大，分批写入更安全
        )
        print("Done! Check table 'tmp_translate_result'.")
    except Exception as e:
        print(f"Error writing to database: {e}")
else:
    print("No data processed.")