# FiveM: CDN (nginx + Cloudflare) + Cutter/Proxy + สเกลไป 1,024 ผู้เล่น

คู่มือนี้เขียนจากสเปกเครื่องจริงของคุณ 3 เครื่อง และอ้างอิงค่าคอนฟิกจากเอกสารทางการของ Cfx.re
(ลิงก์อ้างอิงทั้งหมดอยู่ท้ายไฟล์)

---

## 0. สรุปคำตอบสั้น ๆ (อ่านก่อน)

| คำถามของคุณ | คำตอบตรง ๆ |
|---|---|
| ทำ CDN nginx + Cloudflare บน VPS ฿500 ได้ไหม | **ได้ และคุ้มมาก** — VPS 6 vCPU / 12 GB / 100 GB / 1 Gbps เหลือ ๆ สำหรับงาน CDN |
| ต้องย้ายการเชื่อมต่อ FXServer ใหม่ไหม | **ต้อง** — แก้ `server.cfg` บนเครื่อง i9 (Windows) เพิ่ม `fileserver_add`, `adhesive_cdnKey`, `sv_forceIndirectListing`, `sv_listingHostOverride`, `sv_proxyIPRanges`, `sv_endpoints` |
| Cutter ต้องใช้ VPS เพิ่มไหม | **ควรเพิ่มอีก 1 ตัว** — ถ้ายัด CDN + Cutter ไว้เครื่องเดียวที่ 1 Gbps จะชนเพดานตอน 1,024 คน |
| Cutter ช่วยอะไร | ซ่อน IP จริง / กัน DDoS / กันสแปม TCP — **แต่ไม่ช่วยเรื่องวาร์ป–ดีซิงค์เลย** |
| Cutter ส่งผลต่อผู้เล่นเยอะไหม | เพิ่ม ping ~0.3–1 ms (DC เดียวกัน), ~2–8 ms (คนละ DC ในไทย) และกลายเป็นจุดตายจุดเดียว (SPOF) |
| CDN ช่วยเรื่อง "โหลดแมพเร็ว" ไหม | **ช่วยมาก** — นี่คือจุดที่ CDN ช่วยได้จริง |
| CDN/Cutter ช่วยเรื่อง "ไม่วาร์ป ซิงค์ตรงกัน" ไหม | **ไม่ช่วย** — ปัญหาวาร์ปคือ CPU เธรดหลักของ FXServer + สคริปต์ + OneSync culling ต้องไปแก้ที่ข้อ 4 |

> ⚠️ **ข้อควรระวังที่สำคัญที่สุดของงานนี้:** จากภาพที่ส่งมา เครื่อง i9 อยู่ที่ **PTNK** ส่วน i5 และ VPS ฿500 อยู่ที่ **ReadyIDC**
> — คนละผู้ให้บริการ = คนละ DC. งาน CDN ไม่มีปัญหา (โหลดไฟล์ไม่แคร์ latency)
> แต่ถ้าเอา **Cutter** ไปไว้ ReadyIDC แล้ววิ่งเข้าเกมที่ PTNK ผู้เล่นทุกคนจะโดนบวก latency ของเส้นทาง PTNK↔ReadyIDC
> **วัดก่อนเสมอ** (ดูข้อ 3.6) ถ้าเกิน ~5 ms ให้หา VPS ที่อยู่ DC เดียวกับ i9 มาทำ Cutter แทน

---

## 1. สถาปัตยกรรม

### 1.1 ตอนนี้ (ทุกอย่างชี้ไปที่ Windows)

```
                       ┌──────────────────────────────┐
   ผู้เล่น ~700 คน ──▶ │  i9-13900K (Windows) @PTNK   │
   (เกม + โหลดไฟล์)    │  FXServer + HTTP /files/     │  ◀── IP จริงโดนเปิดโล่ง
                       └──────────────────────────────┘
                                    │
                       ┌──────────────────────────────┐
                       │  i5-12600K @ReadyIDC          │
                       │  pma-voice / Mumble           │
                       └──────────────────────────────┘
```

**ปัญหา:** เครื่องเกมต้องแบกทั้งการซิงค์ผู้เล่น *และ* การอัปโหลดไฟล์ให้คนที่เพิ่งเข้ามาโหลดแมพพร้อมกัน
เวลามีคนเข้าใหม่เยอะ ๆ ดิสก์ + NIC + เธรด HTTP จะไปแย่งทรัพยากรจากเธรดเกม → คนในเซิร์ฟกระตุก

### 1.2 เป้าหมาย

```
                    Cloudflare (DNS + TLS + WAF)
                              │
            ┌─────────────────┴─────────────────┐
            │                                   │
    connect.stl.xxx (proxied 🟠)        cdn.stl.xxx (DNS only ⚪)
    = ทาง "เข้าเซิร์ฟ" HTTPS 443        = ทาง "โหลดไฟล์" HTTPS 443
            │                                   │
            └───────────────┬───────────────────┘
                            ▼
              ┌───────────────────────────────┐
              │  VPS ฿500 (Linux)             │
              │  nginx  = Connect proxy + CDN │   ◀── 100 GB SSD ทำ cache
              │  6 vCPU / 12 GB / 1 Gbps      │
              └───────────────┬───────────────┘
                              │ (WireGuard หรือ firewall allowlist)
                              ▼
              ┌───────────────────────────────┐
              │  i9-13900K (Windows) @PTNK    │
              │  FXServer :30120 TCP/UDP      │   ◀── ไม่เปิดสู่สาธารณะแล้ว
              └───────────────┬───────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  i5-12600K @ReadyIDC          │
              │  pma-voice / Mumble           │   ◀── ห้ามลอด Cutter (ดูข้อ 4.8)
              └───────────────────────────────┘

              [ทางเลือก] VPS ตัวที่ 2 = Cutter (raw TCP/UDP 30120)  → ดูข้อ 3
```

### 1.3 บทบาทของแต่ละเครื่อง

| เครื่อง | สเปก | บทบาท | หมายเหตุ |
|---|---|---|---|
| i9-13900K (PTNK) | 24C/32T @5.8 GHz, 64 GB, M.2 250 GB | **FXServer** | ✅ CPU ดีที่สุดสำหรับ FiveM (เธรดหลักกินคอร์เดียว) <br> ⚠️ **M.2 250 GB น้อยไป** ถ้า assets เยอะ ควรเพิ่มดิสก์ |
| i5-12600K (ReadyIDC) | 10C/16T, 16 GB, NVMe 1 TB | **pma-voice / Mumble** | เหลือกำลังเยอะมาก — ใช้เป็น origin สำรอง / txAdmin / DB ได้ |
| VPS ฿500 (ReadyIDC) | 6 vCPU, 12 GB, 100 GB SSD, 1 Gbps | **CDN + Connect proxy** | 100 GB → ตั้ง cache ได้ ~60 GB |
| VPS ตัวที่ 2 (แนะนำ) | 2–4 vCPU, 4 GB, **1–10 Gbps**, DC เดียวกับ i9 | **Cutter** | เน้น "แบนด์วิดท์ + ที่ตั้ง" ไม่ต้องเน้น CPU |

---

## 2. ทำ CDN: nginx + Cloudflare บน VPS

### 2.1 เตรียม VPS (Ubuntu 22.04/24.04)

```bash
sudo apt update && sudo apt -y upgrade
sudo apt -y install nginx libnginx-mod-stream wireguard-tools ufw curl jq
sudo mkdir -p /var/cache/fivem
sudo chown -R www-data:www-data /var/cache/fivem
```

จูนเคอร์เนล (สำคัญตอนคนโหลดพร้อมกันเยอะ ๆ):

```bash
sudo tee /etc/sysctl.d/99-fivem-cdn.conf > /dev/null <<'EOF'
fs.file-max = 2097152
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 250000
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.ip_local_port_range = 1024 65535
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sudo sysctl --system
```

เพิ่มลิมิตไฟล์ให้ nginx:

```bash
sudo mkdir -p /etc/systemd/system/nginx.service.d
sudo tee /etc/systemd/system/nginx.service.d/limits.conf > /dev/null <<'EOF'
[Service]
LimitNOFILE=200000
EOF
sudo systemctl daemon-reload
```

ไฟร์วอลล์:

```bash
sudo ufw allow 22/tcp
sudo ufw allow 80,443/tcp
sudo ufw allow 51820/udp        # WireGuard (ถ้าใช้)
sudo ufw enable
```

### 2.2 เปิดทางให้ VPS คุยกับ FXServer ได้ (เลือก 1 แบบ)

#### แบบ A — Firewall allowlist (ง่ายที่สุด, latency ต่ำสุด, CPU ต่ำสุด)

บนเครื่อง Windows i9 รัน PowerShell (Run as Administrator):

```powershell
# ลบกฎเดิมที่เปิด 30120 ให้ทุกคน (ถ้ามี)
Get-NetFirewallRule -DisplayName "*30120*" | Remove-NetFirewallRule -ErrorAction SilentlyContinue

# อนุญาตเฉพาะ IP ของ VPS (และ Cutter ถ้ามี)
New-NetFirewallRule -DisplayName "FXServer TCP from proxy" -Direction Inbound -Protocol TCP `
  -LocalPort 30120 -RemoteAddress "<VPS_IP>","<CUTTER_IP>" -Action Allow

New-NetFirewallRule -DisplayName "FXServer UDP from proxy" -Direction Inbound -Protocol UDP `
  -LocalPort 30120 -RemoteAddress "<VPS_IP>","<CUTTER_IP>" -Action Allow
```

> ถ้ายังไม่ได้ทำ Cutter ให้ปล่อย UDP 30120 เปิดสาธารณะไว้ก่อน (เกมยังต้องวิ่งตรงเข้า i9)
> — ปิดได้ก็ต่อเมื่อมี Cutter แล้วเท่านั้น

#### แบบ B — WireGuard (ปลอดภัยกว่า, IP จริงไม่รั่วแน่นอน)

บน VPS:

```bash
wg genkey | sudo tee /etc/wireguard/priv.key | wg pubkey | sudo tee /etc/wireguard/pub.key
sudo chmod 600 /etc/wireguard/priv.key

sudo tee /etc/wireguard/wg0.conf > /dev/null <<'EOF'
[Interface]
Address    = 10.66.0.1/24
ListenPort = 51820
PrivateKey = <VPS_PRIVATE_KEY>

[Peer]
# FXServer (Windows i9)
PublicKey  = <WINDOWS_PUBLIC_KEY>
AllowedIPs = 10.66.0.2/32
PersistentKeepalive = 25
EOF

sudo systemctl enable --now wg-quick@wg0
```

บน Windows i9 (ติดตั้ง WireGuard for Windows → Add Tunnel → Add empty tunnel):

```ini
[Interface]
PrivateKey = <WINDOWS_PRIVATE_KEY>
Address    = 10.66.0.2/24
MTU        = 1420

[Peer]
PublicKey  = <VPS_PUBLIC_KEY>
Endpoint   = <VPS_PUBLIC_IP>:51820
AllowedIPs = 10.66.0.1/32
PersistentKeepalive = 25
```

ทดสอบจาก VPS: `ping 10.66.0.2` และ `curl -s http://10.66.0.2:30120/info.json | jq .vars`

> **เลือกอันไหนดี?** งาน **CDN (HTTP)** ใช้ WireGuard ได้สบาย
> แต่ถ้าจะยิง **เกม UDP 1,024 คน** ผ่าน WireGuard ต้องระวัง: การเข้ารหัสกิน CPU + MTU เล็กลง (เสี่ยง fragment)
> → สำหรับ Cutter แนะนำ **แบบ A** มากกว่า

### 2.3 DNS + Cloudflare

เพิ่ม 2 เรคคอร์ดที่ Cloudflare (สมมติโดเมน `stl.example`):

| ชื่อ | ชนิด | ค่า | Proxy status | ใช้ทำอะไร |
|---|---|---|---|---|
| `connect` | A | `<VPS_IP>` | 🟠 **Proxied** | ทางเข้าเซิร์ฟ (info.json / client / getEndpoints) — ทราฟฟิกน้อย ได้ WAF + ซ่อน IP |
| `cdn` | A | `<VPS_IP>` | ⚪ **DNS only** | โหลดไฟล์ resource — ทราฟฟิกหลัก TB/เดือน |

**ทำไม `cdn` ต้อง DNS only?**

1. Cloudflare แผนฟรี/Pro/Business **แคชไฟล์ได้สูงสุด 512 MB/ไฟล์** — assets ก้อนใหญ่จะไม่ถูกแคช วิ่งทะลุมาที่ VPS ทุกครั้งอยู่ดี
2. การดัน asset เกมหลาย TB/เดือนผ่าน CDN ฟรีของ Cloudflare สุ่มเสี่ยงผิดเงื่อนไขการใช้งาน (ข้อจำกัดเรื่องเนื้อหา non-HTML)
3. แคชจริง ๆ ทำที่ nginx บน VPS อยู่แล้ว (100 GB SSD) — ไม่ได้ต้องพึ่ง edge ของ CF

> ถ้าอยากให้ `cdn` อยู่หลัง Cloudflare จริง ๆ (เพื่อกัน DDoS L7) ให้พิจารณา **Cloudflare R2** (egress ฟรี) หรืออัปเกรดแผน — อย่าใช้แผนฟรีดัน TB

**ตั้งค่าเพิ่มใน Cloudflare (เฉพาะ `connect`):**

- SSL/TLS mode: **Full (Strict)**
- Always Use HTTPS: **On**
- Rocket Loader / Auto Minify / Email Obfuscation: **Off** (มันจะไปยุ่งกับ JSON)
- ⚠️ Cloudflare proxied รองรับเฉพาะพอร์ต HTTP มาตรฐาน (80/443/8443/2053/…) — ดังนั้น connect endpoint **ต้องเป็น 443**

