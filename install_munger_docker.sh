#!/usr/bin/env bash
set -euo pipefail

APP_NAME="munger-expense-checker"
APP_DIR="/opt/${APP_NAME}"
PORT="18501"                 # host port (avoid conflicts); container listens on 8501
BASE_PATH="/munger"          # path under your main domain reverse-proxy (e.g., https://site/munger)

# 0) Docker install (if needed)
if ! command -v docker >/dev/null 2>&1; then
  echo "[*] Installing Docker Engine..."
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

sudo mkdir -p "$APP_DIR"
sudo chown -R "$USER":"$USER" "$APP_DIR"
cd "$APP_DIR"

# 1) .env (inject your key later)
cat > .env <<EOF
OPENAI_API_KEY=
STREAMLIT_BASE_PATH=${BASE_PATH}
EOF

# 2) Dockerfile (slim, reproducible)
cat > Dockerfile <<'EOF'
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# System deps for building wheels (kept minimal)
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    build-essential \
  && rm -rf /var/lib/apt/lists/*

# App directory
WORKDIR /app

# Requirements first (better layer caching)
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copy app
COPY . /app

# Streamlit needs a writable cache dir
RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

# Expose default Streamlit port
EXPOSE 8501

# Healthcheck via Streamlit's /_stcore/health
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python - <<'PY' || exit 1
import urllib.request, os, sys
url = f"http://127.0.0.1:8501/_stcore/health"
try:
    with urllib.request.urlopen(url, timeout=3) as r:
        sys.exit(0 if r.status == 200 else 1)
except Exception:
    sys.exit(1)
PY

# Start Streamlit with baseUrlPath
CMD ["bash", "-lc", "streamlit run app.py --server.baseUrlPath=${STREAMLIT_BASE_PATH:-/} --server.headless=true --server.enableXsrfProtection=true --browser.gatherUsageStats=false"]
EOF

# 3) requirements
cat > requirements.txt <<'EOF'
streamlit>=1.37
openai>=1.40
EOF

# 4) Streamlit config (theme only; baseUrlPath set via CLI)
mkdir -p .streamlit
cat > .streamlit/config.toml <<'EOF'
[theme]
base="light"
primaryColor="#2C3E50"
textColor="#111111"
backgroundColor="#FFFFFF"
secondaryBackgroundColor="#F5F6F7"
EOF

# 5) App code (journal + single expense) --------------------------

mkdir -p prompts

cat > prompts/munger_rules.md <<'EOF'
# Munger Expense Principles (Over-60 Lens)

Core guardrails:
- Survival > brilliance. Avoid wipeouts.
- Spend less than you earn; cash is oxygen.
- Avoid debt (noose), leverage, and complex/fad bets.
- Prefer boring durability: health, maintenance, modest living.
- Ownership mindset: autonomy > status. Time > money at 60+.
- Cut envy, drama, and dumb decisions. Keep life simple and boring—on purpose.
- Humility: stay in your circle of competence.

Red flags (likely “BAD”):
- New consumer debt, margin loans, BNPL at high rates.
- Status goods with debt (luxury cars, watches, boats).
- Get-rich-quick schemes, hot tips, day-trading churn.
- High fixed costs that reduce resilience (vacation homes, oversized subscriptions).
- Over-concentration or complex products you can’t explain in one sentence.

Often “GOOD” (context-dependent):
- Paying off high-interest debt.
- Health, mobility, preventive care, essential maintenance.
- Reducing ongoing costs (insulation, durable repairs).
- Experiences that compound gratitude and relationships (modest scope).
- Simple, diversified, low-cost investing you actually understand.
EOF

cat > gpt_check.py <<'EOF'
import os, json
from typing import Dict, Any, List
from openai import OpenAI

SYSTEM_PROMPT = """You are a cautious, no-nonsense financial checker channeling Charlie Munger's late-life guidance,
with special focus on decisions for people aged 60+. You assess a single expense and return STRICT JSON.

Principles to apply:
- Survival > brilliance. Avoid wipeouts.
- Spend less than you earn; cash is oxygen.
- Avoid debt, leverage, complex/fad bets; avoid status vanity.
- Prefer boring durability: health, maintenance, modest living, reduced fixed costs.
- Ownership mindset: time > money at 60+, autonomy > appearances.
- Humility: within circle of competence; if you can't explain it, don't buy it.
- Cut envy/drama/dumb decisions.

Output JSON schema:
{
  "verdict": "GOOD" | "BORDERLINE" | "BAD",
  "risk_score": 0-100,
  "principles_triggered": [ "string", ...],
  "rationale": "short clear paragraph",
  "suggested_alternative": "one actionable, simpler, safer alternative"
}

Scoring guidance (for age >= 60):
- Debt/leverage, opacity, status-seeking, fixed-cost creep => push toward BAD and higher risk.
- Essentials, health, maintenance, cost reduction => push toward GOOD and lower risk.
- If insufficient info, lean conservative; return BORDERLINE with info needed."""

EXTRACTOR_SYSTEM = """You are an extractor that reads one or many journal entries and returns
a JSON object with an array of expense candidates, suitable for evaluation by the Munger checker.

Return STRICT JSON with this schema:
{
  "expenses": [
    {
      "age": int,
      "description": "string",
      "amount": float|null,
      "currency": "USD",
      "category": "health|housing|auto|food|utilities|travel|investment|education|leisure|other",
      "recurring": bool,
      "uses_debt": bool,
      "notes": "string"
    }
  ]
}

Extraction rules:
- Identify concrete purchases, subscriptions, financing decisions, upgrades, repairs, and 'considering buying' statements.
- If multiple dollar figures appear, match the most relevant; if unclear, use null and explain in notes.
- Infer 'recurring' for subscription/membership/payment plan.
- Infer 'uses_debt' for finance/BNPL/margin/loan/refi/0% for 12mo patterns.
- Keep descriptions short and specific.
- Do NOT invent items that are not implied by the journal."""

def _client() -> OpenAI:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY environment variable is not set.")
    return OpenAI(api_key=api_key)

def check_expense_with_gpt(expense: Dict[str, Any]) -> Dict[str, Any]:
    client = _client()
    payload = {
        "age": expense.get("age"),
        "description": expense.get("description"),
        "amount": expense.get("amount"),
        "category": expense.get("category"),
        "recurring": expense.get("recurring"),
        "uses_debt": expense.get("uses_debt"),
        "notes": expense.get("notes", "")
    }
    completion = client.chat.completions.create(
        model="gpt-4o-mini",
        temperature=0.2,
        response_format={"type": "json_object"},
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": json.dumps(payload)}
        ]
    )
    content = completion.choices[0].message.content
    try:
        parsed = json.loads(content)
    except Exception:
        parsed = {
            "verdict": "BORDERLINE",
            "risk_score": 60,
            "principles_triggered": ["uncertain_info"],
            "rationale": "Model returned non-JSON or ambiguous output; defaulting conservatively.",
            "suggested_alternative": "Clarify debt/leverage, necessity, and long-term fixed costs before proceeding."
        }
    parsed["verdict"] = str(parsed.get("verdict", "BORDERLINE")).upper()
    try:
        rs = int(parsed.get("risk_score", 50))
        rs = max(0, min(100, rs))
    except Exception:
        rs = 50
    parsed["risk_score"] = rs
    if "principles_triggered" not in parsed or not isinstance(parsed["principles_triggered"], list):
        parsed["principles_triggered"] = []
    return parsed

def extract_expenses_from_journal(age: int, entries: List[Dict[str, str]]) -> List[Dict[str, Any]]:
    client = _client()
    payload = {"age": age, "entries": entries}
    completion = client.chat.completions.create(
        model="gpt-4o-mini",
        temperature=0.0,
        response_format={"type": "json_object"},
        messages=[
            {"role": "system", "content": EXTRACTOR_SYSTEM},
            {"role": "user", "content": json.dumps(payload)}
        ]
    )
    content = completion.choices[0].message.content
    try:
        parsed = json.loads(content)
        expenses = parsed.get("expenses", [])
    except Exception:
        expenses = []

    normalized = []
    for e in expenses:
        amt = e.get("amount", None)
        try:
            amt = None if amt is None else float(amt)
        except Exception:
            amt = None
        cat = (e.get("category") or "other").lower()
        if cat not in {"health","housing","auto","food","utilities","travel","investment","education","leisure","other"}:
            cat = "other"
        normalized.append({
            "age": int(age),
            "description": (e.get("description") or "").strip(),
            "amount": amt if amt is not None else 0.0,
            "category": cat,
            "recurring": bool(e.get("recurring", False)),
            "uses_debt": bool(e.get("uses_debt", False)),
            "notes": (e.get("notes") or "").strip()
        })
    return normalized
EOF

cat > app.py <<'EOF'
import os, json, datetime as dt
import streamlit as st
from gpt_check import check_expense_with_gpt, extract_expenses_from_journal

st.set_page_config(page_title="Munger Expense Checker", page_icon="💸", layout="centered")

if "journal_entries" not in st.session_state:
    st.session_state.journal_entries = []

st.title("💸 Munger Expense Checker")
st.caption("Channeling Charlie’s late-life guidance — especially for decisions after 60.")

with st.sidebar:
    st.markdown("### Setup")
    if not os.getenv("OPENAI_API_KEY"):
        st.warning("OPENAI_API_KEY not set. Provide it via environment or Docker .env file.")
    st.markdown("- Use **Single Expense** for one-off checks.")
    st.markdown("- Use **Journal Mode** to paste daily notes; we’ll extract & score expenses.")
    st.markdown("---")
    base_path = os.getenv("STREAMLIT_BASE_PATH", "/")
    st.markdown(f"**Mounted at path:** `{base_path}`")

tabs = st.tabs(["Single Expense", "Journal Mode"])

with tabs[0]:
    st.header("1) Enter Expense")
    col1, col2 = st.columns(2)
    with col1:
        age = st.number_input("Your age", min_value=18, max_value=100, value=65, step=1)
        amount = st.number_input("Amount (USD)", min_value=0.0, value=1200.0, step=50.0, format="%.2f")
        category = st.selectbox("Category", ["health","housing","auto","food","utilities","travel","investment","education","leisure","other"])
    with col2:
        recurring = st.checkbox("Recurring monthly?", value=False)
        uses_debt = st.checkbox("Uses debt / BNPL / margin?", value=False)

    description = st.text_input("Expense description", placeholder="e.g., Finance a new luxury SUV; or install attic insulation")
    notes = st.text_area("Context/notes (optional)", placeholder="Why now? Alternatives? Fixed costs? Resale? Health/comfort?")

    payload = {
        "age": int(age),
        "amount": float(amount),
        "category": category,
        "recurring": bool(recurring),
        "uses_debt": bool(uses_debt),
        "description": description.strip(),
        "notes": notes.strip(),
    }

    st.header("2) Check with Munger’s Guardrails")
    if st.button("Run Check", key="single_check"):
        if not description.strip():
            st.error("Please enter an expense description.")
        elif not os.getenv("OPENAI_API_KEY"):
            st.error("Missing OPENAI_API_KEY environment variable.")
        else:
            with st.spinner("Thinking like Charlie..."):
                result = check_expense_with_gpt(payload)
            verdict = result.get("verdict", "BORDERLINE")
            rs = result.get("risk_score", 50)
            prin = result.get("principles_triggered", [])
            rationale = result.get("rationale", "")
            alt = result.get("suggested_alternative", "")

            color = "#2ecc71" if verdict == "GOOD" else ("#f1c40f" if verdict == "BORDERLINE" else "#e74c3c")
            st.markdown(f"### Verdict: <span style='color:{color}; font-weight:700'>{verdict}</span>", unsafe_allow_html=True)
            st.progress(rs/100.0, text=f"Risk score: {rs}/100 (higher = riskier)")
            st.markdown("**Rationale**"); st.write(rationale)
            if prin: st.markdown("**Principles triggered**"); st.write(", ".join(prin))
            st.markdown("**Suggested alternative**"); st.write(alt)
            st.markdown("---"); st.subheader("Your input"); st.json(payload)

with tabs[1]:
    st.header("Journal entries → Extract expenses → Score")
    jcol1, jcol2 = st.columns([2,1])
    with jcol1:
        j_text = st.text_area("Add a journal entry", height=180,
                              placeholder="e.g., Bought a premium gym membership for $89/month. Thinking about financing a new e-bike...")
    with jcol2:
        j_date = st.date_input("Entry date", value=dt.date.today())

    if st.button("➕ Add entry"):
        if j_text.strip():
            st.session_state.journal_entries.append({"date": str(j_date), "text": j_text.strip()})
            st.success("Added journal entry.")
        else:
            st.warning("Please paste some text before adding.")

    if st.session_state.journal_entries:
        st.markdown("#### Current entries")
        for i, e in enumerate(st.session_state.journal_entries, start=1):
            with st.expander(f"{i}. {e['date']}"):
                st.write(e["text"])

        st.markdown("---")
        st.subheader("Extract & Evaluate")
        j_age = st.number_input("Your age (for context)", min_value=18, max_value=100, value=65, step=1, key="j_age")

        if st.button("🔎 Extract expenses and evaluate"):
            if not os.getenv("OPENAI_API_KEY"):
                st.error("Missing OPENAI_API_KEY environment variable.")
            else:
                with st.spinner("Extracting expense candidates from journal..."):
                    expenses = extract_expenses_from_journal(int(j_age), st.session_state.journal_entries)

                if not expenses:
                    st.info("No clear expense candidates found. Add more details (amounts, whether financed, recurring, etc.).")
                else:
                    st.success(f"Found {len(expenses)} expense candidate(s). Evaluating…")
                    for idx, exp in enumerate(expenses, start=1):
                        with st.spinner(f"Scoring expense {idx}/{len(expenses)}"):
                            result = check_expense_with_gpt(exp)

                        st.markdown("---")
                        st.markdown(f"### 🧾 Expense {idx}")
                        st.json(exp)

                        verdict = result.get("verdict", "BORDERLINE")
                        rs = result.get("risk_score", 50)
                        prin = result.get("principles_triggered", [])
                        rationale = result.get("rationale", "")
                        alt = result.get("suggested_alternative", "")

                        color = "#2ecc71" if verdict == "GOOD" else ("#f1c40f" if verdict == "BORDERLINE" else "#e74c3c")
                        st.markdown(f"**Verdict:** <span style='color:{color}; font-weight:700'>{verdict}</span>", unsafe_allow_html=True)
                        st.progress(rs/100.0, text=f"Risk score: {rs}/100 (higher = riskier)")
                        st.markdown("**Rationale**"); st.write(rationale)
                        if prin: st.markdown("**Principles triggered**"); st.write(", ".join(prin))
                        st.markdown("**Suggested alternative**"); st.write(alt)

        if st.button("🧹 Clear all entries"):
            st.session_state.journal_entries = []
            st.info("Cleared journal entries.")

st.markdown("---")
st.caption("Educational tool, not financial advice. Consult a fiduciary for personal guidance.")
EOF

# 6) docker-compose.yml
cat > docker-compose.yml <<EOF
services:
  ${APP_NAME}:
    build: .
    image: ${APP_NAME}:latest
    container_name: ${APP_NAME}
    env_file:
      - .env
    environment:
      - STREAMLIT_BASE_PATH=\${STREAMLIT_BASE_PATH:-${BASE_PATH}}
      - OPENAI_API_KEY=\${OPENAI_API_KEY}
    ports:
      - "${PORT}:8501"
    restart: unless-stopped
EOF

echo "[*] Build & start container..."
docker compose build
docker compose up -d

echo
echo "================= NEXT STEPS ================="
echo "1) Edit ${APP_DIR}/.env and set OPENAI_API_KEY=<your key>"
echo "2) Restart: docker compose restart"
echo "3) Local test: http://<server-ip>:${PORT}${BASE_PATH}"
echo "4) Put NGINX in front (sample config provided in the docs output)."
echo "=============================================="
