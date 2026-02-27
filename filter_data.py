import os, re, json
import pyarrow as pa
import pyarrow.parquet as pq

# ==================== CONFIG ====================
# KEEP_TOOLS: 只保留工具调用全部在此集合内的数据，system_prompt 也只保留这些工具
# 可选工具: "search", "visit", "PythonInterpreter", "google_scholar", "google_maps"
# 示例:
#   {"search", "visit"}                                          -> 8937 条
#   {"search", "visit", "PythonInterpreter"}                     -> 9764 条
#   {"search", "visit", "google_scholar"}                        -> 9069 条
#   {"search", "visit", "google_maps"}                           -> 8956 条
#   {"search", "visit", "PythonInterpreter", "google_scholar"}   -> 9956 条
#   {"search", "visit", "PythonInterpreter", "google_scholar", "google_maps"} -> 10001 条 (全部)
KEEP_TOOLS = {"search", "visit", "PythonInterpreter", "google_scholar"}
DATA_DIR = r"C:\Ring_base\RedSearcher\REDSearcher_SFT_10K\data"
OUT_DIR = r"C:\Ring_base\RedSearcher\REDSearcher_SFT_10K\data_filtered_v1"
# ================================================

os.makedirs(OUT_DIR, exist_ok=True)

TOOL_CALL_PATTERN = re.compile(
    r"<tool_call>\s*\{[^}]*\"name\"\s*:\s*\"(\w+)\"", re.DOTALL
)


def get_used_tools(messages):
    tools = set()
    for msg in messages:
        if msg["role"] != "assistant":
            continue
        for m in TOOL_CALL_PATTERN.finditer(msg["content"]):
            tools.add(m.group(1))
    return tools


TOOL_DEF_MARKER = '{"type": "function"'
TOOL_NAME_RE = re.compile(r'"name"\s*:\s*"(\w+)"')
JSON_DECODER = json.JSONDecoder()

TOOL_DEF_OVERRIDES = {
    "search": json.dumps(
        {"type": "function", "function": {"name": "search", "description": "Perform a Google web search then returns a string of the top search results.", "parameters": {"type": "object", "properties": {"query": {"type": "string", "description": "The search query."}}, "required": ["query"]}}},
        ensure_ascii=False,
    ),
    "google_scholar": json.dumps(
        {"type": "function", "function": {"name": "google_scholar", "description": "Leverage Google Scholar to retrieve relevant information from academic publications.", "parameters": {"type": "object", "properties": {"query": {"type": "string", "description": "The search query for Google Scholar."}}, "required": ["query"]}}},
        ensure_ascii=False,
    ),
}


def split_tool_chunks(tools_text):
    """Split <tools> block into (name, raw_chunk) pairs by marker positions."""
    starts = []
    pos = 0
    while True:
        idx = tools_text.find(TOOL_DEF_MARKER, pos)
        if idx == -1:
            break
        starts.append(idx)
        pos = idx + len(TOOL_DEF_MARKER)

    chunks = []
    for i, start in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(tools_text)
        chunk = tools_text[start:end].rstrip("\n")
        m = TOOL_NAME_RE.search(chunk)
        if m:
            chunks.append((m.group(1), chunk))
    return chunks


def normalize_preamble(text):
    """Align the original data preamble with the eval framework conventions."""
    text = text.replace("\u2014", " ")          # em dash → space
    text = text.replace(                        # split into two paragraphs
        "academic inquiries. For each user request",
        "academic inquiries.\n\nFor each user request",
    )
    text = text.replace("\u2019", "'")          # curly apostrophe → straight
    text = text.replace(                        # wording + bold alignment
        "you must wrap the entire final answer in **<answer></answer>** tags.",
        "you must enclose the entire final answer within <answer></answer> tags.",
    )
    return text


def rebuild_system_prompt(system_prompt, keep_tools):
    before, rest = system_prompt.split("<tools>\n", 1)
    tools_text, after = rest.split("\n</tools>", 1)

    before = normalize_preamble(before)

    kept = []
    for name, chunk in split_tool_chunks(tools_text):
        if name not in keep_tools:
            continue
        chunk = TOOL_DEF_OVERRIDES.get(name, chunk)
        kept.append(chunk)

    return before + "<tools>\n" + "\n".join(kept) + "\n</tools>" + after


def fix_tool_calls_in_content(content):
    """Re-serialize tool_call JSON with ensure_ascii=False; strip topn/source from search."""
    TAG_OPEN, TAG_CLOSE = "<tool_call>", "</tool_call>"
    parts = []
    pos = 0
    while True:
        idx = content.find(TAG_OPEN, pos)
        if idx == -1:
            parts.append(content[pos:])
            break
        end_idx = content.find(TAG_CLOSE, idx)
        if end_idx == -1:
            parts.append(content[pos:])
            break
        parts.append(content[pos:idx + len(TAG_OPEN)])
        inner = content[idx + len(TAG_OPEN):end_idx]
        try:
            obj, _ = JSON_DECODER.raw_decode(inner.lstrip())
            if obj.get("name") == "search":
                args = obj.get("arguments", {})
                args.pop("topn", None)
                args.pop("source", None)
            parts.append("\n" + json.dumps(obj, ensure_ascii=False) + "\n")
        except (json.JSONDecodeError, ValueError):
            parts.append(inner)
        parts.append(TAG_CLOSE)
        pos = end_idx + len(TAG_CLOSE)
    return "".join(parts)


def fix_messages(messages):
    """Fix tool_call JSON in assistant messages: decode unicode escapes, remove search extras."""
    fixed = []
    for msg in messages:
        if msg["role"] == "assistant" and "<tool_call>" in msg.get("content", ""):
            msg = dict(msg)
            msg["content"] = fix_tool_calls_in_content(msg["content"])
        fixed.append(msg)
    return fixed


total_kept = 0
total_filtered = 0

for fname in sorted(os.listdir(DATA_DIR)):
    if not fname.endswith(".parquet"):
        continue

    table = pq.read_table(os.path.join(DATA_DIR, fname))
    msgs_col = table.column("messages")
    sp_col = table.column("system_prompt")

    keep_indices = []
    new_system_prompts = []
    new_messages = []

    for i in range(table.num_rows):
        messages = msgs_col[i].as_py()
        used_tools = get_used_tools(messages)
        if used_tools <= KEEP_TOOLS:
            keep_indices.append(i)
            new_system_prompts.append(rebuild_system_prompt(sp_col[i].as_py(), KEEP_TOOLS))
            new_messages.append(fix_messages(messages))
        else:
            total_filtered += 1

    if keep_indices:
        filtered = table.take(keep_indices)
        sp_idx = filtered.schema.get_field_index("system_prompt")
        filtered = filtered.set_column(
            sp_idx, "system_prompt", pa.array(new_system_prompts)
        )
        msgs_idx = filtered.schema.get_field_index("messages")
        filtered = filtered.set_column(
            msgs_idx, "messages",
            pa.array(new_messages, type=filtered.schema.field("messages").type),
        )
        pq.write_table(filtered, os.path.join(OUT_DIR, fname))
        total_kept += len(keep_indices)
        print(f"[done] {fname}: kept {len(keep_indices)}/{table.num_rows}")
    else:
        print(f"[skip] {fname}: kept 0/{table.num_rows}")

    del table, msgs_col, sp_col

print(f"\nTotal: kept {total_kept}, filtered {total_filtered}")
print(f"KEEP_TOOLS = {KEEP_TOOLS}")
print(f"Output -> {OUT_DIR}")
