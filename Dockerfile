FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app

# Apply current security updates to the Debian base image.
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root runtime account.
RUN groupadd --system appgroup \
    && useradd --system --gid appgroup appuser

COPY requirements.txt .

# Install dependencies, then remove pip from the final runtime image.
RUN python -m pip install --no-cache-dir --upgrade pip \
    && python -m pip install --no-cache-dir --upgrade \
       'setuptools>=78.1.1' \
       'urllib3>=2.8.0' \
       'msgpack>=1.2.3' \
    && python -m pip install --no-cache-dir -r requirements.txt \
    && python -m pip uninstall -y pip \
    && rm -rf /usr/local/lib/python3.12/site-packages/pip \
              /usr/local/lib/python3.12/site-packages/pip-*.dist-info

COPY app ./app

USER appuser

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", \
     "--workers", "2", "--access-logfile", "-", \
     "app.main:app"]