### 2.4 ใบรับรอง TLS

- `connect.stl.example` (proxied) → ใช้ **Cloudflare Origin Certificate** ได้ (สร้างที่ SSL/TLS → Origin Server, อายุ 15 ปี)
- `cdn.stl.example` (DNS only) → **ต้องใช้ Let's Encrypt** เท่านั้น
  เพราะ Origin Certificate ของ Cloudflare ไม่ได้อยู่ใน trust store สาธารณะ — client FiveM จะปฏิเสธ

```bash
sudo apt -y install certbot python3-certbot-nginx
sudo certbot --nginx -d cdn.stl.example
# ต่ออายุอัตโนมัติ: systemctl status certbot.timer
```

วางใบรับรอง Origin ของ Cloudflare:

```bash
sudo mkdir -p /etc/ssl/cf
sudo nano /etc/ssl/cf/origin.pem      # วางเนื้อ certificate
sudo nano /etc/ssl/cf/origin.key      # วาง private key
sudo chmod 600 /etc/ssl/cf/origin.key
```

### 2.5 คอนฟิก nginx

**`/etc/nginx/nginx.conf`** — แก้ส่วนหัวและเพิ่ม `proxy_cache_path` ใน `http { }`:

```nginx
user  www-data;
worker_processes      auto;
worker_rlimit_nofile  200000;

events {
    worker_connections  65535;
    multi_accept        on;
    use                 epoll;
}

http {
    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    aio                 threads;
    directio            16m;
    keepalive_timeout   65;
    server_tokens       off;

    # ---- CDN cache ----
    # max_size ตั้ง ~60g จาก SSD 100 GB (เผื่อ OS + log)
    proxy_cache_path /var/cache/fivem
                     levels=1:2
                     keys_zone=assets:200m
                     max_size=60g
                     inactive=30d
                     use_temp_path=off;

    log_format asset '$remote_addr - [$time_local] "$request" $status '
                     '$body_bytes_sent $upstream_cache_status $request_time';

    gzip off;   # asset เกมบีบอัดมาแล้ว บีบซ้ำเปลืองซีพียูเปล่า

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
```

**`/etc/nginx/sites-available/fivem`**:

```nginx
upstream fxserver {
    # ใช้ 10.66.0.2 ถ้าต่อผ่าน WireGuard, หรือ IP จริงของ i9 ถ้าใช้ firewall allowlist
    server 10.66.0.2:30120 max_fails=3 fail_timeout=10s;
    keepalive 128;
}

# เอา IP จริงของผู้เล่นจาก Cloudflare (ถ้ามา proxied)
map $http_cf_connecting_ip $client_ip {
    default   $remote_addr;
    "~."      $http_cf_connecting_ip;
}

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name connect.stl.example cdn.stl.example;
    return 301 https://$host$request_uri;
}

# ─────────────────────────────────────────────
# 1) CONNECT ENDPOINT  (หลัง Cloudflare 🟠)
# ─────────────────────────────────────────────
server {
    # nginx >= 1.25.1 ใช้ 2 บรรทัดนี้ + `http2 on;`
    # nginx <  1.25.1 (Ubuntu 22.04 = 1.18, Ubuntu 24.04 = 1.24) ให้ใช้:
    #   listen 443 ssl http2;
    #   listen [::]:443 ssl http2;
    # แล้วลบบรรทัด `http2 on;` ออก   (เช็คเวอร์ชัน: nginx -v)
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name connect.stl.example;

    ssl_certificate     /etc/ssl/cf/origin.pem;
    ssl_certificate_key /etc/ssl/cf/origin.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_session_cache   shared:SSL:20m;
    ssl_session_timeout 1d;

    client_max_body_size 0;

    location / {
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $client_ip;
        proxy_set_header X-Forwarded-For   $client_ip;
        proxy_set_header X-Forwarded-Proto $scheme;

        # จำเป็น: ส่ง header auth ให้ครบ
        proxy_pass_request_headers on;
        # จำเป็น: ไม่งั้น deferral (คิว/loading screen) จะถูกตัดทันที
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_connect_timeout 10s;
        proxy_read_timeout    300s;
        proxy_send_timeout    300s;
        proxy_buffering       off;      # ให้ deferral สตรีมแบบเรียลไทม์

        proxy_pass http://fxserver;
    }

    # เผื่อมีคนเข้าทาง connect. โดยตรง ก็ให้แคชได้เหมือนกัน
    location /files/ {
        include /etc/nginx/snippets/fivem-cache.conf;
    }
}

# ─────────────────────────────────────────────
# 2) CDN ENDPOINT  (DNS only ⚪ — ทราฟฟิกหลัก)
# ─────────────────────────────────────────────
server {
    listen 443 ssl;          # ดูหมายเหตุเรื่อง http2 ในบล็อกด้านบน
    listen [::]:443 ssl;
    http2 on;
    server_name cdn.stl.example;

    ssl_certificate     /etc/letsencrypt/live/cdn.stl.example/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/cdn.stl.example/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_session_cache   shared:SSL:20m;

    access_log /var/log/nginx/fivem-cdn.log asset buffer=64k flush=5s;

    location /files/ {
        include /etc/nginx/snippets/fivem-cache.conf;
    }

    location = /cache-status {
        stub_status;
        allow 127.0.0.1;
        deny all;
    }

    location / { return 404; }
}
```

**`/etc/nginx/snippets/fivem-cache.conf`** (ใช้ร่วมกัน 2 ที่):

```nginx
proxy_pass http://fxserver$request_uri;

proxy_http_version 1.1;
proxy_set_header Connection "";
proxy_set_header Host $host;

proxy_cache               assets;
proxy_cache_key           $request_uri$is_args$args;
proxy_cache_valid         200 206 365d;
proxy_cache_valid         404 1m;
proxy_cache_lock          on;      # 100 คนขอไฟล์เดียวกัน → ไป origin แค่ครั้งเดียว
proxy_cache_lock_timeout  120s;
proxy_cache_lock_age      120s;
proxy_cache_revalidate    on;
proxy_cache_min_uses      1;
proxy_cache_background_update on;
proxy_cache_use_stale     error timeout updating http_500 http_502 http_503 http_504;

add_header X-Cache-Status $upstream_cache_status always;

# บัฟเฟอร์ใหญ่ขึ้นสำหรับไฟล์ asset ก้อนโต
proxy_buffering        on;
proxy_buffer_size      64k;
proxy_buffers          32 64k;
proxy_busy_buffers_size 256k;
proxy_read_timeout     300s;

# กันคนเดียวดูดจนเต็ม 1 Gbps  (≈15 MB/s ต่อ 1 connection หลังผ่านไป 50 MB)
# ปรับ/คอมเมนต์ออกได้ตามต้องการ
limit_rate_after 50m;
limit_rate       15m;
```

เปิดใช้งาน:

```bash
sudo mkdir -p /etc/nginx/snippets
sudo ln -sf /etc/nginx/sites-available/fivem /etc/nginx/sites-enabled/fivem
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

### 2.6 แก้ `server.cfg` บนเครื่อง i9 (Windows) — "เชื่อมต่อ FXServer ใหม่"

นี่คือส่วนที่ทำให้ FXServer เลิกเสิร์ฟไฟล์เอง แล้วบอก client ให้ไปโหลดจาก CDN แทน

```cfg
# ══════════════════════════════════════════════════════
#  ENDPOINTS
#  ⚠️ ต้องประกาศ UDP "ก่อน" TCP เสมอ ไม่งั้นค่าจะไม่ทำงานถูกต้อง
# ══════════════════════════════════════════════════════
endpoint_add_udp "0.0.0.0:30120"
endpoint_add_tcp "0.0.0.0:30120"

# ══════════════════════════════════════════════════════
#  PROXY / LISTING
# ══════════════════════════════════════════════════════

# ไม่ให้ server list ประกาศ IP จริงของเครื่อง i9
set sv_forceIndirectListing true

# ให้ backend ของ server list ไปถาม https://connect.stl.example/ แทน
set sv_listingHostOverride "connect.stl.example"

# IP ที่เชื่อถือได้ → ยอมรับ header X-Real-IP + ข้าม rate limiter
# ใส่ทั้ง IP ฝั่ง WireGuard และ IP สาธารณะของ VPS/Cutter (เว้นวรรคคั่น, CIDR)
set sv_proxyIPRanges "10.66.0.1/32 <VPS_IP>/32 <CUTTER_IP>/32"

# ปลายทางจริงที่ client จะยิง UDP เข้า
#   - ยังไม่มี Cutter  → ใส่ IP สาธารณะของ i9
#   - มี Cutter แล้ว   → ใส่ IP ของ Cutter
set sv_endpoints "<PUBLIC_GAME_IP>:30120"

# ══════════════════════════════════════════════════════
#  CDN  ← หัวใจของงานนี้
# ══════════════════════════════════════════════════════

# ⚠️ บังคับต้องมี! ปกติ FiveM จะ obfuscate ไฟล์ด้วย "คีย์รายคน"
#    ทำให้ URL ของทุกคนไม่ซ้ำกัน → nginx แคชไม่ได้เลยแม้แต่ไฟล์เดียว
#    ตั้งค่านี้ = ใช้คีย์กลางตัวเดียว → URL เหมือนกันทุกคน → แคชได้
#    สร้างคีย์: powershell -c "[guid]::NewGuid().ToString('N')"
set adhesive_cdnKey "เปลี่ยนเป็นสตริงสุ่มยาวๆของคุณ"

# ชี้ทุก resource (regex ".*") ไปโหลดที่ CDN
# ⚠️ ห้ามมี / ปิดท้าย
fileserver_add ".*" "https://cdn.stl.example/files"

# ══════════════════════════════════════════════════════
#  ความปลอดภัย / ทั่วไป
# ══════════════════════════════════════════════════════
set sv_endpointPrivacy true     # ไม่ให้ IP ผู้เล่นหลุดใน report สาธารณะ
set sv_scriptHookAllowed false
```

**คำสั่งที่ใช้ตรวจ/ถอนได้ในคอนโซล FXServer:**

```
fileserver_list              # ดูรายการ file server ที่ผูกไว้
fileserver_remove ".*"       # ถอนออก (เวลาจะกลับไปเสิร์ฟจากเครื่องเอง)
```

> 🔴 **`adhesive_cdnKey` = ห้ามเปลี่ยนพร่ำเพรื่อ**
> เปลี่ยนเมื่อไหร่ URL ของทุกไฟล์เปลี่ยนหมด → ผู้เล่นทุกคนต้องโหลดใหม่ทั้งเซิร์ฟ และแคช 60 GB บน VPS กลายเป็นขยะทันที

### 2.7 ทดสอบว่าใช้งานได้จริง

**1) เช็ค connect endpoint** — เปิดในเบราว์เซอร์ ต้องได้ผลตามนี้:

| URL | ผลที่ควรได้ |
|---|---|
| `https://connect.stl.example/info.json` | JSON ข้อมูลเซิร์ฟ |
| `https://connect.stl.example/players.json` | JSON รายชื่อผู้เล่น |
| `https://connect.stl.example/dynamic.json` | JSON จำนวนคน/แมพ |
| `https://connect.stl.example/client` | ข้อความ `/client is POST only` |

**2) เช็คว่าแคชทำงาน** — ยิงไฟล์เดียวกัน 2 ครั้ง ดูค่า `X-Cache-Status`:

```bash
# หา URL ไฟล์จริงจาก log ตอนมีคนเข้าเซิร์ฟ:
sudo tail -f /var/log/nginx/fivem-cdn.log

# แล้วทดสอบ:
URL="https://cdn.stl.example/files/<resource>/<file>?<hash>"
curl -sI "$URL" | grep -i x-cache-status   # ครั้งแรก → MISS
curl -sI "$URL" | grep -i x-cache-status   # ครั้งสอง → HIT   ✅
```

ถ้าครั้งที่สองยังเป็น `MISS` แสดงว่า **ยังไม่ได้ตั้ง `adhesive_cdnKey`** (URL ไม่ซ้ำกัน) — กลับไปดูข้อ 2.6

**3) ดูอัตรา HIT รวม:**

```bash
sudo awk '{print $NF}' /var/log/nginx/fivem-cdn.log | sort | uniq -c | sort -rn
# ควรเห็น HIT มากกว่า MISS อย่างชัดเจนหลังใช้งานไปสักพัก
```

**4) ดูขนาดแคช:**

```bash
du -sh /var/cache/fivem
```

**5) เข้าเซิร์ฟทดสอบจากในเกม:**

```
connect https://connect.stl.example/
```

> ⚠️ ต้องพิมพ์ URL เต็ม (มี `https://` และ `/` ปิดท้าย)
> คำสั่ง `connect` จะ **ไม่** ตีความชื่อโดเมนเปล่า ๆ เป็น URL ให้อัตโนมัติ
> ส่วนผู้เล่นที่กดเข้าจาก server list จะได้ `connectEndPoints` จาก `sv_listingHostOverride` เองอยู่แล้ว

### 2.8 🔴 ล้างแคช — เรื่องที่พลาดกันบ่อยที่สุด

> เอกสารทางการเตือนไว้ตรง ๆ ว่า:
> *"There's currently no cache invalidation logic based on hashes, so make sure to clear your proxy's cache before you modify/restart a resource."*

แปลว่า: **แก้ไฟล์ใน resource แล้วรีสตาร์ท → ต้องล้างแคชบน VPS ก่อนเสมอ**
ไม่งั้นผู้เล่นจะได้ไฟล์เวอร์ชันเก่าจากแคช → texture หาย / script error / โหลดค้าง

สร้างสคริปต์บน VPS:

