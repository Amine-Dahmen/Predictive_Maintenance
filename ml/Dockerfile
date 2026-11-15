# Service de prédiction de panne (US-22). Le modèle entraîné (models/) est inclus dans l'image.
FROM python:3.13-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY predimaint_ml/ predimaint_ml/
COPY models/ models/
RUN useradd --system --uid 10001 ml && chown -R ml /app
USER ml
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"
CMD ["uvicorn", "predimaint_ml.service:app", "--host", "0.0.0.0", "--port", "8000"]
