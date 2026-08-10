# Phiếu Phản Ánh — K3 Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng placeholder ở mỗi câu bằng câu trả lời của bạn.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Lê Quang Huy  Mã học viên: 2A202601821

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

> Tôi deploy lên Railway nhưng quên set biến `AGENT_API_KEY` trong dashboard.
> Nếu `Settings` để mặc định `"changeme"`, app vẫn khởi động bình thường, health
> check xanh, tôi tưởng mọi thứ ổn — trong khi endpoint `/ask` giờ chấp nhận
> đúng cái khóa `"changeme"` mà cả lớp (và cả internet) đều đoán ra. Tôi chỉ
> phát hiện khi ai đó đã gọi API bằng khóa đó. Với thiết kế fail-fast, pydantic
> ném `ValidationError` ngay lúc container start, Railway thấy app crash và báo
> deploy fail — tôi biết mình quên set secret trong 30 giây đầu, trước khi có
> bất kỳ traffic thật nào. Lỗi ồn ào lúc khởi động luôn rẻ hơn lỗ hổng im lặng
> lúc chạy production.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

> Dòng log JSON thu được trên stdout của service sau khi gọi `/ask` thành công:
>
> ```
> {"event": "ask_completed", "level": "info", "timestamp": "2026-08-10T03:31:21.360783+00:00", "user_id": "sv-cau2", "tokens_in": 6, "tokens_out": 44, "cost_usd": 2.73e-05}
> ```
>
> Hai việc làm được mà `print("đã trả lời xong")` không làm được:
> 1. **Lọc và đếm bằng máy.** Vì mỗi dòng là một JSON object, tôi có thể đẩy log
>    vào Datadog/Railway logs rồi query `event="ask_completed" AND user_id="sv-test"`
>    để đếm chính xác user này đã gọi bao nhiêu lần, hoặc `sum(cost_usd)` để biết
>    tổng chi phí — không cần bóc tách chuỗi tiếng Việt bằng regex.
> 2. **Cảnh báo tự động theo ngưỡng.** Có trường `cost_usd` là số nên tôi dựng
>    được alert kiểu "gửi cảnh báo khi tổng cost_usd trong 1 giờ vượt $X". Với
>    câu `print` tự do thì máy không biết đâu là con số để so sánh.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu, `FROM python:3.11`) | 1.73 GB |
| Multi-stage | 270 MB |

(Đo thật bằng `docker images`: bản 1-stage 1.73 GB, bản multi-stage 270 MB —
nhỏ hơn khoảng 6.4 lần, chênh gần 1.46 GB.)

Giải thích: phần dung lượng chênh lệch đó là những gì?

> Chênh lệch đến từ hai nguồn. Thứ nhất là **base image**: bản đầu dùng
> `python:3.11` đầy đủ (~1 GB, mang theo cả bộ compiler C, git, các thư viện hệ
> thống để build). Bản multi-stage dùng `python:3.11-slim` (~120 MB) cho stage
> runtime. Thứ hai là **rác của quá trình build**: stage `builder` cài thư viện
> có sinh ra pip cache, file `.o`, header để biên dịch package — nhưng runtime
> chỉ `COPY --from=builder /install` phần thư viện đã cài xong, bỏ lại toàn bộ
> compiler và cache ở stage builder. Nói ngắn gọn: phần chênh lệch là **những
> thứ cần để *lắp ráp* image nhưng không cần để *chạy* nó** — và chúng không đi
> vào image cuối.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

> Dockerfile của tôi xếp thứ tự: `COPY requirements.txt` → `RUN pip install`
> → `COPY app/ ./app/`. Khi tôi sửa một ký tự trong `app/main.py`:
> - Các layer **dùng lại từ cache**: `FROM`, `WORKDIR`, `COPY requirements.txt`,
>   và `RUN pip install` — vì `requirements.txt` không đổi nên Docker biết layer
>   cài thư viện y hệt lần trước.
> - Layer **phải chạy lại**: `COPY app/ ./app/` trở đi (vì nội dung app đã đổi),
>   cộng các layer sau nó.
>
> Kết quả: build lại chỉ mất vài giây, không phải tải và cài lại thư viện.
>
> Nếu đặt `COPY . .` (copy toàn bộ source) **trước** `RUN pip install`, thì mỗi
> lần sửa một dòng code, layer `COPY . .` bị đổi → Docker coi mọi layer sau nó
> (kể cả `pip install`) là "cache đã hỏng" và **cài lại toàn bộ thư viện từ
> đầu**. Một thay đổi 1 ký tự cũng tốn cả phút build. Đây chính là lý do phải
> tách `requirements.txt` ra copy riêng trước.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