```bash
sudo tee /usr/local/bin/fivem-cache-purge > /dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
CACHE_DIR=/var/cache/fivem

echo "[*] ขนาดแคชก่อนล้าง: $(du -sh "$CACHE_DIR" | cut -f1)"
systemctl stop nginx
find "$CACHE_DIR" -mindepth 1 -delete
systemctl start nginx
echo "[✓] ล้างแคชเรียบร้อย — nginx กลับมาแล้ว"
EOF
sudo chmod +x /usr/local/bin/fivem-cache-purge
```

ใช้งาน: `sudo fivem-cache-purge`

**ล้างเฉพาะบาง resource** (เร็วกว่า ไม่ต้องล้างทั้งก้อน):

```bash
# หา cache file ที่ key ตรงกับ resource นั้น แล้วลบ
sudo grep -rl "/files/<ชื่อ-resource>/" /var/cache/fivem | xargs -r sudo rm -f
```

**ทำให้อัตโนมัติ** — เพิ่มใน deploy script บน Windows (ใช้ `ssh` จาก Windows 10/11 ที่มี OpenSSH client ในตัว):

```powershell
# deploy.ps1 — รันทุกครั้งก่อนรีสตาร์ทเซิร์ฟ
ssh root@<VPS_IP> "fivem-cache-purge"
# ...แล้วค่อยสั่ง restart resource / restart server
```

### 2.9 จูนความเร็วโหลดเข้าเซิร์ฟให้เร็วขึ้นอีก

| สิ่งที่ทำ | ผลที่ได้ |
|---|---|
| ลดขนาด assets รวม (บีบ `.ytd` เป็น DXT, ตัด texture 4K ที่ไม่จำเป็น) | ตรงจุดที่สุด — 20 GB → 8 GB คือเร็วขึ้น 2.5 เท่าทันที |
| เอา `limit_rate` ออก ถ้าคนเข้าไม่พร้อมกันเยอะ | 1 คนโหลดได้เต็ม 1 Gbps |
| ตั้ง `limit_rate 15m` ไว้ ถ้าเปิดเซิร์ฟใหม่/มีคนแห่เข้าพร้อมกัน | ทุกคนได้เท่า ๆ กัน ไม่มีใครโดนอด |
| อุ่นแคชล่วงหน้า (warm cache) หลังอัปเดต | คนแรกที่เข้าไม่ต้องรอ origin |
| เปิด HTTP/2 (ทำแล้วในคอนฟิก) | ดาวน์โหลดขนานได้ดีขึ้น |

สคริปต์อุ่นแคชหลังอัปเดต resource — รันบน VPS:

```bash
sudo tee /usr/local/bin/fivem-cache-warm > /dev/null <<'EOF'
#!/usr/bin/env bash
# ดึงรายการไฟล์จาก log ของรอบก่อน แล้วขอซ้ำเพื่อเติมแคชล่วงหน้า
set -euo pipefail
LOG=/var/log/nginx/fivem-cdn.log
HOST=https://cdn.stl.example
awk '{print $6}' "$LOG" | tr -d '"' | grep '^/files/' | sort -u \
  | xargs -P 8 -I{} curl -s -o /dev/null "$HOST{}"
echo "[✓] อุ่นแคชเสร็จ"
EOF
sudo chmod +x /usr/local/bin/fivem-cache-warm
```

> ลำดับที่ถูกต้องเวลาอัปเดต: **ล้างแคช → รีสตาร์ท resource → อุ่นแคช → เปิดให้คนเข้า**

---

## 3. Cutter (Server Endpoint Proxy)

### 3.1 Cutter คืออะไรกันแน่

ในเอกสารทางการของ Cfx.re เรียกสิ่งนี้ว่า **"Server endpoint proxy"** — เครื่องกลางที่รับ **raw TCP/UDP พอร์ต 30120**
จากผู้เล่นแล้วส่งต่อเข้าเครื่องเกมจริง ที่ชุมชนไทยเรียก "Cutter" ก็คือตัวนี้แหละ (มันไป "ตัด/กรอง" ทราฟฟิกก่อนถึงเครื่องเกม)

ให้แยกให้ชัดว่ามันคนละตัวกับ CDN:

| | ทำหน้าที่ | โปรโตคอล | ทราฟฟิก |
|---|---|---|---|
| **Connect proxy** (ข้อ 2) | ทางเข้าเซิร์ฟ HTTPS 443 | TCP/HTTP | น้อยมาก |
| **CDN** (ข้อ 2) | เสิร์ฟไฟล์ `/files/` | TCP/HTTP | หนักตอนคนเข้าใหม่ |
| **Cutter** (ข้อ 3) | ตัวเกมจริง ๆ | **UDP + TCP 30120** | หนักตลอดเวลาที่คนออนไลน์ |

### 3.2 ต้องใช้ VPS เพิ่มไหม → **ควรเพิ่ม**

ลองคำนวณจริงที่ 1,024 คน (ค่าประมาณจากที่ชุมชนรายงาน ~50–150 kbit/s ต่อคนต่อทิศทาง):

```
ขาลง (server → ผู้เล่น)  1,024 × 150 kbit/s ≈ 154 Mbit/s
ขาขึ้น (ผู้เล่น → server) 1,024 × 100 kbit/s ≈ 103 Mbit/s

Cutter ต้องรับ+ส่ง ทั้งสองทิศ 2 รอบ (จากผู้เล่น → เข้า Cutter → ไป i9)
รวมทราฟฟิกผ่าน NIC ของ Cutter ≈ 257 Mbit/s (ปกติ)
ช่วงพีค (อีเวนต์รวมคนที่เดียว) ×3 ≈ 770 Mbit/s   ← ชน 1 Gbps แล้ว
```

ถ้าเอา **CDN (มีคนแห่โหลดไฟล์ 20 GB) + Cutter** ไว้เครื่องเดียวกันที่ 1 Gbps
→ ตอนเปิดเซิร์ฟหลังอัปเดต ทั้งสองงานจะแย่งแบนด์วิดท์กัน → **คนที่เล่นอยู่จะแลค เพราะคนใหม่กำลังโหลดไฟล์**

**สรุปแผนที่แนะนำ:**

| เครื่อง | บทบาท | สเปกที่ต้องการ |
|---|---|---|
| VPS ฿500 ที่มีอยู่ (ReadyIDC) | **CDN + Connect proxy** | ตามที่มี ✅ พอ |
| VPS ตัวที่ 2 (ใหม่) | **Cutter** | 2–4 vCPU / 4 GB / **แบนด์วิดท์เยอะ** / **DC เดียวกับ i9 (PTNK)** |

> ถ้างบจำกัดจริง ๆ ให้ทำ **CDN ก่อน** (ได้ผลชัดเจนต่อ "โหลดแมพเร็ว") แล้วค่อยทำ Cutter ทีหลัง

### 3.3 วิธี A — nftables DNAT (แนะนำสำหรับ 1,024 คน)

ทำงานในเคอร์เนล ไม่ต้องคัดลอกแพ็กเก็ตขึ้น userspace → **CPU แทบเป็นศูนย์ latency ต่ำสุด** เหมาะกับ UDP จำนวนมาก

```bash
sudo apt -y install nftables
sudo systemctl enable nftables

# เปิด IP forwarding + จูน conntrack
sudo tee /etc/sysctl.d/99-cutter.conf > /dev/null <<'EOF'
net.ipv4.ip_forward = 1
net.netfilter.nf_conntrack_max = 2097152
net.netfilter.nf_conntrack_udp_timeout = 60
net.netfilter.nf_conntrack_udp_timeout_stream = 180
net.core.netdev_max_backlog = 300000
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
EOF
sudo sysctl --system
```

```bash
> ℹ️ `nf_conntrack_*` จะตั้งได้ก็ต่อเมื่อโมดูลถูกโหลดแล้ว ถ้า `sysctl --system` ฟ้อง unknown key ให้รัน
> `sudo modprobe nf_conntrack` แล้วสั่งใหม่ (และเพิ่ม `nf_conntrack` ลง `/etc/modules-load.d/`)

```bash
sudo tee /etc/nftables.conf > /dev/null <<'EOF'
#!/usr/sbin/nft -f
flush ruleset

# ⚠️ แก้ IP นี้เป็น IP จริงของเครื่อง i9 (ทั้ง 4 จุดด้านล่าง)
#    ตั้งใจเขียนเป็นค่าตรง ๆ แทน define เพราะ nft บางเวอร์ชัน
#    ตีความ `dnat to $VAR:$VAR` ไม่ตรงกับที่คาด
table ip cutter {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        udp dport 30120 dnat to 203.0.113.10:30120
        tcp dport 30120 dnat to 203.0.113.10:30120
    }
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ip daddr 203.0.113.10 udp dport 30120 masquerade
        ip daddr 203.0.113.10 tcp dport 30120 masquerade
    }
}

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        ct state established,related accept
        iif lo accept
        tcp dport 22 accept
        icmp type echo-request limit rate 5/second accept
    }

    # ⚠️ แพกเก็ตที่โดน DNAT แล้วจะเดินผ่าน chain "forward" ไม่ใช่ "input"
    #    กฎกรอง/จำกัดอัตราของทราฟฟิกเกม จึงต้องอยู่ตรงนี้
    chain forward {
        type filter hook forward priority 0; policy drop;
        ct state established,related accept
        # จำกัดอัตราการเปิด connection TCP ใหม่ กันสแปม
        tcp dport 30120 ct state new limit rate 200/second burst 400 packets accept
        udp dport 30120 accept
    }
}
EOF
sudo nft -f /etc/nftables.conf
sudo nft list ruleset | head -40      # ตรวจว่าโหลดขึ้นจริง
```

> 🔴 **ทดสอบก่อนปิด SSH ทิ้ง** — `policy drop` ที่ chain input จะตัดทุกอย่างที่ไม่ได้ระบุไว้
> เปิด SSH session ที่สองค้างไว้ระหว่างทดสอบเสมอ

### 3.4 วิธี B — nginx stream (ง่ายกว่า จัดการง่ายกว่า)

> ⚠️ ต้องวางใน `/etc/nginx/nginx.conf` หรือ `/etc/nginx/conf.d/` **โดยตรง** — ใส่ใน `sites-enabled` ไม่ได้
> เพราะบล็อก `stream` อยู่ระดับเดียวกับ `http` ไม่ใช่ข้างใน

```bash
# บน Debian/Ubuntu แพ็กเกจ libnginx-mod-stream จะสร้างไฟล์โหลดโมดูลให้อยู่แล้ว
# ตรวจก่อนว่ามีหรือยัง — ถ้ามีแล้ว "ห้าม" สร้างซ้ำ (nginx จะฟ้อง module already loaded)
ls -1 /etc/nginx/modules-enabled/ | grep -i stream

# ถ้าไม่มี ค่อยติดตั้ง:
sudo apt -y install libnginx-mod-stream

# จากนั้นเพิ่มบล็อก stream { } ลงใน /etc/nginx/nginx.conf
# ⚠️ ต้องอยู่ "ระดับเดียวกับ" http { } ไม่ใช่ข้างใน
sudo nginx -t && sudo systemctl reload nginx
```

```nginx
stream {
    upstream fx_game {
        server 203.0.113.10:30120;     # IP จริงของ i9
    }

    # TCP (ใช้ตอน handshake / getConfiguration / ช่องเสริม)
    server {
        listen               30120;
        proxy_pass           fx_game;
        proxy_connect_timeout 5s;
        proxy_timeout        10m;
    }

    # UDP (ตัวเกมจริง — ENet)
    server {
        listen               30120 udp reuseport;
        proxy_pass           fx_game;
        proxy_timeout        5m;       # ห้ามสั้น ไม่งั้น session ผู้เล่นหลุด
        # ห้ามตั้ง proxy_responses — ค่าเริ่มต้นคือ "ไม่จำกัด" ซึ่งถูกแล้วสำหรับเกม
    }
}
```

เปรียบเทียบ:

| | nftables DNAT | nginx stream |
|---|---|---|
| CPU ที่ 1,024 คน | ต่ำมาก (kernel) | ปานกลาง–สูง (userspace copy) |
| Latency ที่เพิ่ม | น้อยที่สุด | +0.1–0.5 ms |
| ตั้งค่า/ดูแล | ต้องเข้าใจ NAT | ง่ายกว่า, log ดีกว่า |
| จำกัดอัตรา L7 | ไม่ได้ | ทำได้บ้าง |
| **แนะนำสำหรับคุณ** | ✅ | ใช้ตอนทดลอง/เซิร์ฟเล็ก |

### 3.5 `server.cfg` เมื่อมี Cutter

```cfg
# ให้ client ยิง UDP เข้าที่ Cutter แทน i9
set sv_endpoints "<CUTTER_IP>:30120"

# ⚠️ สำคัญมาก! เมื่อ NAT แล้ว ผู้เล่นทุกคนจะ "ดูเหมือนมาจาก IP เดียว" คือ Cutter
#    ถ้าไม่ประกาศ IP นี้เป็น proxy range → rate limiter จะเตะผู้เล่นทิ้งเป็นแถว
set sv_proxyIPRanges "<VPS_IP>/32 <CUTTER_IP>/32 10.66.0.1/32"

