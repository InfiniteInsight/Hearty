import io
import os
from datetime import datetime, timezone
from typing import Optional

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

from supabase import create_client

from app.health_profile.schemas import HealthProfileResponse
from app.models.schemas import MealWithSymptoms, SymptomResponse, TriggerFood, WellbeingResponse
from app.services import trend_engine, ai_extraction

supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def gather_export_data(user_id: str, start_date: Optional[datetime], end_date: Optional[datetime]) -> dict:
    """Fetch all data needed for the PDF report sections."""
    # Meals + symptoms
    meals_query = supabase.table("meals").select("*").eq("user_id", user_id).order("logged_at", desc=False)
    if start_date:
        meals_query = meals_query.gte("logged_at", start_date.isoformat())
    if end_date:
        meals_query = meals_query.lte("logged_at", end_date.isoformat())
    meals_result = meals_query.execute()
    meals_raw = meals_result.data or []

    meal_ids = [m["id"] for m in meals_raw]
    symptoms_raw: list[dict] = []
    if meal_ids:
        symptoms_result = supabase.table("symptoms").select("*").in_("meal_id", meal_ids).execute()
        symptoms_raw = symptoms_result.data or []
    symptoms_by_meal: dict[str, list] = {}
    for s in symptoms_raw:
        mid = s.get("meal_id")
        if mid:
            symptoms_by_meal.setdefault(mid, []).append(s)
    meals = [
        MealWithSymptoms(
            **m,
            symptoms=[SymptomResponse(**s) for s in symptoms_by_meal.get(m["id"], [])],
        )
        for m in meals_raw
    ]

    # Wellbeing
    wb_query = supabase.table("wellbeing_snapshots").select("*").eq("user_id", user_id).order("logged_at", desc=False)
    if start_date:
        wb_query = wb_query.gte("logged_at", start_date.isoformat())
    if end_date:
        wb_query = wb_query.lte("logged_at", end_date.isoformat())
    wb_result = wb_query.execute()
    wellbeing_data = wb_result.data or []

    # Food triggers (via trend engine to get labels)
    period_days = 365
    if start_date and end_date:
        period_days = max(int((end_date - start_date).total_seconds() / 86400), 1)
    trend_result = trend_engine.analyze_triggers(
        user_id=user_id,
        analysis_period_days=period_days,
        focus_symptom=None,
        min_occurrences=2,
    )
    food_triggers = [TriggerFood(**t) for t in trend_result["triggers"]]

    # Health profile
    hp_result = supabase.table("health_profile").select("*").eq("user_id", user_id).execute()
    hp_row = (hp_result.data or [{}])[0] if hp_result.data else {}
    health_profile: Optional[HealthProfileResponse] = None
    if hp_row:
        try:
            health_profile = HealthProfileResponse(
                allergens=hp_row.get("allergens") or [],
                intolerances=hp_row.get("intolerances") or [],
                conditions=hp_row.get("conditions") or [],
                dietary_protocols=hp_row.get("dietary_protocols") or [],
                updated_at=hp_row.get("updated_at") or datetime.now(timezone.utc),
            )
        except Exception:
            health_profile = None

    # Notification preferences
    np_result = supabase.table("notification_preferences").select("*").eq("user_id", user_id).execute()
    np_row = (np_result.data or [{}])[0] if np_result.data else {}
    ai_recommendations_enabled = bool(np_row.get("ai_recommendations_enabled", False))

    return {
        "meals": meals,
        "wellbeing_data": wellbeing_data,
        "food_triggers": food_triggers,
        "health_profile": health_profile,
        "ai_recommendations_enabled": ai_recommendations_enabled,
        "user_email": hp_row.get("user_email", ""),
        "total_meals": len(meals),
        "trend_result": trend_result,
    }


