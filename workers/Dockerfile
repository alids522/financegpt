FROM python:3.12-slim
RUN pip install --no-cache-dir pypdf==6.2.0
WORKDIR /app
COPY pdf_worker.py .
USER 10001:10001
EXPOSE 8080
CMD ["python", "pdf_worker.py"]