# เผื่อไว้อีกชั้น: ค่าเริ่มต้นจำกัด 16 connection ต่อ IP
# เป็นคำสั่งฝั่ง server ไม่ใช่ convar ที่ replicate ไปหา client → เขียนแบบไม่มี `set`
net_tcpConnLimit 1024
```

จากนั้นค่อยปิด UDP 30120 สาธารณะบน Windows (ให้เหลือเฉพาะจาก Cutter):

```powershell
Set-NetFirewallRule -DisplayName "FXServer UDP from proxy" -RemoteAddress "<CUTTER_IP>","<VPS_IP>"
```

### 3.6 ผลกระทบต่อผู้เล่น — วัดก่อนตัดสินใจ

รันบน **Cutter** ยิงไปที่ i9:

```bash
sudo apt -y install mtr-tiny
mtr -rwzc 100 <FX_IP>      # ดูค่า Avg / StDev / Loss
ping -c 100 <FX_IP> | tail -3
```

ตีความผล:

| RTT ที่วัดได้ | ผลต่อผู้เล่น | ตัดสินใจ |
|---|---|---|
| < 1 ms | แทบไม่รู้สึก | ✅ ทำได้เลย |
| 1–5 ms | ping เพิ่มขึ้นเล็กน้อย รับได้ | ✅ ทำได้ |
| 5–15 ms | เริ่มรู้สึกตอนยิงกัน/ขับรถเร็ว | ⚠️ หา VPS ที่ DC เดียวกับ i9 |
| > 15 ms หรือมี packet loss | แย่ชัดเจน ผู้เล่นจะบ่น | ❌ อย่าทำ |

**สรุปผลกระทบ (ทั้งด้านดีและเสีย):**

✅ ข้อดี
- IP จริงของเครื่อง i9 ไม่โผล่ที่ไหนอีกเลย (คู่กับ `sv_forceIndirectListing`)
- ทราฟฟิกโจมตี L3/L4 ไปตายที่ Cutter — เครื่องเกมไม่รู้เรื่อง
- เปลี่ยน/เพิ่ม Cutter ได้โดยผู้เล่นไม่ต้องเปลี่ยน connect string
- กัน TCP connection spam ก่อนถึงเครื่องเกม

❌ ข้อเสีย
- **+latency ทุกแพ็กเก็ตของทุกคน** (ตามตารางข้างบน)
- **จุดตายจุดเดียว** — Cutter ล่ม = ทั้งเซิร์ฟเข้าไม่ได้ ทั้งที่ i9 ยังทำงานปกติ
- แบนด์วิดท์ Cutter กลายเป็นเพดานใหม่ของทั้งเซิร์ฟ
- FXServer จะเห็น IP ผู้เล่นเป็น IP ของ Cutter หมด (ยังแบนได้ตามปกติ เพราะ FiveM ใช้ license/steam identifier ไม่ได้ใช้ IP)
- ถ้า Cutter ถูก DDoS จน DC null-route → เซิร์ฟล่มเหมือนกัน (ยกเว้นซื้อบริการ anti-DDoS จริงจัง)

### 3.7 สิ่งที่ Cutter **ไม่ได้** ช่วย (อย่าคาดหวังผิด)

| ความคาดหวัง | ความจริง |
|---|---|
| "ทำ Cutter แล้วจะไม่วาร์ป" | ❌ ไม่เกี่ยวกันเลย — วาร์ปคือเธรดหลัก FXServer ทำงานไม่ทัน |
| "ทำ Cutter แล้ว server tick ดีขึ้น" | ❌ ไม่ — งาน CPU ยังอยู่ที่ i9 เหมือนเดิม |
| "ทำ Cutter แล้วรับคนได้มากขึ้น" | ❌ ไม่ — เพดานคนอยู่ที่ CPU + สคริปต์ |
| "ทำ Cutter แล้วโหลดแมพเร็วขึ้น" | ❌ ไม่ — อันนั้นคืองานของ CDN (ข้อ 2) |
| "ทำ Cutter แล้วกัน DDoS ได้" | ✅ ได้ **เฉพาะ** ถ้า DC ของ Cutter มีระบบกรองที่ดีพอ |

> ถ้าเป้าหมายหลักคือ "กัน DDoS จริงจังที่ 1,024 คน" การซื้อบริการ anti-DDoS เฉพาะทางที่มี **filter เข้าใจโปรโตคอล FiveM/ENet**
> จะได้ผลกว่าการทำ Cutter เองบน VPS ธรรมดา เพราะ FiveM ใช้ UDP แพ็กเก็ตเล็ก ๆ ถี่ ๆ ซึ่ง scrubbing ทั่วไปมักเข้าใจผิดว่าเป็นการโจมตี แล้วเตะผู้เล่นจริงทิ้ง

---

## 4. จาก 700 → 1,024 คน: ซิงค์ตรง ไม่วาร์ป ไม่หน่วง

### 4.1 ต้องเข้าใจคอขวดตัวจริงก่อน

> **FXServer ประมวลผล state/sync ของทั้งเซิร์ฟบน "เธรดหลักเธรดเดียว"**
> ต่อให้ i9-13900K มี 24 คอร์ / 32 เธรด งานซิงค์ก็ยังเกาะอยู่คอร์เดียว
> — นี่คือเหตุผลที่ CPU ความถี่สูง (5.8 GHz) สำคัญกว่าจำนวนคอร์ และเป็นเหตุผลที่ **CDN/Cutter ช่วยเรื่องวาร์ปไม่ได้**

อาการที่คุณเจอ (วาร์ป / เห็นไม่ตรงกัน / ภาพหน่วง) มาจาก 3 อย่างนี้เท่านั้น:

| สาเหตุ | สัดส่วนที่มักเป็นตัวการ | แก้ที่ไหน |
|---|---|---|
| **เธรดหลักทำงานไม่ทัน** (tick > 20 ms) | ~60% | ลดจำนวน entity, ลด culling radius, optimize สคริปต์ |
| **สคริปต์เขียนแย่** (ลูปทุกเฟรม, event สแปม, DB query ช้า) | ~30% | โปรไฟล์แล้วแก้ทีละตัว |
| **แบนด์วิดท์/เส้นทางเน็ต** | ~10% | ข้อ 4.7 |

**ที่ 700 คนคุณเจอปัญหาแล้ว = เธรดหลักใกล้เต็มแล้ว**
การขึ้นไป 1,024 คน (+46%) จะไม่ใช่ +46% ของภาระ แต่มักจะแย่กว่านั้น เพราะคนกระจุกตัวกัน = entity ในระยะ culling ของแต่ละคนเพิ่มขึ้นแบบไม่เชิงเส้น

> **ให้วัดก่อนเสมอ (ข้อ 4.9) แล้วค่อยแก้ — อย่าเพิ่ม `sv_maxclients` ก่อนที่ tick time จะนิ่ง**

### 4.2 เช็คลิสต์ก่อน: สิทธิ์ใช้งาน slot

| slot ที่ต้องการ | สิ่งที่ต้องมี |
|---|---|
| ≤ 48 | ฟรี |
| ≤ 64 (OneSync) | Element Club **Argentum** |
| ≤ 128 (OneSync Infinity) | Element Club **Aurum** |
| **≤ 2048 (OneSync Infinity)** | Element Club **Platinum** ← คุณต้องใช้ระดับนี้ |

คุณรัน 700 คนอยู่แล้ว แสดงว่ามี Platinum อยู่ — แค่ยืนยันว่าบัญชี Cfx.re ที่ผูกกับเซิร์ฟยัง active

### 4.3 `server.cfg` สำหรับ 1,024 คน

```cfg
# ══════════════════════════════════════════════════════
#  ONESYNC / SLOTS
# ══════════════════════════════════════════════════════
set onesync on                  # = OneSync Infinity (จำเป็นเมื่อ > 64 คน)
sv_maxclients 1024              # ค่าที่รับได้ 1–2048

# ══════════════════════════════════════════════════════
#  CULLING — ตัวช่วยที่ได้ผลที่สุดสำหรับเซิร์ฟคนเยอะ
# ══════════════════════════════════════════════════════
# รถที่มีผู้เล่นนั่งอยู่ ก็โดน distance culling ด้วย
# (default: เปิดอยู่แล้วตั้งแต่ build ปี 2020 — ประกาศไว้ให้ชัด)
set onesync_distanceCullVehicles true

# entity ที่ไม่ได้รับ clone sync เกิน x วินาที → ย้ายเจ้าของไปคนใกล้ ๆ
set onesync_forceMigration true

# ⚠️ ตัวนี้ผลแรงที่สุด: ปิด population (NPC/รถ AI) ที่ฝั่ง server จัดการ
#    - ปิด  = โหลดเธรดหลักลดฮวบ แต่ NPC จะไม่ซิงค์ระหว่างผู้เล่น (ต่างคนต่างเห็น)
#    - เปิด = NPC ตรงกันทุกคน แต่กิน CPU มหาศาลที่ 1,000 คน
#    เซิร์ฟคนเยอะส่วนมากเลือก false แล้วใช้สคริปต์จัดการ NPC เฉพาะจุดแทน
set onesync_population false

# เวลา (ms) ก่อนบังคับย้ายเจ้าของ entity ถ้าเจ้าของเดิมหยุดส่ง sync
set onesync_migrateDataTimeout 10000

# ══════════════════════════════════════════════════════
#  ความปลอดภัย / เสถียรภาพ
# ══════════════════════════════════════════════════════
set sv_scriptHookAllowed false
set sv_endpointPrivacy true
set sv_enforceGameBuild 3407           # ล็อก build ให้ทุกคนเท่ากัน (เลือกตาม assets ที่ใช้)
set sv_tcpConnectionTimeoutSeconds 10
net_tcpConnLimit 1024                  # จำเป็นเมื่อมี proxy/Cutter (ค่าเริ่มต้น 16 ต่อ IP)

# เข้มขึ้นเรื่องตัวตน (ทางเลือก — ช่วยลด alt/บอทที่กินสล็อต)
# ⚠️ ตั้งเข้มไป ผู้เล่นจริงบางคนอาจเข้าไม่ได้ ทดสอบก่อน
# set sv_authMaxVariance 1
# set sv_authMinTrust 4

steam_webApiKey "<key>"                # ถ้าต้องการ steam identifier
```

### 4.4 ปรับ culling ให้ละเอียดขึ้นด้วย native (ได้ผลกว่า convar)

ค่าเริ่มต้นของ OneSync Infinity คือ **424 หน่วย** รอบตัวผู้เล่น
ที่ 1,024 คน ถ้าลดลงได้จะช่วยเธรดหลักเยอะ

> 🔴 **ข้อควรรู้ก่อนใช้:** เอกสาร native ของ Cfx.re ระบุว่า **culling natives ถูก deprecate แล้ว และมีบั๊กที่แก้ไม่ได้**
> (อาการที่รู้จัก: entity ที่อยู่ไกลอยู่แล้วแต่ใกล้ผู้เล่นคนอื่น จะ cull ไม่ถูกต้อง)
> → ใช้ได้ แต่ **ต้องทดสอบบนเซิร์ฟจริงและเฝ้าดูอาการ entity หาย/โผล่ช้า**
> ถ้าเจอปัญหาให้ถอยกลับไปใช้ค่า default (`0.0` = รีเซ็ต) แล้วไปเน้น routing bucket + optimize สคริปต์แทน:

```lua
-- server-side
-- ลดรัศมีที่ผู้เล่นแต่ละคนจะได้รับ state ของ entity
-- 424 → 300 = พื้นที่ลดลง ~50% = entity ที่ต้องซิงค์ลดลงมาก
AddEventHandler('playerJoining', function()
    local src = source
    SetPlayerCullingRadius(src, 300.0)
end)

-- entity บางประเภทให้เห็นไกลกว่าปกติ (เช่น เฮลิคอปเตอร์, รถฉุกเฉิน)
-- SetEntityDistanceCullingRadius(entity, 600.0)
```

**Routing bucket — แยกโลกเพื่อกระจายภาระ** (ได้ผลมากถ้าเซิร์ฟมี "โซน" ชัดเจน เช่น ในบ้าน/อินสแตนซ์/ภารกิจ):

```lua
-- ย้ายผู้เล่นเข้าโลกย่อย (คนใน bucket ต่างกัน = ไม่ต้องซิงค์กันเลย)
SetPlayerRoutingBucket(src, 42)

-- ปิด NPC ใน bucket นั้น
SetRoutingBucketPopulationEnabled(42, false)

-- 🔒 ล็อกไม่ให้ client สร้าง entity เอง = กัน cheat + ลดภาระ sync
--    'strict'   = client สร้าง entity ไม่ได้เลย (ปลอดภัยสุด ต้องให้ server สร้างให้)
--    'relaxed'  = สร้างได้บางส่วน
--    'inactive' = ค่าเริ่มต้น (ไม่ล็อก)
SetRoutingBucketEntityLockdownMode(0, 'relaxed')
```

> `strict` ช่วยได้มากทั้งเรื่อง performance และ cheat แต่ต้องแก้สคริปต์ให้สร้าง entity ฝั่ง server หมด
> — แนะนำเริ่มที่ `relaxed` ก่อน แล้วค่อยไล่ปรับสคริปต์เพื่อไป `strict`

### 4.5 เช็คลิสต์ optimize resource (จุดที่ได้ผลจริง เรียงตามความคุ้ม)

| # | สิ่งที่ต้องทำ | ผลที่ได้ |
|---|---|---|
| 1 | **โปรไฟล์หา resource ที่กิน tick สูงสุด** แล้วแก้ 5 ตัวแรก | มักได้ 50–70% ของปัญหาทั้งหมด |
| 2 | ลบ `while true do ... Wait(0) end` ที่ไม่จำเป็น เปลี่ยนเป็น event / `Wait(500)` | ลด CPU client + server ทันที |
| 3 | เลิกใช้ `TriggerClientEvent(-1, ...)` (ยิงหาทุกคน) → ยิงเฉพาะคนในระยะ | ที่ 1,024 คน อันนี้คือฆาตกร |
| 4 | ใช้ **state bag** แทน event สำหรับ state ที่เปลี่ยนบ่อย | ซิงค์เฉพาะคนที่มองเห็น |
| 5 | รวม resource เล็ก ๆ / ลบที่ไม่ใช้ | ทุก resource มี overhead คงที่ |
| 6 | DB: ใส่ index, ใช้ prepared statement, เลี่ยง query ใน loop | query ช้า = block เธรดหลัก |
| 7 | ลด `stream/` assets ที่ไม่ได้ใช้ + บีบ texture | โหลดเร็วขึ้น + VRAM client ลด |
| 8 | ปิด/ลด entity ที่ไม่จำเป็น (props ตกแต่งกลางแมพ) | ลดจำนวน entity ที่ต้องซิงค์ |

**คำสั่งโปรไฟล์ (พิมพ์ในคอนโซล FXServer):**

```
profiler record 500      # เก็บ 500 เฟรม
profiler save profile.json
profiler view            # เปิดดูใน client (F8 → resmon/profiler)
```

ฝั่ง client ให้ผู้เล่นทดสอบกด **F8** แล้วพิมพ์:

```
resmon 2                 # ดู CPU ms ของแต่ละ resource ฝั่ง client
netgraph                 # ดู packet loss / latency แบบเรียลไทม์
```

### 4.6 จูนเครื่อง Windows i9

```powershell
# 1) Power plan = High performance / Ultimate (ห้าม Balanced)
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c

