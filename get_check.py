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
        model="gpt-4",
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
            "rationale": "Model returned non-JJSON or ambiguous output; defaulting conservatively.",
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
