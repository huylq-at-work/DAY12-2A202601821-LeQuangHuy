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

> Lúc mình deploy lên Railway, thú thật là ban đầu mình quên set `AGENT_API_KEY`
> trong dashboard (đúng ra là mình có gặp một lỗi khác trước, nhưng cứ giả sử
> mình quên đúng biến này). Nếu hồi đó mình để `Settings` có mặc định
> `"changeme"`, thì app vẫn khởi động ngon lành, `/health` vẫn xanh, và mình sẽ
> yên tâm nghĩ là xong. Vấn đề là cái endpoint `/ask` khi đó lại đang chấp nhận
> đúng cái khóa `"changeme"` — một chuỗi mà bất kỳ ai từng đọc qua repo mẫu cũng
> đoán được. Nghĩa là service coi như không có bảo mật, mà mình thì không hề hay
> biết cho tới khi có người lạ gọi API bằng chính khóa đó.
>
> Vì mình để `agent_api_key` không có mặc định nên mọi thứ diễn ra ngược lại:
> pydantic ném `ValidationError` ngay khi container vừa start, Railway thấy tiến
> trình chết nên báo deploy fail luôn. Mình biết mình thiếu secret chỉ sau vài
> chục giây, trước khi có bất kỳ traffic thật nào. Mình thấy đây là một đánh đổi
> hợp lý: một lỗi ồn ào lúc khởi động dễ chịu hơn nhiều so với một lỗ hổng nằm
> im trong lúc chạy production.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

> Đây là một dòng log mình lấy được từ stdout của service sau khi gọi `/ask`
> thành công:
>
> ```
> {"event": "ask_completed", "level": "info", "timestamp": "2026-08-10T03:31:21.360783+00:00", "user_id": "sv-cau2", "tokens_in": 6, "tokens_out": 44, "cost_usd": 2.73e-05}
> ```
>
> Việc đầu tiên mình làm được với dòng này mà một câu `print` chung chung không
> làm được là lọc và thống kê bằng máy. Vì mỗi log là một JSON object có cấu
> trúc, mình có thể đẩy nó vào một hệ thống như Railway logs hay Datadog rồi lọc
> theo `event` và `user_id`, hoặc cộng dồn trường `cost_usd` để biết chính xác
> một user đã tiêu bao nhiêu tiền — không phải ngồi viết regex để bóc số ra khỏi
> một câu tiếng Việt.
>
> Việc thứ hai là dựng cảnh báo tự động. Vì `cost_usd` là một con số thật chứ
> không phải chữ, mình có thể đặt một luật kiểu "báo động nếu tổng chi phí trong
> một giờ vượt ngưỡng X". Với `print("đã trả lời xong")` thì máy chẳng biết đâu
> là con số để mà so sánh. Một điểm mình để ý thêm trong lúc test: khi mình gọi
> sai (thiếu key hay sai method), request đó bị chặn từ sớm nên không hề sinh ra
> log `ask_completed` — tức là chỉ cần đếm event này là mình tách được request
> thành công khỏi request bị từ chối, điều mà một dòng print tự do không phân
> biệt nổi.

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

Giải thích: phần dung lượng chênh lệch đó là những gì?

> Mình build cả hai rồi đọc số từ `docker images`: bản một stage nặng 1.73 GB,
> còn bản multi-stage chỉ 270 MB, tức nhỏ hơn khoảng sáu lần rưỡi. Khi ngồi nghĩ
> xem gần 1.5 GB chênh nhau nằm ở đâu, mình thấy nó đến từ hai chỗ.
>
> Chỗ lớn nhất là base image. Bản đầu dùng `python:3.11` bản đầy đủ, vốn kéo
> theo cả bộ compiler C, git và một đống thư viện hệ thống chỉ cần để *biên
> dịch* chứ không cần để *chạy*. Bản multi-stage của mình đổi stage runtime sang
> `python:3.11-slim`, nhẹ hơn hẳn vì đã lược đi những thứ đó.
>
> Chỗ còn lại là rác của quá trình build. Ở stage `builder`, lúc `pip install`
> có sinh ra pip cache và các file trung gian để biên dịch package. Nhưng stage
> runtime của mình chỉ `COPY --from=builder /install` — tức là chỉ nhặt phần thư
> viện đã cài xong mang sang, còn toàn bộ compiler và cache thì bỏ lại luôn ở
> stage builder, không đi vào image cuối. Nói gọn thì phần chênh lệch chính là
> mọi thứ cần để lắp ráp image nhưng không cần để nó phục vụ request.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