# 2) ยกเว้นโฟลเดอร์เซิร์ฟจาก Windows Defender (สแกน = ดิสก์ช้า = tick กระตุก)
Add-MpPreference -ExclusionPath "D:\FXServer"
Add-MpPreference -ExclusionProcess "FXServer.exe"

# 3) ให้ priority สูง (รันหลังเซิร์ฟสตาร์ท)
Get-Process FXServer | ForEach-Object { $_.PriorityClass = 'High' }
```

**เรื่อง P-core / E-core ของ 13900K (สำคัญ):**
Windows Thread Director อาจย้ายเธรดหลักของ FXServer ไปอยู่บน **E-core** (ช้ากว่า P-core มาก) → tick กระตุกเป็นช่วง ๆ
ล็อกให้อยู่บน P-core (คอร์ 0–15 = P-core 8 ตัว แบบ hyperthread) ด้วยการตั้ง affinity:

```powershell
# 0xFFFF = ใช้เฉพาะ logical processor 0–15 (ปกติคือ P-core 8 ตัว × HT)
$p = Get-Process FXServer
$p.ProcessorAffinity = 0xFFFF
```

> ⚠️ **ตรวจก่อนตั้ง** — Task Manager → Performance → CPU → คลิกขวา → *Change graph to → Logical processors*
> แล้วดูว่าเครื่องคุณ enumerate P-core ไว้ที่ 0–15 จริงไหม (ลำดับต่างกันได้ตาม BIOS/ไมโครโค้ด)
> และ **วัด tick time เทียบก่อน/หลัง** — การจำกัด affinity ช่วยบางเซิร์ฟ แต่บางเซิร์ฟที่มี worker thread เยอะกลับแย่ลง

**อื่น ๆ:**
- ⚠️ **M.2 250 GB น้อยเกินไป** สำหรับเซิร์ฟที่มี assets เยอะ + cache + log → ควรเพิ่มดิสก์ อย่าให้เหลือ < 20%
- ปิด Windows Update auto-restart ในเวลาเซิร์ฟเปิด
- ปิด Nagle บน NIC (`TcpAckFrequency=1`, `TCPNoDelay=1` ใน registry ของ interface) — ช่วยลด jitter ของ TCP
- อย่ารัน MySQL/MariaDB บนเครื่องเดียวกับ FXServer ถ้าเลี่ยงได้ → **ย้ายไปเครื่อง i5** (มี NVMe 1 TB, 10C/16T ว่างอยู่เยอะ)

### 4.7 คำนวณแบนด์วิดท์ที่ 1,024 คน

```
ต่อผู้เล่น 1 คน (ค่าที่ชุมชนรายงาน — ต่างกันได้เยอะตามสคริปต์และความหนาแน่น):
  ขาลง  50–150 kbit/s   (สูงกว่านี้ตอนอยู่ในเมืองแออัด)
  ขาขึ้น 30–100 kbit/s
  เสียง  50–100 kbit/s ต่อคนที่กำลังพูด

ที่ 1,024 คน:
  เกม ขาลง   1,024 × 150 kbit/s  ≈ 154 Mbit/s
  เกม ขาขึ้น 1,024 × 100 kbit/s  ≈ 103 Mbit/s
  เสียง (สมมติ 15% พูดพร้อมกัน) 154 × 80 kbit/s ≈ 12 Mbit/s
  ─────────────────────────────────────────────
  รวมที่เครื่อง i9 ≈ 270 Mbit/s (ปกติ) / ~800 Mbit/s (พีค)
```

**ข้อสรุปสำคัญ:** เครื่อง i9 ที่ 1 Gbps **พอ** สำหรับตัวเกม
แต่ **ไม่พอ** ถ้าเครื่องเดียวกันต้องเสิร์ฟไฟล์ให้คนโหลดแมพด้วย → นี่คือเหตุผลที่ต้องแยก CDN ออกไป (ข้อ 2)

### 4.8 เครื่อง i5 / pma-voice

- เสียงเป็นทราฟฟิกแยกจากเกม — **อย่าให้วิ่งผ่าน Cutter** เพราะจะเพิ่ม latency ของเสียงโดยไม่จำเป็น
  ให้ผู้เล่นต่อตรงเข้าเครื่อง i5 (เปิดพอร์ตเสียงตรง หรือทำ Cutter แยกอีกตัวถ้าต้องซ่อน IP)
- ถ้าใช้ Mumble แยกเครื่อง ให้ตั้ง address ในสคริปต์ฝั่ง client:
  ```lua
  MumbleSetServerAddress('<IP_เครื่อง_i5>', 64738)
  ```
- เครื่อง i5 (10C/16T, 16 GB, NVMe 1 TB) **เหลือกำลังเยอะมาก** สำหรับแค่งานเสียง
  แนะนำให้ย้ายงานพวกนี้มาลงด้วย เพื่อปลดภาระเครื่อง i9:
  - **MariaDB / MySQL** — ดูข้อ 4.10 ก่อน (วัดแล้วพบว่า DB เล็กมาก ผลตอบแทนต่ำกว่าที่คาด)
  - txAdmin (แยกจากเครื่องเกม)
  - Discord bot / เว็บ / API
  - ⚠️ ระวัง: DB อยู่คนละ DC กับ i9 = ทุก query บวก latency ข้าม DC
    **วัด `ping` ระหว่าง i9 ↔ i5 ก่อน** ถ้าเกิน ~2 ms ให้เก็บ DB ไว้บน i9 ต่อ

### 4.9 การวัดผล — ต้องมีตัวเลข ไม่ใช่ความรู้สึก

**ตัวเลขที่ต้องจับตา:**

| ตัวชี้วัด | ค่าที่ควรได้ | อ่านจากไหน |
|---|---|---|
| **Server tick time** | < 10 ms ดี, 10–20 ms พอไหว, **> 20 ms = วาร์ปแน่นอน** | txAdmin → Performance chart |
| CPU เธรดหลัก | < 80% | Task Manager (ดูคอร์ที่พีค) |
| Packet loss ของผู้เล่น | < 0.5% | F8 → `netgraph` |
| CDN cache hit rate | > 90% | `awk` ที่ข้อ 2.7 |
| แบนด์วิดท์ i9 | < 60% ของ 1 Gbps | ดูที่ NIC |

**เกณฑ์ตัดสินใจก่อนเพิ่มสล็อต:**

```
ถ้า tick time ที่ 700 คน  <  10 ms  →  เพิ่มเป็น 850 ได้เลย แล้ววัดใหม่
ถ้า tick time ที่ 700 คน 10–20 ms  →  ต้อง optimize ก่อน (ข้อ 4.4–4.5) แล้วค่อยเพิ่มทีละ 100
ถ้า tick time ที่ 700 คน  >  20 ms  →  ❌ ห้ามเพิ่ม ไปแก้สคริปต์ก่อน
```

> **อย่าตั้ง `sv_maxclients 1024` ตั้งแต่วันแรก** — เพิ่มทีละ 100 คน วัดผลทุกครั้ง
> ถ้าเจอกำแพงที่ 800–900 คนแล้วแก้ไม่ตก ทางเลือกจริงจังคือ **แยกเซิร์ฟเป็นหลาย instance (shard)**
> เพราะ FXServer 1 instance ไม่สามารถขยายไปใช้หลายคอร์ได้

### 4.10 ย้าย MariaDB จาก i9 → i5 (ทีละขั้น)

#### 📊 ผลการวัดจริงของเซิร์ฟนี้ (อัปเดต 2026-09-06)

| สิ่งที่วัด | ค่าที่ได้ | แปลว่า |
|---|---|---|
| ping i9 → i5 (`103.253.74.66`, ReadyIDC) | 100/100 แพ็กเก็ต, **0% loss**<br>Min/Max/Avg = **0 ms** ทั้งหมด, TTL 123 | ✅ **เส้นทางสมบูรณ์แบบ** — ไม่มี spike แม้แต่ครั้งเดียวใน 100 ครั้ง ไม่มีปัญหาข้าม DC |
| ขนาด `happy_base` | **0.16 GB (163.5 MiB)** | ⚠️ **เล็กมาก** |
| ขนาด `stl_watchdog` | 0.01 GB | มีอีก 1 ฐานข้อมูลที่ต้องย้ายด้วย |

> 🔻 **ข้อสรุปที่เปลี่ยนไปจากคำแนะนำเดิม**
>
> ตอนที่ยังไม่รู้ขนาด DB ผมจัดให้การย้าย MariaDB เป็นงาน "คุ้มที่สุด" ของเครื่อง i5
> **พอวัดจริงแล้วไม่ใช่** — ฐานข้อมูลรวมกันแค่ ~165 MB ซึ่งหมายความว่า:
>
> - DB ทั้งก้อน**อยู่ใน RAM อยู่แล้ว** → ดิสก์ IO จาก MariaDB บน i9 แทบเป็นศูนย์
> - พื้นที่ที่จะปลดได้จาก M.2 250 GB คือ **165 MB** → ไม่ช่วยอะไรเลย
> - สิ่งที่ MariaDB กินบน i9 เหลือแค่ **CPU จากการประมวลผล query** ซึ่งการย้ายเครื่อง
>   **ไม่ได้ลดจำนวน query ลงแม้แต่ query เดียว** — แค่ย้ายที่ทำงาน แถมบวก latency เข้าไปอีก
>
> **ให้วัด 2 อย่างนี้ก่อนตัดสินใจย้าย** (ดูขั้นที่ 0 ต่อด้านล่าง):
> 1. `mysqld.exe` กิน CPU บน i9 กี่ % — ถ้าต่ำกว่า ~10% ของหนึ่งคอร์ **การย้ายแทบไม่ช่วยอะไร**
> 2. queries/sec เป็นเท่าไหร่ — ถ้าสูงผิดปกติ ปัญหาอยู่ที่**สคริปต์ยิง query เยอะเกิน** ไม่ใช่ที่ตัว DB
>    → การย้ายเครื่องจะทำให้**แย่ลง** เพราะทุก query บวก latency เพิ่ม
>
> **ลำดับความสำคัญที่ถูกต้องสำหรับเซิร์ฟนี้:**
> ข้อ 4.5 (optimize resource) → ขั้นที่ 9 ด้านล่าง (ลดจำนวน query) → **ค่อยพิจารณาย้าย DB ทีหลัง**
> การย้าย DB ยัง "ทำได้" และปลอดภัย (ping ผ่าน) แต่ไม่ใช่งานที่ควรทำก่อน

---

#### ขั้นที่ 0 — ตัดสินใจก่อน (ห้ามข้าม)

เครื่อง i9 อยู่ **PTNK** เครื่อง i5 อยู่ **ReadyIDC** = คนละ DC
ทุก query จะต้องวิ่งข้าม DC ไป-กลับ **ทุกครั้ง** ดังนั้นต้องวัดก่อนว่าคุ้มไหม

```powershell
# รันบนเครื่อง i9
ping -n 100 <IP_เครื่อง_i5>
# ดูค่า Average และดูว่ามี loss ไหม
```

```bash
# ละเอียดกว่า — รันบน i5 ยิงไป i9
mtr -rwzc 200 <IP_เครื่อง_i9>
```

| ping i9 ↔ i5 | ตัดสินใจ |
|---|---|
| **< 1 ms** | ✅ ย้ายได้เลย ← **วัดจริงแล้วได้ค่านี้** (Min/Max/Avg = 0 ms, 0% loss จาก 100 แพ็กเก็ต) |
| **1–3 ms** | ✅ ย้ายได้ ถ้าสคริปต์ไม่ยิง query ซ้ำซ้อน (N+1) |
| **3–10 ms** | ⚠️ ย้ายเฉพาะเมื่อพิสูจน์แล้วว่า CPU/ดิสก์ของ i9 เป็นคอขวดจริง — และต้อง optimize query ก่อน |
| **> 10 ms หรือมี packet loss** | ❌ **อย่าย้าย** — เก็บ DB ไว้บน i9 แล้วไปแก้ที่อื่นแทน |

**ทำไมต้องซีเรียสขนาดนี้:** query บนเครื่องเดียวกันใช้เวลาไป-กลับ ~0.2–0.5 ms
ถ้าข้าม DC ที่ 3 ms = **ทุก query ช้าลงราว 10 เท่า** สคริปต์ที่ยิง 5 query ต่อการกระทำ 1 ครั้ง
จะจาก ~2 ms กลายเป็น ~17 ms — ผู้เล่นเริ่มรู้สึกได้

**วัด CPU ที่ MariaDB กินจริงบน i9 ก่อน** — นี่คือตัวเลขที่บอกว่าย้ายแล้วจะได้อะไรคืนมา:

```powershell
# ดูค่าเฉลี่ย 60 วินาทีของ mysqld (หารด้วยจำนวน logical core เพื่อได้ % ของทั้งเครื่อง)
Get-Counter '\Process(mysqld)\% Processor Time' -SampleInterval 5 -MaxSamples 12 |
  ForEach-Object { $_.CounterSamples[0].CookedValue } |
  Measure-Object -Average -Maximum