def render_symptom_timeline(meals_data: list) -> bytes:
    """Return PNG bytes of symptom severity by date. Returns a valid PNG even for empty data."""
    fig, ax = plt.subplots(figsize=(8, 4))

    dates: list[datetime] = []
    severities: list[float] = []

    for meal in meals_data:
        symptoms = getattr(meal, "symptoms", []) or []
        for sym in symptoms:
            if sym.severity is not None:
                logged = meal.logged_at
                if isinstance(logged, str):
                    logged = datetime.fromisoformat(logged.replace("Z", "+00:00"))
                dates.append(logged)
                severities.append(sym.severity)

    if dates:
        ax.scatter(dates, severities, alpha=0.6, color="#e74c3c", s=30)
        ax.xaxis.set_major_formatter(mdates.DateFormatter("%b %d"))
        fig.autofmt_xdate()
        ax.set_ylim(0, 11)
    else:
        ax.text(0.5, 0.5, "No symptom data available", transform=ax.transAxes,
                ha="center", va="center", color="gray", fontsize=12)

    ax.set_title("Symptom Severity Over Time")
    ax.set_xlabel("Date")
    ax.set_ylabel("Severity (1–10)")
    ax.grid(True, alpha=0.3)
    fig.tight_layout()

    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=100)
    plt.close(fig)
    buf.seek(0)
    return buf.read()


def render_wellbeing_trends(wellbeing_data: list) -> bytes:
    """Return PNG bytes of energy/mood/sleep trends over time. Returns a valid PNG even for empty data."""
    fig, ax = plt.subplots(figsize=(8, 4))

    dates: list[datetime] = []
    energy: list[Optional[float]] = []
    mood: list[Optional[float]] = []
    sleep: list[Optional[float]] = []

    for row in wellbeing_data:
        logged = row.get("logged_at")
        if not logged:
            continue
        if isinstance(logged, str):
            logged = datetime.fromisoformat(logged.replace("Z", "+00:00"))
        dates.append(logged)
        energy.append(row.get("energy_level"))
        mood.append(row.get("mood"))
        sleep.append(row.get("sleep_hours"))

    if dates:
        e_pairs = [(d, v) for d, v in zip(dates, energy) if v is not None]
        m_pairs = [(d, v) for d, v in zip(dates, mood) if v is not None]
        s_pairs = [(d, v) for d, v in zip(dates, sleep) if v is not None]
        if e_pairs:
            ax.plot(*zip(*e_pairs), label="Energy", color="#3498db", marker="o", markersize=4)
        if m_pairs:
            ax.plot(*zip(*m_pairs), label="Mood", color="#2ecc71", marker="s", markersize=4)
        if s_pairs:
            ax.plot(*zip(*s_pairs), label="Sleep (hrs)", color="#9b59b6", marker="^", markersize=4)
        ax.xaxis.set_major_formatter(mdates.DateFormatter("%b %d"))
        fig.autofmt_xdate()
        ax.legend(loc="upper right", fontsize=8)
    else:
        ax.text(0.5, 0.5, "No wellbeing data available", transform=ax.transAxes,
                ha="center", va="center", color="gray", fontsize=12)

    ax.set_title("Wellbeing Trends")
    ax.set_xlabel("Date")
    ax.set_ylabel("Score / Hours")
    ax.grid(True, alpha=0.3)
    fig.tight_layout()

    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=100)
    plt.close(fig)
    buf.seek(0)
    return buf.read()