> Dockerfile của mình xếp theo thứ tự `COPY requirements.txt` rồi `RUN pip
> install` rồi mới `COPY app/ ./app/`. Nên khi mình chỉ sửa một ký tự trong
> `app/main.py` rồi build lại, Docker vẫn dùng lại được cache cho các layer phía
> trên: `FROM`, `WORKDIR`, cái `COPY requirements.txt` và cả `RUN pip install` —
> đơn giản vì `requirements.txt` không đổi nên Docker biết chắc kết quả cài thư
> viện y hệt lần trước. Chỉ từ layer `COPY app/` trở đi mới phải chạy lại vì nội
> dung thư mục app đã khác. Thành ra build lại chỉ mất vài giây thay vì phải tải
> và cài lại cả đống thư viện.
>
> Nếu mình làm ngược lại, đặt `COPY . .` lên trước `RUN pip install`, thì mọi
> chuyện hỏng ngay. Chỉ cần sửa một dòng code là layer `COPY . .` đã đổi, mà một
> khi một layer đổi thì Docker coi tất cả layer sau nó — kể cả `pip install` —
> là cache không còn dùng được và phải chạy lại từ đầu. Sửa một ký tự cũng phải
> chờ cài lại toàn bộ dependency mất cả phút. Đó chính là lý do mình cố tình tách
> `requirements.txt` ra copy riêng trước phần source.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

> Mình hình dung kịch bản xấu nhất như thế này. Giả sử code Python của mình có
> một lỗ hổng — chẳng hạn một chỗ vô tình đưa input người dùng vào lệnh shell,
> hoặc một thư viện dính lỗi cho phép chạy code từ xa. Kẻ tấn công khai thác chỗ
> đó để chạy được lệnh tùy ý bên trong container. Nếu tiến trình app đang chạy
> bằng root, thì mấy lệnh nó chèn vào cũng chạy với quyền root. Đã là root trong
> container thì nó cài thêm công cụ, đọc mọi file thoải mái; và nếu container lại
> được cấu hình lỏng lẻo — mount nhầm thư mục của host, chạy `--privileged`, hay
> gặp một lỗ hổng thoát container — thì cái quyền root bên trong đó có đường trở
> thành root ngay trên máy host, coi như mất cả server.
>
> Lệnh `USER appuser` chặn chuỗi này lại ngay ở đoạn kẻ tấn công vừa chạy được
> lệnh. Lúc đó tiến trình app không còn là root nữa mà là một user thường không
> có đặc quyền gì, nên dù nó có chạy được lệnh trong container thì cũng chỉ với
> quyền của `appuser`: không cài được gói hệ thống, không ghi ra ngoài phạm vi
> cho phép, và cái bàn đạp để leo lên host gần như không còn. Nó không vá được
> lỗ hổng gốc trong code, nhưng kéo mức thiệt hại xuống thấp nhất có thể — đúng
> tinh thần least privilege.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

> Với cách đếm theo phút đồng hồ, một người có thể nhét được tối đa 20 request
> chỉ trong khoảng hai giây. Mẹo là lợi dụng đúng thời điểm bộ đếm reset về 0 ở
> giây 00. Người dùng gửi 10 request vào lúc 10:00:59 — vẫn nằm trong phút 10:00
> nên đủ hạn mức 10 — rồi đợi thêm hai giây sang 10:01:01. Lúc này đã là phút
> mới, bộ đếm vừa reset, nên gửi tiếp 10 request nữa cũng hoàn toàn hợp lệ. Cộng
> lại là 20 request bắc qua ranh giới phút mà không luật nào bị vi phạm, dù thực
> tế đó là một cú dồn tải rõ ràng.
>
> Sliding window mình làm bịt được đúng cái khe này, vì nó không quan tâm mốc
> phút mà luôn đếm số request trong đúng 60 giây gần nhất tính ngược từ hiện tại.
> Ở thời điểm 10:01:01, mười request lúc 10:00:59 vẫn còn nằm trong cửa sổ, nên
> request thứ 11 bị chặn 429 ngay. Mình có kiểm chứng bằng đồng hồ giả trong
> test: bắn 5 request quanh mốc t, request ở t+1 giây đã bị chặn, phải tới t+61
> giây — khi mấy request cũ trôi hẳn ra khỏi cửa sổ — thì mới gọi lại được.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

> Với mình, cách phân biệt gọn nhất là một cái đếm lần còn một cái đếm tiền.
> Rate limit khống chế *số lượng* request trong một khoảng thời gian, còn cost
> guard khống chế *tổng chi phí* token trong cả tháng. Chúng canh hai thứ khác
> nhau nên hoàn toàn có thể một cái cho qua trong khi cái kia chặn.
>
> Trường hợp rate limit cho qua mà cost guard phải chặn: một user mới gọi
> request thứ ba trong phút, quota còn dư nên rate limit không có lý do gì để
> cản. Nhưng câu hỏi lần này kèm một đoạn văn bản mấy chục nghìn token, mà user
> thì đã tiêu gần cạn ngân sách tháng — thế là cost guard trả 402. Ít request
> nhưng mỗi request quá đắt.
>
> Trường hợp ngược lại: một user bắn 200 request "hi" trong mười giây. Mỗi
> request rẻ đến mức tổng tiền chẳng đáng kể nên cost guard chẳng buồn để ý,
> nhưng nó vượt xa mức 10 request mỗi phút nên rate limit chặn bằng 429. Nhiều
> request mà cái nào cũng gần như miễn phí. Đây cũng là lúc rate limit đóng vai
> lá chắn chống DoS: nó cắt bằng số lần trước cả khi cost guard kịp tính tới
> chuyện tiền nong.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

