from huggingface_hub import snapshot_download

# 将数据集仓库下载到本地的 ./REDSearcher_SFT_10K 文件夹中
local_dir = snapshot_download(
    repo_id="Zchu/REDSearcher_SFT_10K", 
    repo_type="dataset", 
    local_dir="./REDSearcher_SFT_10K"
)

print(f"数据集所有文件已成功下载至: {local_dir}")