> Chuỗi sự kiện khi container chạy bằng root:
> 1. Code Python của tôi có lỗ hổng (ví dụ một chỗ nhận input người dùng rồi
>    truyền vào lệnh shell, hoặc một thư viện dính RCE).
> 2. Kẻ tấn công lợi dụng lỗ hổng để chạy lệnh tùy ý **bên trong container**.
>    Vì tiến trình app chạy bằng root, các lệnh đó cũng chạy với quyền root.
> 3. Là root trong container, kẻ tấn công cài thêm công cụ, đọc mọi file, và nếu
>    container bị cấu hình lỏng (mount host path, `--privileged`, hoặc một lỗ
>    hổng thoát container) thì root-trong-container có đường trở thành **root
>    trên host** — lúc này toàn bộ máy bị kiểm soát.
>
> Lệnh `USER appuser` cắt đứt chuỗi ở **bước 2**: tiến trình app chạy bằng user
> thường không có quyền gì đặc biệt. Kẻ tấn công vẫn có thể chạy lệnh trong
> container, nhưng chỉ với quyền của `appuser` — không cài được gói hệ thống,
> không ghi được vào thư mục ngoài phạm vi, và bàn đạp để leo lên host gần như
> biến mất. Nó không vá lỗ hổng gốc, nhưng giới hạn thiệt hại xuống mức tối
> thiểu (nguyên tắc least privilege).

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

> Tối đa **20 request** trong 2 giây. Cách đạt được: cửa sổ đếm-theo-phút-đồng-hồ
> reset về 0 vào đúng giây 00. Người dùng gửi 10 request vào lúc `10:00:59`
> (vẫn thuộc phút 10:00, đủ hạn mức 10), rồi chờ đến `10:01:01` — bộ đếm đã
> reset sang phút mới nên gửi tiếp 10 request nữa cũng hợp lệ. Tổng 20 request
> chỉ trong khoảng ~2 giây bắc qua ranh giới phút, mà không luật nào bị vi phạm.
>
> Sliding window 60 giây của tôi bịt lỗ này: nó luôn đếm số request trong đúng
> 60 giây *gần nhất* tính từ thời điểm hiện tại, không quan tâm mốc phút. Tại
> `10:01:01`, 10 request lúc `10:00:59` vẫn nằm trong cửa sổ, nên request thứ 11
> bị chặn 429. Tôi đã kiểm chứng bằng đồng hồ giả trong test: 5 request tại t và
> t+0.1..0.4, request tại t+1s bị chặn, tới t+61s (các request cũ đã trôi khỏi
> cửa sổ) mới được gọi lại.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

> Khác biệt cốt lõi: **rate limit giới hạn *số lượng* request** (bao nhiêu lần
> gọi trong một khoảng thời gian), **cost guard giới hạn *số tiền*** (tổng chi
> phí token trong một tháng). Một cái đếm lần, một cái đếm đô-la.
>
> - **Rate limit cho qua, cost guard chặn:** user gửi request thứ 3 trong phút
>   (hạn mức 10/phút → còn quota, rate limit cho qua), nhưng đây là câu hỏi kèm
>   một đoạn văn bản 50.000 token và user đã tiêu gần hết ngân sách $10 của
>   tháng → cost guard trả 402. Ít request nhưng mỗi request quá đắt.
> - **Cost guard cho qua, rate limit chặn:** user bắn 200 request "hi" trong 10
>   giây. Mỗi request rẻ như cho nên tổng tiền chưa tới đâu (cost guard cho qua),
>   nhưng vượt xa 10 request/phút → rate limit trả 429. Nhiều request nhưng mỗi
>   cái gần như miễn phí. Đây cũng là kịch bản chống DoS: chặn bằng số lần trước
>   khi kịp tính tới tiền.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

