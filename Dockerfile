# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (bản production-ready)
#
# Build thử: docker build -t day12-agent:prod .
#            docker images day12-agent:prod
# ═══════════════════════════════════════════════════════════════════

# ── Stage 1: builder ──────────────────────────────────────────────
# Stage này được phép "bẩn": có compiler, có cache pip, có file tạm.
# Không thứ nào trong đó đi sang image cuối.
FROM python:3.11-slim AS builder

WORKDIR /app

# COPY requirements.txt riêng, TRƯỚC source code: layer pip install chỉ bị
# dựng lại khi file này đổi, không phải mỗi lần sửa một dòng code.
COPY requirements.txt .

# --prefix=/install gom toàn bộ thư viện vào một thư mục để copy sang runtime.
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: runtime ──────────────────────────────────────────────
FROM python:3.11-slim AS runtime

# PYTHONDONTWRITEBYTECODE: không sinh .pyc trong container (chỉ tổ phình FS)
# PYTHONUNBUFFERED: log ra stdout ngay, không kẹt trong buffer khi bị SIGKILL
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

WORKDIR /app

# Chỉ mang thư viện đã cài sang — không mang pip cache, không mang compiler.
COPY --from=builder /install /usr/local

# Source code copy sau cùng: đây là thứ đổi thường xuyên nhất, để ở layer cuối
# thì các layer nặng phía trên vẫn được cache.
COPY app/ ./app/
COPY utils/ ./utils/

# User thường, không có shell đăng nhập. Thoát được khỏi app cũng không thành
# root trên host. Đặt SAU khi copy để không phải chỉnh quyền lằng nhằng.
RUN useradd --create-home --shell /usr/sbin/nologin appuser \
    && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

# Không có curl trong image slim — dùng chính Python đã có sẵn.
# Gọi /health (liveness), không gọi /ready: Redis chết không phải lý do
# để Docker giết container này.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os,urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.environ.get('PORT','8000') + '/health').read()" || exit 1

# `exec` là mấu chốt: nó thay thế tiến trình sh bằng uvicorn, nên uvicorn trở
# thành PID 1 và nhận TRỰC TIẾP SIGTERM. Không có `exec`, sh là PID 1 và KHÔNG
# chuyển tiếp tín hiệu cho con → uvicorn không drain, bị SIGKILL sau timeout.
# Vẫn dùng sh -c để ${PORT} được nội suy (cloud tự gán cổng, không cố định 8000).
# --timeout-graceful-shutdown: chờ request đang chạy xong rồi mới đóng, ràng
# buộc dưới thời gian orchestrator đợi trước khi SIGKILL.
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --timeout-graceful-shutdown ${SHUTDOWN_GRACE_SECONDS:-25}"]