> Giả sử mình gộp `/health` và `/ready` làm một, và cho cái endpoint chung đó
> ping Redis. Khi Redis rớt mạng 30 giây, mọi chuyện sẽ diễn ra thế này. Đầu
> tiên, cả ba container đều ping Redis không được nên cùng trả 503. Vấn đề là
> orchestrator lại đang dùng chính endpoint này làm liveness probe, mà với nó
> 503 nghĩa là "container hỏng rồi, restart đi" chứ không phải "một dependency
> bên ngoài đang chập chờn". Thế là nó lần lượt giết và dựng lại cả ba container,
> dù bản thân tiến trình Python vẫn khỏe, lỗi chỉ nằm ở Redis bên ngoài. Restart
> thì đâu làm Redis sống lại được, nên container mới khởi động xong lại ping fail,
> lại 503, lại bị giết — thành một vòng lặp CrashLoopBackOff trên toàn cụm. Một
> sự cố Redis vỏn vẹn 30 giây bị khuếch đại thành sập cả service, và tới lúc
> Redis hồi phục thì cụm vẫn còn đang loạng choạng vì bị restart dồn dập.
>
> Đó chính là lý do mình tách hai endpoint. `/health` là liveness nên không đụng
> tới Redis, cứ tiến trình còn sống là trả 200 — orchestrator không có cớ để
> restart oan. Còn `/ready` là readiness, được phép ping Redis và trả 503 khi
> Redis chết, nhưng load balancer chỉ hiểu tín hiệu đó là "tạm đừng đẩy traffic
> vào instance này" rồi tự đưa nó trở lại pool khi Redis lành. Không container
> nào bị giết cả.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

> Trên service mình đang chạy (một instance, nối tới Redis thật qua docker
> compose), mình gọi `/ask` nhiều lần với cùng một `X-User-Id` và thấy
> `history_length` tăng rất đều: 0 rồi 2 rồi 4 rồi 6, mỗi lượt cộng thêm hai vì
> một lượt trao đổi gồm một message của user và một của assistant. Câu trả lời
> còn tự thêm câu "Mình đang nhớ N lượt trao đổi trước đó", nên mình khá chắc là
> history đang được đọc lại từ Redis chứ không phải bịa ra.
>
> Nếu scale lên ba container sau một load balancer mà vẫn giữ store trong Redis,
> con số này vẫn tăng đều như vậy, bởi cả ba cùng đọc ghi chung một key
> `history:<user>` trên một Redis duy nhất — request rơi vào instance nào cũng
> nhìn thấy đúng lịch sử đó, chỉ khác là tải được chia ra nhiều process.
>
> Nhưng nếu mình cất lịch sử trong một dict Python nằm trong RAM của từng
> process thì mọi thứ vỡ. Mỗi container có bộ nhớ riêng, load balancer lại xoay
> vòng request qua ba instance, nên `history_length` sẽ nhảy lung tung: lần vào
> container A thấy 0, lần sau vào B cũng thấy 0 vì B chưa từng biết lượt trước,
> lần sau nữa quay lại A mới thấy 2. Con số phụ thuộc vào việc request tình cờ
> rơi vào máy nào chứ không phản ánh lịch sử thật, và agent thì "mất trí nhớ" mỗi
> khi bị định tuyến sang instance khác. Chính vì vậy mà state phải được đẩy ra
> Redis — có stateless thì mới scale ngang được mà không lỗi.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

> Lỗi mình gặp trên Railway xảy ra sau khi build đã xong, ngay lúc container bắt
> đầu chạy. Trong deploy log, container cứ khởi động rồi chết ngay với dòng
> `Error: Invalid value for '--port': '$PORT' is not a valid integer.`, và vì
> Railway có restartPolicy nên nó thử lại mấy lần, log lặp đi lặp lại đúng câu
> đó.
>
> Chi tiết giúp mình lần ra nguyên nhân là chuỗi `$PORT` hiện lên nguyên văn
> trong thông báo lỗi thay vì một con số — tức là nó không được nội suy thành
> giá trị thật. Nhìn lại `railway.toml`, mình để `startCommand = "uvicorn
> app.main:app --host 0.0.0.0 --port $PORT"`. Railway chạy lệnh này không thông
> qua một shell, nên `$PORT` không được thay bằng cổng mà Railway cấp mà bị đưa
> thẳng cho uvicorn như một chuỗi. uvicorn cần số nguyên cho `--port` nên nó từ
> chối luôn.
>
> Mình sửa bằng cách bọc lệnh trong `sh -c` để ép nó chạy qua shell:
> `startCommand = "sh -c 'uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}'"`.
> Lúc này shell mới thật sự nội suy `$PORT`, còn `${PORT:-8000}` là phần dự phòng
> dùng 8000 nếu vì lý do gì biến chưa được set. Push commit lên, Railway build
> lại và lần này `/health` trả 200, `/ready` trả `{"status":"ready","redis":true}`.
> Điều mình rút ra là cổng bắt buộc phải đọc từ biến môi trường, và một biến chỉ
> được nội suy khi lệnh thực sự chạy qua một shell.