```

| ผลที่ได้ (% ของ 1 คอร์) | แปลว่า |
|---|---|
| < 10% | ย้ายแล้วได้คืนแทบไม่มี — **อย่าเพิ่งย้าย** ไปทำข้อ 4.5 ก่อน |
| 10–50% | ย้ายแล้วพอได้ประโยชน์ |
| > 50% | มี query problem — **ย้ายไม่ช่วย** ต้องไปแก้ที่สคริปต์ (ขั้นที่ 9) |

**วัดปริมาณ query จริงก่อน** (รันบน DB ปัจจุบัน):

```sql
SHOW GLOBAL STATUS LIKE 'Questions';
-- รอ 60 วินาที แล้วรันซ้ำ → (ค่าใหม่ - ค่าเก่า) / 60 = queries/sec
```

แล้วคำนวณจำนวน connection ที่ต้องใช้ (กฎของ Little):

```
connection ที่ต้องมี ≈ queries/sec × เวลาต่อ query (วินาที)

ตัวอย่าง: 300 QPS × 0.0035 วิ (3.5 ms) ≈ 1.05
→ ตั้ง connectionLimit = 16 ก็เหลือเฟือแล้ว
```

**ได้อะไร / เสียอะไร**

| ✅ ได้ | ❌ เสีย |
|---|---|
| i9 ไม่ต้องแบ่ง CPU + ดิสก์ IO ให้ DB → tick time นิ่งขึ้น | ทุก query บวก latency ข้าม DC |
| ปลดพื้นที่บน M.2 250 GB ที่ตึงอยู่แล้ว | i5 ล่ม = ทั้งเซิร์ฟล่ม (จุดพึ่งพาเพิ่ม) |
| i5 มี NVMe 1 TB — เหมาะกับ DB มากกว่า | ต้องตั้งระบบสำรองข้อมูลใหม่ |
| แยก backup / restore ได้โดยไม่แตะเครื่องเกม | ต้องดูแลอีกเครื่อง |

> 🔴 **ห้ามเปิดพอร์ต 3306 ออกอินเทอร์เน็ตเด็ดขาด** ไม่ว่ากรณีใด — ต้องผ่าน WireGuard เท่านั้น (ขั้นที่ 2)

---

#### ขั้นที่ 1 — ติดตั้ง MariaDB บน i5

**ถ้า i5 เป็น Linux (แนะนำ):**

```bash
sudo apt update
sudo apt -y install mariadb-server mariadb-client
mariadb --version

sudo mariadb-secure-installation
#   Set root password?          → Y (ตั้งรหัสยาว ๆ)
#   Remove anonymous users?     → Y
#   Disallow root login remotely? → Y
#   Remove test database?       → Y
#   Reload privilege tables?    → Y
```

**ถ้า i5 เป็น Windows:**
โหลด MariaDB Server จาก mariadb.org → ติดตั้งแบบ Service → ตั้ง root password
ไฟล์คอนฟิกอยู่ที่ `C:\Program Files\MariaDB 11.4\data\my.ini` (เนื้อหาส่วน `[mysqld]` ใช้เหมือนกัน)
ส่วนคำสั่ง `systemctl` ให้เปลี่ยนเป็น `net stop MariaDB` / `net start MariaDB`

> ให้ **เวอร์ชันบน i5 เท่ากับหรือใหม่กว่า** เวอร์ชันที่ใช้อยู่บน i9 (เช็คด้วย `SELECT VERSION();`)
> ถ้าใหม่กว่ามาก ๆ (ข้าม 2 major) ให้ทดสอบ import บนสำเนาก่อน

---

#### ขั้นที่ 2 — WireGuard ระหว่าง i9 ↔ i5

โปรโตคอล MySQL ส่งข้อมูลแบบไม่เข้ารหัสโดยดีฟอลต์ — **ห้ามวิ่งบนอินเทอร์เน็ตเปลือย ๆ**

ใช้ผังเดิมจากข้อ 2.2 แล้วเพิ่มเครื่อง i5 เป็น `10.66.0.3`
(i9 กับ i5 มี public IP ทั้งคู่ → ต่อตรงหากันได้เลย ไม่ต้องอ้อมผ่าน VPS)

**บน i5 (Linux)** — `/etc/wireguard/wg0.conf`:

```ini
[Interface]
Address    = 10.66.0.3/24
ListenPort = 51820
PrivateKey = <I5_PRIVATE_KEY>

[Peer]
# FXServer (Windows i9)
PublicKey  = <WINDOWS_PUBLIC_KEY>
Endpoint   = <IP_สาธารณะ_i9>:51820
AllowedIPs = 10.66.0.2/32
PersistentKeepalive = 25
```

```bash
sudo ufw allow 51820/udp
sudo systemctl enable --now wg-quick@wg0
```

**บน i9 (Windows)** — เพิ่ม `[Peer]` บล็อกที่สองในทันเนลเดิม (ไม่ต้องสร้างทันเนลใหม่):

```ini
[Peer]
# MariaDB (i5)
PublicKey  = <I5_PUBLIC_KEY>
Endpoint   = <IP_สาธารณะ_i5>:51820
AllowedIPs = 10.66.0.3/32
PersistentKeepalive = 25
```

ทดสอบ: จาก i9 รัน `ping 10.66.0.3` → ต้องตอบ
แล้ววัด latency ผ่านทันเนลอีกรอบ (WireGuard บวกอีกราว 0.1–0.3 ms)

---

#### ขั้นที่ 3 — คอนฟิก MariaDB บน i5

`/etc/mysql/mariadb.conf.d/60-fivem.cnf`:

```ini
[mysqld]
# ── เครือข่าย ──────────────────────────────────
# ฟังเฉพาะ IP ฝั่ง WireGuard เท่านั้น (อินเทอร์เน็ตเข้าไม่ถึง)
bind-address    = 10.66.0.3

# ⚠️ สำคัญมากสำหรับ DB ที่อยู่คนละเครื่อง
# ปิด reverse DNS lookup ตอน client เชื่อมต่อ — ไม่ปิดจะค้างหลายวินาทีต่อ connection
skip-name-resolve

max_connections     = 200
thread_cache_size   = 64
wait_timeout        = 600
interactive_timeout = 600

# ── InnoDB ─────────────────────────────────────
# กฎ: ตั้งเท่ากับ (ขนาด DB × 1.5) ปัดขึ้น — ไม่ใช่ % ของ RAM
# DB ของคุณรวมกัน ~165 MB → 1G เหลือเฟือแล้ว และเหลือ RAM ให้งานเสียงอีก 15 GB
# (ตั้ง 8G ไม่ได้ทำให้เร็วขึ้นเลยเมื่อ DB เล็กกว่านั้น — แค่จอง RAM ทิ้งไว้เปล่า ๆ)
innodb_buffer_pool_size      = 1G
innodb_buffer_pool_instances = 1
innodb_log_file_size         = 256M
innodb_flush_method          = O_DIRECT

# ⚠️ trade-off: ค่า 2 เร็วกว่ามาก แต่ถ้าไฟดับกะทันหันอาจเสีย transaction ≤ 1 วินาที
#    เซิร์ฟ FiveM ส่วนใหญ่ยอมรับได้ — ถ้ารับไม่ได้ (ระบบเงิน/ธนาคาร) ให้ใช้ 1
innodb_flush_log_at_trx_commit = 2

# NVMe — ค่าดีฟอลต์ตั้งไว้สำหรับ HDD ซึ่งต่ำเกินไปมาก
innodb_io_capacity      = 4000
innodb_io_capacity_max  = 10000
innodb_read_io_threads  = 8
innodb_write_io_threads = 8

# ── Slow query log — ไว้ตามหาสคริปต์ที่ถล่ม DB ──
slow_query_log      = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time     = 0.15
log_queries_not_using_indexes = 1

# ── Charset ────────────────────────────────────
character-set-server = utf8mb4
collation-server     = utf8mb4_unicode_ci
```

> ⚠️ **ปัญหาที่เจอบ่อย:** MariaDB สตาร์ตก่อน WireGuard ตอนบูต → bind ที่ `10.66.0.3` ไม่สำเร็จ → service ล่ม
> แก้ด้วยการบอก systemd ให้รอ wg0 ก่อน:

```bash
sudo mkdir -p /etc/systemd/system/mariadb.service.d
sudo tee /etc/systemd/system/mariadb.service.d/wait-wg.conf > /dev/null <<'EOF'
[Unit]
After=wg-quick@wg0.service
Requires=wg-quick@wg0.service
EOF
sudo systemctl daemon-reload
sudo systemctl restart mariadb
sudo systemctl status mariadb --no-pager
```

---

#### ขั้นที่ 4 — สร้างฐานข้อมูลและผู้ใช้

```bash
sudo mariadb
```

> ⚠️ เซิร์ฟนี้มี **2 ฐานข้อมูล**: `happy_base` (หลัก) และ `stl_watchdog` — ต้องย้ายทั้งคู่

```sql
CREATE DATABASE IF NOT EXISTS happy_base
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS stl_watchdog
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- ⚠️ ผูกสิทธิ์กับ "IP ฝั่ง WireGuard ของ i9" เท่านั้น ห้ามใช้ '%'
CREATE USER 'fivem'@'10.66.0.2' IDENTIFIED BY 'รหัสผ่านสุ่มยาว32ตัว';
GRANT ALL PRIVILEGES ON happy_base.*   TO 'fivem'@'10.66.0.2';
GRANT ALL PRIVILEGES ON stl_watchdog.* TO 'fivem'@'10.66.0.2';
FLUSH PRIVILEGES;

-- ตรวจว่าไม่มี user ที่เปิดกว้างหลงเหลือ
SELECT user, host FROM mysql.user;
```

สร้างรหัสผ่านสุ่ม 32 ตัว — บน Windows: `powershell -c "[guid]::NewGuid().ToString('N')"`
บน Linux: `openssl rand -hex 16`

> เลี่ยงอักขระ `@ : / # ?` ในรหัสผ่าน จะได้ใช้ connection string รูปแบบ URI ได้สะดวก (ดูขั้นที่ 6)

---

#### ขั้นที่ 5 — ย้ายข้อมูล

##### แผน A — มีช่วงปิดปรับปรุง (แนะนำ, ตรงไปตรงมา)

**1) ประกาศปิดปรับปรุง** — เผื่อเวลาไว้ 30–60 นาที (งานจริงมักใช้ 5–15 นาที)

**2) หยุด FXServer** ให้สนิท (สำคัญ — ไม่งั้นข้อมูลระหว่าง dump จะไม่ตรงกัน)

