FROM python:3.11-slim

WORKDIR /app

COPY . .

RUN apt-get update && apt-get install -y \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir -r requirements.txt

# Disable Flask/Werkzeug debug mode.
# Without this, app.py defaults FLASK_DEBUG to "1" which enables
# the interactive debugger and reloader, adding overhead to every
# request even when no error occurs.
ENV FLASK_DEBUG=0

EXPOSE 7860

# ── Production WSGI server (Gunicorn) ───────────────────────────────
#
#  Single synchronous worker — correct for this workload:
#
#  This app holds one PyTorch model (~300 MB) in RAM.  Forking more
#  than one worker duplicates that memory footprint.  On Hugging Face
#  free tier this causes RAM pressure and swapping, which is why
#  workers=2 was slower (21 s) than the dev server (7 s).
#
#  The sync worker class is correct because the OCR pipeline is purely
#  CPU-bound and mixes OpenCV C-extensions with PyTorch.  Threading
#  inside a single process (gthread/gevent) adds GIL contention with
#  no throughput benefit for this use case.
#
#  Speed improvement over `python app.py` comes from removing:
#    • Werkzeug file-system reloader (inotify polling every request)
#    • Interactive debugger middleware (attached even on success paths)
#    • FLASK_DEBUG overhead now also disabled via ENV above
#
#  --timeout 120  : OCR on a large newspaper photo can take 10-20 s.
#                   Gunicorn's default 30 s would kill the worker
#                   mid-pipeline and return a 502 to the browser.
#  --keep-alive 5 : Reuse TCP connections from the HF reverse proxy,
#                   avoiding a new TCP handshake on every API call.
#
CMD ["gunicorn", \
     "--workers", "1", \
     "--worker-class", "sync", \
     "--timeout", "120", \
     "--keep-alive", "5", \
     "--log-level", "info", \
     "--bind", "0.0.0.0:7860", \
     "app:app"]