> Nếu gộp `/health` và `/ready` làm một và cho nó ping Redis, chuỗi sự kiện khi
> Redis mất kết nối 30 giây:
> 1. Redis ngắt. Ở cả 3 container, endpoint gộp này ping Redis thất bại → trả
>    503 (hoặc timeout).
> 2. Orchestrator dùng chính endpoint đó làm **liveness probe** — nó hiểu 503
>    nghĩa là "container hỏng, cần restart", chứ không phải "phụ thuộc tạm chết".
> 3. Nó lần lượt **giết và restart cả 3 container** vì cả 3 đều báo 503 — dù
>    bản thân tiến trình Python vẫn khỏe, chỉ có Redis là bên ngoài đang lỗi.
> 4. Restart không làm Redis sống lại (Redis là dịch vụ riêng), nên container
>    mới khởi động xong lại ping fail, lại 503, lại bị restart → **vòng lặp
>    CrashLoopBackOff** trên toàn cụm. Một sự cố Redis 30 giây biến thành sập
>    toàn bộ service, và khi Redis hồi phục thì cụm vẫn đang loạng choạng.
>
> Đây chính là lý do tách hai endpoint: `/health` (liveness) **không** chạm
> Redis nên vẫn 200 → orchestrator không restart oan; `/ready` (readiness) ping
> Redis và trả 503 → load balancer chỉ **tạm ngừng đẩy traffic** vào instance,
> rồi tự đưa trở lại khi Redis hồi phục. Không container nào bị giết.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

> Quan sát thật trên service đang chạy (một instance, Redis thật qua docker
> compose): gọi `/ask` nhiều lần với cùng `X-User-Id`, `history_length` trong
> response tăng đều và nhất quán: 0 → 2 → 4 → 6 theo đúng số lượt đã trao đổi
> (mỗi lượt thêm 2 message: user + assistant). Câu trả lời còn tự kèm "Mình
> đang nhớ N lượt trao đổi trước đó", xác nhận history được đọc lại từ Redis.
>
> Với store dùng Redis, khi scale lên 3 container (`--scale agent=3` sau một
> load balancer): cả 3 chia sẻ chung một Redis, nên dù mỗi request rơi vào
> container khác nhau, tất cả đều đọc/ghi cùng một key `history:<user>`.
> `history_length` vẫn tăng đều 0, 2, 4, 6... bất kể load balancer đẩy request
> vào instance nào — đúng như quan sát ở trên, chỉ khác là traffic trải ra
> nhiều process.
>
> Nếu lịch sử nằm trong một **dict Python trong RAM** của từng process, mỗi
> container có bộ nhớ riêng. Load balancer xoay vòng request qua 3 instance, nên
> `history_length` sẽ **nhảy loạn xạ**: request vào container A thấy 0, request
> sau vào B cũng thấy 0 (B chưa từng thấy lượt trước), request vào A lần nữa thấy
> 2... Con số phụ thuộc vào instance nào tình cờ nhận request, không phản ánh
> đúng lịch sử thật. Agent "mất trí nhớ" mỗi khi bị định tuyến sang instance
> khác — đó là hệ quả của việc giữ state trong process, và là lý do phải đẩy
> state ra Redis để service trở nên stateless và scale ngang được.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

> Tôi deploy lên Railway và gặp lỗi ở giai đoạn chạy container (build đã xong):
> - **Thông báo lỗi:** trong deploy log, container khởi động rồi crash ngay với
>   `Error: Invalid value for '--port': '$PORT' is not a valid integer.`, lặp lại
>   nhiều lần (Railway restart theo restartPolicy).
> - **Tìm nguyên nhân:** chuỗi `$PORT` xuất hiện *nguyên văn* trong thông báo lỗi
>   thay vì một con số → nghĩa là nó không được nội suy. `railway.toml` của tôi
>   đặt `startCommand = "uvicorn app.main:app --host 0.0.0.0 --port $PORT"`, và
>   Railway chạy lệnh này **không qua shell**, nên `$PORT` không được thay bằng
>   cổng thật mà bị truyền thẳng cho uvicorn. uvicorn cần một số nguyên nên nó
>   từ chối chuỗi `"$PORT"`.
> - **Sửa:** bọc lệnh trong `sh -c` để bắt buộc chạy qua shell:
>   `startCommand = "sh -c 'uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}'"`.
>   Lúc này shell mới nội suy `$PORT` thành cổng Railway cấp; `${PORT:-8000}` là
>   dự phòng dùng 8000 nếu biến chưa được set. Push commit, Railway deploy lại →
>   `/health` trả 200, `/ready` trả `{"status":"ready","redis":true}`. Bài học:
>   cổng phải đọc từ biến môi trường, và biến chỉ được nội suy khi lệnh chạy qua
>   một shell thật.