**3) Dump บน i9** (PowerShell / cmd)
— ปรับเลขเวอร์ชันในพาธให้ตรงกับที่ติดตั้งจริง (ดูในโฟลเดอร์ `C:\Program Files\`):

```
"C:\Program Files\MariaDB 11.4\bin\mariadb-dump.exe" -u root -p ^
  --single-transaction --routines --triggers --events ^
  --hex-blob --default-character-set=utf8mb4 ^
  --databases happy_base stl_watchdog > D:\backup\fivem_all.sql
```

> `--databases` จะใส่คำสั่ง `CREATE DATABASE` / `USE` ให้ในไฟล์เอง → import ทีเดียวได้ทั้งสองฐาน

| ตัวเลือก | ทำไมต้องมี |
|---|---|
| `--single-transaction` | dump แบบไม่ล็อกตาราง (ใช้ได้กับ InnoDB) |
| `--routines --triggers --events` | เอา stored procedure / trigger / scheduled event ไปด้วย — **ลืมบ่อยมาก** |
| `--hex-blob` | กัน binary data เพี้ยน |
| `--default-character-set=utf8mb4` | กันภาษาไทยกลายเป็น `???` |

**4) บีบอัดแล้วโอนผ่าน WireGuard:**

```powershell
# บน i9
tar -czf D:\backup\happy_base.sql.gz -C D:\backup happy_base.sql
scp D:\backup\happy_base.sql.gz user@10.66.0.3:/tmp/
```

**5) Import บน i5:**

```bash
cd /tmp
gunzip happy_base.sql.gz
time sudo mariadb --default-character-set=utf8mb4 happy_base < happy_base.sql
```

> ⏱️ ประมาณการบน NVMe: ~1–3 นาทีต่อข้อมูล 1 GB
> **เซิร์ฟนี้มีแค่ ~165 MB → dump + โอน + import รวมกันไม่เกิน 1–2 นาที**
> หน้าต่างปิดปรับปรุงจริงจึงสั้นมาก (เผื่อไว้ 15 นาทีก็เหลือเฟือ) → **ใช้แผน A ไปเลย ไม่ต้องคิดถึงแผน B**

**6) ตรวจสอบว่าข้อมูลครบ** — เทียบ 2 เครื่อง:

```sql
-- รันทั้งบน i9 (ตัวเก่า) และ i5 (ตัวใหม่) แล้วเทียบผลให้ตรงกัน
SELECT COUNT(*) AS total_tables
FROM information_schema.tables WHERE table_schema = 'happy_base';

-- นับจำนวนแถวจริงของตารางสำคัญ (อย่าใช้ table_rows ของ information_schema
-- เพราะ InnoDB ให้ค่าประมาณ ไม่แม่นยำ)
SELECT COUNT(*) FROM users;
SELECT COUNT(*) FROM owned_vehicles;
SELECT COUNT(*) FROM user_inventory;

-- เช็คภาษาไทยไม่เพี้ยน
SELECT name FROM users WHERE name REGEXP '[ก-๙]' LIMIT 5;
```

**7) แก้ connection string** (ขั้นที่ 6) → **8) เปิดเซิร์ฟ** → เฝ้าดู console

##### แผน B — เกือบไม่มี downtime (สำหรับ DB ใหญ่มาก — **เซิร์ฟนี้ไม่ต้องใช้**)

ถ้า DB ใหญ่จน import กินเวลาเกินหน้าต่างที่รับได้ ให้ทำ replication แทน:

1. ตั้ง i9 เป็น **master** (เปิด binlog, `server_id=1`) — ต้องรีสตาร์ท MariaDB หนึ่งครั้ง
2. dump พร้อมตำแหน่ง binlog: เพิ่ม `--master-data=2` ตอน dump (เซิร์ฟยังเปิดอยู่ได้)
3. import บน i5 แล้วตั้ง `CHANGE MASTER TO ...` ตามตำแหน่งที่ได้ → `START SLAVE`
4. รอจน `SHOW SLAVE STATUS\G` แสดง `Seconds_Behind_Master: 0`
5. ปิดเซิร์ฟ **แค่ 1–2 นาที** → เช็คว่า replica ตามทัน → `STOP SLAVE; RESET SLAVE ALL;` → เปลี่ยน connection string → เปิดเซิร์ฟ

> แผน B ซับซ้อนกว่ามากและมีจุดพลาดเยอะ — **ใช้แผน A ก่อนเสมอ** ถ้าหน้าต่างปิดปรับปรุง 30 นาทีรับได้

---

#### ขั้นที่ 6 — แก้ `server.cfg` ให้ oxmysql ชี้ไป i5

```cfg
# ⚠️ ต้องตั้ง "ก่อน" บรรทัด ensure/start ของ resource อื่นทั้งหมด
set mysql_connection_string "mysql://fivem:PASSWORD@10.66.0.3:3306/happy_base?charset=utf8mb4&connectionLimit=16&connectTimeout=10000"

# แจ้งเตือน query ที่ช้ากว่า 150 ms — ไว้ตามหาสคริปต์ที่ถล่ม DB
set mysql_slow_query_warning 150

ensure oxmysql
# ...resource อื่น ๆ ตามหลัง
```

> 🔴 **กับดักที่เจอบ่อยที่สุด:** ถ้ารหัสผ่านมีอักขระพิเศษ (`@` `:` `/` `#` `?`) รูปแบบ URI **จะพัง**
> ให้เปลี่ยนไปใช้รูปแบบ semicolon แทน ซึ่ง oxmysql รองรับเหมือนกัน:

```cfg
set mysql_connection_string "user=fivem;password=P@ss:w0rd#1;host=10.66.0.3;port=3306;database=happy_base;charset=utf8mb4;connectionLimit=16"
```

**ค่า `connectionLimit`:** ใช้สูตรกฎของ Little จากขั้นที่ 0
ส่วนใหญ่ **16 พอ** — ตั้งสูงเกินไปไม่ได้ทำให้เร็วขึ้น แต่จะไปกิน `max_connections` ของ DB แทน

---

#### ขั้นที่ 7 — ทดสอบ และแผนถอยกลับ

**ทดสอบการเชื่อมต่อก่อนเปิดเซิร์ฟ** (จาก i9):

```powershell
"C:\Program Files\MariaDB 11.4\bin\mariadb.exe" -h 10.66.0.3 -u fivem -p ^
  -e "SELECT VERSION(), NOW(), COUNT(*) FROM users;" happy_base
```

**ตอนเปิดเซิร์ฟ ให้ดู console ของ oxmysql** — ต้องขึ้นว่าเชื่อมต่อสำเร็จ และ **ต้องไม่มี** `ETIMEDOUT` / `ECONNREFUSED`

**เฝ้าดู 24 ชั่วโมงแรก:**

```bash
# บน i5 — query ที่ช้า
sudo tail -f /var/log/mysql/slow.log

# จำนวน connection ที่ใช้จริง
sudo mariadb -e "SHOW STATUS LIKE 'Threads_connected'; SHOW STATUS LIKE 'Max_used_connections';"
```

พร้อมกับดู **tick time ใน txAdmin** เทียบก่อน/หลัง — นี่คือตัวชี้วัดว่าย้ายแล้วคุ้มจริงไหม

**แผนถอยกลับ (rollback) — เตรียมไว้เสมอ:**

1. เปลี่ยน `mysql_connection_string` กลับเป็น `mysql://...@localhost:3306/...`
2. รีสตาร์ทเซิร์ฟ
3. ⚠️ **ห้ามลบ DB เดิมบน i9 ทันที** — เก็บไว้อย่างน้อย **1–2 สัปดาห์**
   (แต่จำไว้ว่าข้อมูลที่เขียนลง i5 ไปแล้วจะไม่อยู่ในตัวเก่า — ถ้า rollback หลังเปิดเซิร์ฟไปแล้วต้อง dump กลับมาจาก i5)

---

#### ขั้นที่ 8 — ตั้งระบบสำรองข้อมูล (DB ย้ายบ้านแล้ว backup เดิมใช้ไม่ได้)

```bash
sudo apt -y install mariadb-backup
sudo mkdir -p /var/backups/mariadb

sudo tee /usr/local/bin/db-backup > /dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DEST=/var/backups/mariadb
STAMP=$(date +%F_%H%M)
mariadb-dump --single-transaction --routines --triggers --events \
  --hex-blob --default-character-set=utf8mb4 happy_base \
  | gzip > "$DEST/happy_base_$STAMP.sql.gz"
# เก็บย้อนหลัง 14 วัน
find "$DEST" -name '*.sql.gz' -mtime +14 -delete
echo "[✓] backup: $DEST/happy_base_$STAMP.sql.gz"
EOF
sudo chmod +x /usr/local/bin/db-backup

# ทุกวันตี 5
echo "0 5 * * * root /usr/local/bin/db-backup >> /var/log/db-backup.log 2>&1" \
  | sudo tee /etc/cron.d/db-backup
```

> 🔴 **backup ที่ไม่เคยลอง restore = ไม่มี backup** — ทดลอง restore ลง DB ชื่ออื่นอย่างน้อยเดือนละครั้ง

---

#### ขั้นที่ 9 — ลดจำนวน query (สำคัญกว่าการเร่ง DB)

เมื่อ DB อยู่คนละเครื่อง สิ่งที่แพงคือ **จำนวนครั้งที่วิ่งไป-กลับ** ไม่ใช่ความเร็วของ DB
ดังนั้นการลด query 100 ครั้งให้เหลือ 1 ครั้ง คุ้มกว่าการเร่ง DB ให้เร็วขึ้น 2 เท่า

```lua
-- ❌ N+1 — 100 ผู้เล่น = 100 round trip = 350 ms ที่ 3.5 ms ต่อครั้ง
for _, id in ipairs(identifiers) do
    local row = MySQL.single.await('SELECT * FROM users WHERE identifier = ?', { id })
end

-- ✅ รวบเป็น query เดียว = 1 round trip
-- string.rep(s, n, sep) ของ Lua 5.4 สร้าง "?,?,?" ให้เลย
local placeholders = ('?'):rep(#identifiers, ',')
local rows = MySQL.query.await(
    ('SELECT * FROM users WHERE identifier IN (%s)'):format(placeholders),
    identifiers
)

-- ✅ เขียนหลายแถวรวดเดียวด้วย prepare
MySQL.prepare.await('UPDATE users SET money = ? WHERE identifier = ?', batchedRows)

-- ✅ หลาย statement ที่ต้องสำเร็จพร้อมกัน → transaction (1 round trip)
MySQL.transaction.await({
    { query = 'UPDATE users SET money = money - ? WHERE identifier = ?', values = { amount, from } },
    { query = 'UPDATE users SET money = money + ? WHERE identifier = ?', values = { amount, to } },
})
```

เช็คลิสต์เพิ่มเติม:

- ใส่ **index** ทุกคอลัมน์ที่ใช้ใน `WHERE` / `JOIN` (โดยเฉพาะ `identifier`)
  หา query ที่ไม่ใช้ index ได้จาก `slow.log` (เปิด `log_queries_not_using_indexes` ไว้แล้วในขั้นที่ 3)
- เก็บข้อมูลที่อ่านบ่อย–เปลี่ยนน้อย (config, ราคาสินค้า, job) ไว้ใน memory ตอนเซิร์ฟสตาร์ท ไม่ต้อง query ซ้ำ
- อย่า query ใน loop ที่วิ่งทุกเฟรม หรือใน `Citizen.CreateThread` ที่ `Wait(0)`
- เขียนข้อมูลผู้เล่นแบบ **batch ทุก 5–10 นาที** แทนการเขียนทุกครั้งที่ค่าเปลี่ยน


---

#### ภาคผนวก 4.10-W — ถ้าเครื่อง i5 เป็น **Windows** (ขั้นตอนที่ต่างออกไป)

ขั้นที่ 0, 5 (dump/import), 6 (connection string), 7 (ทดสอบ) และ 9 (ลด query) **ใช้เหมือนกันทุกอย่าง**
ต่างกันเฉพาะ 4 ขั้นนี้:

##### W-1 ติดตั้ง MariaDB

1. โหลด **MariaDB Server (MSI)** จาก mariadb.org → เลือกเวอร์ชัน LTS
2. ระหว่างติดตั้ง:
   - ✅ ติ๊ก **"Use UTF8 as default server's character set"**
   - ✅ ติ๊ก **Install as service** → ชื่อ service `MariaDB`
   - ❌ **อย่า** ติ๊ก "Enable access from remote machines for 'root' user"
3. ตรวจเวอร์ชัน: `"C:\Program Files\MariaDB 11.4\bin\mariadb.exe" --version`

##### W-2 WireGuard บน i5

ติดตั้ง **WireGuard for Windows** → Add Tunnel → Add empty tunnel → ตั้งชื่อทันเนลว่า `wg0`

```ini
[Interface]
PrivateKey = <I5_PRIVATE_KEY>
Address    = 10.66.0.3/24
ListenPort = 51820

[Peer]
# FXServer (Windows i9)
PublicKey  = <WINDOWS_I9_PUBLIC_KEY>
Endpoint   = <IP_สาธารณะ_i9>:51820
AllowedIPs = 10.66.0.2/32
PersistentKeepalive = 25
```

เปิดพอร์ต WireGuard ขาเข้า:

```powershell
New-NetFirewallRule -DisplayName "WireGuard" -Direction Inbound `
  -Protocol UDP -LocalPort 51820 -Action Allow
```

##### W-3 คอนฟิก `my.ini` — **ต่างจาก Linux ตรงนี้ ระวัง**

แก้ไฟล์ `C:\Program Files\MariaDB 11.4\data\my.ini` ในหัวข้อ `[mysqld]`:

```ini
[mysqld]
# ── เครือข่าย ──────────────────────────────────
# บน Windows แนะนำให้ bind 0.0.0.0 แล้วกันด้วย Firewall แทน
# (ถ้า bind ไปที่ 10.66.0.3 ตรง ๆ service จะสตาร์ตไม่ขึ้นตอนบูต
#  เพราะ MariaDB ขึ้นก่อน WireGuard — Windows ไม่มี systemd ให้สั่งรอง่าย ๆ)
bind-address    = 0.0.0.0
skip-name-resolve

max_connections     = 200
thread_cache_size   = 64
wait_timeout        = 600
interactive_timeout = 600

# ── InnoDB ─────────────────────────────────────
# ~165 MB DB → 1G เหลือเฟือ (ดูเหตุผลในบล็อก Linux ด้านบน)
innodb_buffer_pool_size      = 1G
innodb_buffer_pool_instances = 1
innodb_log_file_size         = 256M

# ⚠️ ห้ามใส่ innodb_flush_method = O_DIRECT บน Windows
#    O_DIRECT เป็นของ Unix เท่านั้น — Windows ใช้ async_unbuffered เป็นค่าเริ่มต้นอยู่แล้ว
#    ซึ่งถูกต้องแล้ว ไม่ต้องตั้งอะไรเพิ่ม

innodb_flush_log_at_trx_commit = 2
innodb_io_capacity      = 4000
innodb_io_capacity_max  = 10000
innodb_read_io_threads  = 8
innodb_write_io_threads = 8

# ── Slow query log (พาธแบบ Windows) ────────────
slow_query_log      = 1
slow_query_log_file = "C:/mariadb-logs/slow.log"
long_query_time     = 0.15
log_queries_not_using_indexes = 1

# ── Charset ────────────────────────────────────
character-set-server = utf8mb4
collation-server     = utf8mb4_unicode_ci
```

```powershell
mkdir C:\mariadb-logs -Force
net stop MariaDB
net start MariaDB
```

##### W-4 🔒 Firewall — ขั้นตอนที่สำคัญที่สุดของฝั่ง Windows

เพราะ `bind-address = 0.0.0.0` ทำให้ MariaDB ฟังทุกอินเทอร์เฟซรวมถึง IP สาธารณะ
**Firewall คือด่านเดียวที่กันอินเทอร์เน็ตออกจากพอร์ต 3306** — ห้ามข้ามขั้นนี้เด็ดขาด

```powershell
# 1) บล็อก 3306 จากทุกที่ก่อน (กฎ Block ชนะ Allow เสมอใน Windows Firewall
#    ดังนั้นต้องระบุ RemoteAddress ในกฎ Block ให้เป็นเฉพาะสิ่งที่ต้องการบล็อก)
New-NetFirewallRule -DisplayName "MariaDB - block public" -Direction Inbound `
  -Protocol TCP -LocalPort 3306 -RemoteAddress Any -Action Block

# 2) อนุญาตเฉพาะ i9 ผ่าน WireGuard เท่านั้น
New-NetFirewallRule -DisplayName "MariaDB - allow i9 via wg" -Direction Inbound `
  -Protocol TCP -LocalPort 3306 -RemoteAddress 10.66.0.2 -Action Allow
```

> ⚠️ Windows Firewall ให้ **Block ชนะ Allow** ถ้ากฎทับซ้อนกัน
> ดังนั้นถ้าใส่กฎ Block แบบ `-RemoteAddress Any` มันจะบล็อก `10.66.0.2` ไปด้วย
> **วิธีที่ถูกต้องกว่า** คือไม่ต้องสร้างกฎ Block เลย — ให้พึ่ง default policy ของ Windows
> (ขาเข้าที่ไม่มีกฎ Allow จะถูกบล็อกอยู่แล้ว) แล้วสร้างเฉพาะกฎ Allow ข้อ 2 พอ:

```powershell
# ✅ วิธีที่แนะนำ — สร้างแค่กฎเดียว
Remove-NetFirewallRule -DisplayName "MariaDB - block public" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "MariaDB - allow i9 via wg" -Direction Inbound `
  -Protocol TCP -LocalPort 3306 -RemoteAddress 10.66.0.2 -Action Allow

# ตรวจว่า Firewall เปิดใช้งานอยู่จริงทุกโปรไฟล์ (ถ้า Off = 3306 โล่งสู่อินเทอร์เน็ต!)
Get-NetFirewallProfile | Select-Object Name, Enabled
```

**ตรวจสอบจากภายนอกว่าปิดสนิทจริง** — รันจากเครื่องอื่นที่ไม่ใช่ i9:

```bash
nc -zv -w3 <IP_สาธารณะ_i5> 3306
# ต้องได้ timeout / refused เท่านั้น ถ้าต่อติด = Firewall ยังไม่ปิด ให้แก้ทันที
```

##### W-5 สำรองข้อมูลด้วย Task Scheduler (แทน cron)

สร้าง `C:\scripts\db-backup.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$Bin   = "C:\Program Files\MariaDB 11.4\bin"
$Dest  = "D:\backup\mariadb"
$Stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
New-Item -ItemType Directory -Force -Path $Dest | Out-Null

& "$Bin\mariadb-dump.exe" --defaults-file="C:\scripts\backup.cnf" `
    --single-transaction --routines --triggers --events `
    --hex-blob --default-character-set=utf8mb4 `
    happy_base | Out-File -Encoding utf8 "$Dest\happy_base_$Stamp.sql"

Compress-Archive -Path "$Dest\happy_base_$Stamp.sql" `
                 -DestinationPath "$Dest\happy_base_$Stamp.zip" -Force
Remove-Item "$Dest\happy_base_$Stamp.sql"

# เก็บย้อนหลัง 14 วัน
Get-ChildItem $Dest -Filter *.zip |
  Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } |
  Remove-Item -Force
```

เก็บรหัสผ่านไว้ในไฟล์แยก `C:\scripts\backup.cnf` (อย่าใส่ในสคริปต์):

```ini
[client]
user=root
password=รหัสผ่าน_root
```

```powershell
# จำกัดสิทธิ์ไฟล์รหัสผ่านให้เฉพาะ Administrators
icacls C:\scripts\backup.cnf /inheritance:r /grant:r "Administrators:(R)"

# ตั้งให้รันทุกวันตี 5
$A = New-ScheduledTaskAction -Execute 'powershell.exe' `
       -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\scripts\db-backup.ps1'
$T = New-ScheduledTaskTrigger -Daily -At 5:00am
Register-ScheduledTask -TaskName 'MariaDB Backup' -Action $A -Trigger $T `
       -User 'SYSTEM' -RunLevel Highest
```

> 🔴 ทดลอง restore ลง DB ชื่ออื่นอย่างน้อยเดือนละครั้ง — backup ที่ไม่เคยลอง restore = ไม่มี backup

---

## 5. ลำดับการลงมือทำ

| สัปดาห์ | งาน | ผลที่วัดได้ |
|---|---|---|
| **1** | ตั้ง VPS + nginx + Cloudflare + `fileserver_add` (ข้อ 2) | เวลาโหลดเข้าเซิร์ฟครั้งแรกลดลง 40–70%, โหลดเครื่อง i9 ลด |
| **1** | เขียนสคริปต์ล้างแคชเข้า deploy flow (ข้อ 2.8) | ไม่มีปัญหาไฟล์เก่าค้าง |
| **2** | โปรไฟล์หา resource ที่กิน tick (ข้อ 4.9) แล้วแก้ 5 ตัวแรก | tick time ลดลง |
| **2** | เปิด culling + routing bucket (ข้อ 4.3–4.4) | tick time ลดลงอีก |
| **3** | ~~ย้าย MariaDB ไป i5~~ → **ลดจำนวน query แทน** (ข้อ 4.10 ขั้นที่ 9)<br><sub>วัดแล้ว DB แค่ 165 MB — ย้ายเครื่องไม่ลด query ลงเลย ทำทีหลังได้</sub> | tick time นิ่งขึ้นจริง |
| **3** | เพิ่มสล็อตทีละ 100 → 800 → 900 → 1024 | วัดทุกรอบ |
| **4** | เช่า VPS ตัวที่ 2 ทำ Cutter (ข้อ 3) **ถ้าวัด latency แล้วผ่าน** | IP ซ่อน + กัน DDoS |

> ⚠️ **อย่าทำหลายอย่างพร้อมกัน** — เปลี่ยนทีละอย่าง วัดผลทุกครั้ง
> ไม่งั้นเวลาเซิร์ฟแย่ลงจะไม่รู้ว่าตัวไหนเป็นเหตุ

---

## 6. Troubleshooting

| อาการ | สาเหตุที่พบบ่อย | วิธีแก้ |
|---|---|---|
| `X-Cache-Status` เป็น `MISS` ตลอด | ไม่ได้ตั้ง `adhesive_cdnKey` → URL ไม่ซ้ำกันรายคน | ตั้งค่าแล้วรีสตาร์ทเซิร์ฟ (ข้อ 2.6) |
| ผู้เล่นค้างที่ "Loading..." / texture หาย | แคชค้างไฟล์เวอร์ชันเก่า | `sudo fivem-cache-purge` (ข้อ 2.8) |
| เข้าเซิร์ฟไม่ได้หลังเปิด proxy | ลืม `sv_proxyIPRanges` → rate limiter เตะ | ใส่ IP proxy ทุกตัวใน `sv_proxyIPRanges` |
| ผู้เล่นโดนเตะเป็นแถวหลังทำ Cutter | ทุกคนดูเหมือนมาจาก IP เดียว ชน `net_tcpConnLimit` (default 16) | `net_tcpConnLimit 1024` + ใส่ IP ใน `sv_proxyIPRanges` |
| หน้าจอ deferral / คิว ปิดตัวเองทันที | ลืม `proxy_http_version 1.1` หรือเปิด `proxy_buffering` ที่ `location /` | ดูคอนฟิกข้อ 2.5 |
| `connect connect.stl.example` ไม่ติด | คำสั่ง `connect` ไม่แปลงโดเมนเปล่าเป็น URL | ใช้ `connect "https://connect.stl.example/"` |
| ไฟล์ใหญ่ไม่ถูกแคชโดย Cloudflare | เกิน 512 MB (ลิมิตแผน Free/Pro/Business) | ตั้ง `cdn.` เป็น **DNS only** (ข้อ 2.3) |
| ping ผู้เล่นเพิ่มขึ้นหลังทำ Cutter | Cutter อยู่คนละ DC กับ i9 | ย้าย Cutter ไป DC เดียวกับ i9 (ข้อ 3.6) |
| tick time กระตุกเป็นช่วง ๆ | Windows ย้ายเธรดหลักไป E-core / Defender สแกน | ตั้ง affinity + exclusion (ข้อ 4.6) |
| เซิร์ฟดี แต่บางคนวาร์ป | packet loss ฝั่งผู้เล่นเอง | ให้กด F8 → `netgraph` ดู loss |
| แคชกินดิสก์จนเต็ม | `max_size` สูงเกินไป | ลด `max_size` ใน `proxy_cache_path` |
| ย้าย DB แล้วเซิร์ฟช้าลง | RTT ข้าม DC สูง + สคริปต์ยิง query แบบ N+1 | วัดใหม่ตามข้อ 4.10 ขั้นที่ 0, รวบ query (ขั้นที่ 9), ถ้าไม่ดีขึ้นให้ rollback |
| MariaDB ไม่สตาร์ตหลังรีบูต i5 | `bind-address` ชี้ IP ของ WireGuard แต่ wg0 ยังไม่ขึ้น | เพิ่ม systemd override `After=wg-quick@wg0` (ข้อ 4.10 ขั้นที่ 3) |
| เชื่อม DB ค้างนานหลายวินาทีต่อ connection | MariaDB ทำ reverse DNS lookup ของ client | ใส่ `skip-name-resolve` ใน my.cnf |
| oxmysql ขึ้น error เชื่อมต่อไม่ได้ ทั้งที่ ping ผ่าน | รหัสผ่านมีอักขระพิเศษ ทำให้ URI พัง | ใช้รูปแบบ `user=;password=;host=...` แทน (ข้อ 4.10 ขั้นที่ 6) |
| ภาษาไทยใน DB กลายเป็น `???` หลังย้าย | dump/import ไม่ได้ระบุ charset | dump ใหม่ด้วย `--default-character-set=utf8mb4` |

---

## 7. สรุป: อะไรช่วยอะไร

| เป้าหมายของคุณ | CDN (ข้อ 2) | Cutter (ข้อ 3) | Optimize (ข้อ 4) |
|---|:---:|:---:|:---:|
| โหลดแมพ/เข้าเซิร์ฟเร็ว | ✅ **ช่วยมาก** | ❌ | 🔸 ช่วยถ้าลดขนาด assets |
| ผู้เล่นเห็นตรงกัน ไม่วาร์ป | ❌ | ❌ | ✅ **ช่วยมาก** |
| ภาพไม่หน่วง | ❌ | ❌ | ✅ **ช่วยมาก** |
| รองรับ 1,024 คน | 🔸 ช่วยทางอ้อม (ปลดภาระ i9) | ❌ | ✅ **ตัวหลัก** |
| ซ่อน IP / กัน DDoS | 🔸 บางส่วน | ✅ **ตัวหลัก** | ❌ |
| ลดภาระเครื่อง i9 | ✅ | 🔸 เล็กน้อย | ✅ |

> **ถ้าทำได้แค่อย่างเดียว → ทำข้อ 4 (optimize)** เพราะปัญหาที่คุณอธิบาย (วาร์ป/ซิงค์ไม่ตรง/หน่วง) แก้ได้ที่นั่นที่เดียว
> **ถ้าทำได้สองอย่าง → เพิ่มข้อ 2 (CDN)** เพราะตอบโจทย์ "โหลดแมพเร็ว" ตรง ๆ และปลดภาระ i9
> **ข้อ 3 (Cutter) ทำทีหลังสุด** และทำก็ต่อเมื่อวัด latency แล้วผ่านเกณฑ์

---

## 8. อ้างอิง

- [Proxy Setup — Cfx Documentation](https://docs.fivem.net/docs/server-manual/proxy-setup/) — `sv_forceIndirectListing`, `sv_listingHostOverride`, `sv_proxyIPRanges`, `sv_endpoints`, `adhesive_cdnKey`, `fileserver_add`, nginx stream, local TLS proxy
- [Optimizing Resource Downloads Using a Caching Proxy — Cfx Documentation](https://docs.fivem.net/docs/cookbook/2019/10/29/optimizing-resource-downloads-using-a-caching-proxy/) — `proxy_cache_path`, `fileserver_add/remove/list`, คำเตือนเรื่องล้างแคช
- [Server Commands — Cfx Documentation](https://docs.fivem.net/docs/server-manual/server-commands/) — `sv_maxClients`, `onesync`, `onesync_migrateDataTimeout`, `sv_endpointPrivacy`, `net_tcpConnLimit`, `sv_enforceGameBuild`, `sv_authMaxVariance`, `sv_authMinTrust`
- [OneSync — FiveM Documentation](https://docs.fivem.net/docs/scripting-reference/onesync/) — culling radius 424 หน่วย, routing bucket, ข้อจำกัดสล็อต
- [Two new experimental OneSync variables — Cfx Documentation](https://docs.fivem.net/docs/cookbook/2019/08/12/two-new-experimental-onesync-variables/) — `onesync_distanceCullVehicles`, `onesync_forceMigration`
- [FXServer Reverse Proxy (community gist)](https://gist.github.com/nathanctech/e648f8312ad0d599fbb3a28db7e4c8f0) — ต้นแบบคอนฟิกที่เอกสารทางการอ้างถึง
- [Default Cache Behavior — Cloudflare](https://developers.cloudflare.com/cache/concepts/default-cache-behavior/) — ลิมิตไฟล์แคช 512 MB สำหรับ Free/Pro/Business
- [FiveM Element Club tiers](https://fivem.net/server-hosting) — Argentum 64 / Aurum 128 / Platinum 2048 slots

---

*เอกสารนี้อ้างอิงคอนฟิกจากเอกสารทางการ Cfx.re ณ เดือนกันยายน 2026 — ค่า convar อาจเปลี่ยนตาม server build ให้ตรวจสอบกับเอกสารล่าสุดก่อนใช้งานจริง*
