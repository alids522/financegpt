FROM python:3.12-slim
RUN pip install --no-cache-dir pypdf==6.2.0 reportlab==4.4.4 tzdata==2025.2
WORKDIR /app
COPY pdf_worker.py .
COPY Inter.ttf .
USER 10001:10001
EXPOSE 8080
CMD ["python", "pdf_worker.py"]
