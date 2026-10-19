FROM python:3.13-slim
WORKDIR /app
COPY services/web_account/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY services/web_account/app.py services/web_account/library.py services/web_account/comments.py services/web_account/account_files.py services/web_account/ai_proxy.py ./
USER 65532:65532
EXPOSE 8000
CMD ["uvicorn", "app:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--no-access-log", "--no-proxy-headers"]