def generate_pdf(user_id: str, start_date: Optional[datetime], end_date: Optional[datetime]) -> bytes:
    """Assemble and return a PDF trend report as bytes."""
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import letter
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.units import inch
    from reportlab.platypus import (
        Image, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle,
    )

    data = gather_export_data(user_id, start_date, end_date)
    meals = data["meals"]
    wellbeing_data = data["wellbeing_data"]
    food_triggers = data["food_triggers"]
    health_profile = data["health_profile"]
    ai_recommendations_enabled = data["ai_recommendations_enabled"]

    symptom_png = render_symptom_timeline(meals)
    wellbeing_png = render_wellbeing_trends(wellbeing_data)

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=letter, topMargin=0.75 * inch, bottomMargin=0.75 * inch)
    styles = getSampleStyleSheet()
    heading1 = styles["Heading1"]
    heading2 = styles["Heading2"]
    normal = styles["Normal"]
    small = ParagraphStyle("small", parent=normal, fontSize=9)

    story = []

    # ── Cover ────────────────────────────────────────────────────────────────
    story.append(Paragraph("Hearty — Personal Health Report", heading1))
    date_range = (
        f"{start_date.strftime('%Y-%m-%d') if start_date else 'All time'}"
        f" → "
        f"{end_date.strftime('%Y-%m-%d') if end_date else 'Today'}"
    )
    story.append(Paragraph(f"Period: {date_range}", normal))
    story.append(Paragraph(f"Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}", normal))
    story.append(Spacer(1, 0.3 * inch))

    # ── Section 1: Summary statistics ────────────────────────────────────────
    story.append(Paragraph("1. Summary Statistics", heading2))
    total_symptoms = sum(len(m.symptoms) for m in meals)
    story.append(Paragraph(f"Meals logged: {len(meals)}", normal))
    story.append(Paragraph(f"Symptom events: {total_symptoms}", normal))
    story.append(Spacer(1, 0.2 * inch))

    # ── Section 2: Top trigger foods ─────────────────────────────────────────
    story.append(Paragraph("2. Top Trigger Foods", heading2))
    if food_triggers:
        tbl_data = [["Food", "Symptom", "Confidence", "Occurrences", "Avg Severity", "Status"]]
        for tf in food_triggers[:10]:
            tbl_data.append([
                tf.food_name,
                tf.symptom_type,
                f"{tf.confidence_score:.2f}",
                str(tf.occurrence_count),
                f"{tf.avg_severity:.1f}" if tf.avg_severity is not None else "—",
                tf.label or ("confirmed" if tf.is_confirmed else "—"),
            ])
        tbl = Table(tbl_data, colWidths=[1.4 * inch, 1.2 * inch, 0.9 * inch, 0.9 * inch, 0.9 * inch, 1.3 * inch])
        tbl.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#2c3e50")),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("FONTSIZE", (0, 0), (-1, -1), 8),
            ("GRID", (0, 0), (-1, -1), 0.5, colors.lightgrey),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f8f9fa")]),
            ("ALIGN", (2, 0), (-1, -1), "CENTER"),
        ]))
        story.append(tbl)
    else:
        story.append(Paragraph("No trigger foods identified yet.", normal))
    story.append(Spacer(1, 0.2 * inch))

    # ── Section 3: Symptom timeline chart ────────────────────────────────────
    story.append(Paragraph("3. Symptom Timeline", heading2))
    sym_img_buf = io.BytesIO(symptom_png)
    sym_img = Image(sym_img_buf, width=6 * inch, height=3 * inch)
    story.append(sym_img)
    story.append(Spacer(1, 0.2 * inch))

    # ── Section 4: Wellbeing trends chart ────────────────────────────────────
    story.append(Paragraph("4. Wellbeing Trends", heading2))
    wb_img_buf = io.BytesIO(wellbeing_png)
    wb_img = Image(wb_img_buf, width=6 * inch, height=3 * inch)
    story.append(wb_img)
    story.append(Spacer(1, 0.2 * inch))

    # ── Section 5: Pattern observations ──────────────────────────────────────
    story.append(Paragraph("5. Pattern Observations", heading2))
    observations = _build_observations(food_triggers, meals)
    for obs in observations:
        story.append(Paragraph(f"• {obs}", normal))
    if not observations:
        story.append(Paragraph("Not enough data to identify patterns yet. Keep logging!", normal))
    story.append(Spacer(1, 0.2 * inch))

    # ── Section 6: AI-generated recommendations (conditional) ────────────────
    if ai_recommendations_enabled:
        story.append(Paragraph("6. AI-Generated Recommendations", heading2))
        story.append(Paragraph(
            "<i>Not medical advice. For personal awareness only.</i>", small
        ))
        stats = {
            "meals_logged": len(meals),
            "top_triggers": [
                {"food_name": tf.food_name, "symptom_type": tf.symptom_type,
                 "confidence_score": tf.confidence_score}
                for tf in food_triggers[:5]
            ],
        }
        try:
            rec_text = ai_extraction.generate_summary(stats)
        except Exception:
            rec_text = "Unable to generate AI recommendations at this time."
        story.append(Paragraph(rec_text, normal))

    doc.build(story)
    buf.seek(0)
    return buf.read()


def _build_observations(food_triggers: list, meals: list) -> list[str]:
    """Derive plain-language pattern observations from the data."""
    observations = []
    established = [tf for tf in food_triggers if tf.label == "established"]
    early = [tf for tf in food_triggers if tf.label and "early signal" in tf.label]

    if established:
        foods = ", ".join(tf.food_name for tf in established[:3])
        observations.append(f"Strong correlations found between symptoms and: {foods}.")
    if early:
        foods = ", ".join(tf.food_name for tf in early[:3])
        observations.append(f"Early signals detected for: {foods}. More data needed to confirm.")

    total_symptoms = sum(len(m.symptoms) for m in meals)
    if meals and total_symptoms:
        rate = total_symptoms / len(meals)
        observations.append(f"Average of {rate:.1f} symptom event(s) per meal logged.")

    return observations
