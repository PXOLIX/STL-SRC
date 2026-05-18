# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ภาษาในการตอบกลับ

ตอบกลับผู้ใช้เป็น **ภาษาไทย** เสมอ ทั้งการอธิบาย การถามคำถาม สรุปงาน และข้อเสนอแนะ
โค้ด/commit message/ชื่อไฟล์ ใช้ภาษาอังกฤษตามปกติ

## Workflow Rules (สำคัญที่สุด)

ก่อนแก้ไขโค้ดหรือสร้างไฟล์ใหม่ทุกครั้ง ให้ทำตามขั้นตอนนี้:

1. **ถามก่อนเสมอ** — ห้ามแก้ไข/สร้าง/ลบไฟล์โดยไม่ขออนุญาต แม้จะดูเป็นการเปลี่ยนแปลงเล็กน้อย
2. **เสนอแนวทางอย่างน้อย 2 แบบ** — ทุกการตัดสินใจทาง architecture/implementation ต้องแสดงตัวเลือกพร้อม:
   - ข้อดี (Pros)
   - ข้อเสีย (Cons)
   - ผลต่อ performance
   - ผลต่อ security
   - ผลต่อ maintainability
3. **รอคำตอบก่อนลงมือ** — ใช้ `AskUserQuestion` tool เพื่อให้ผู้ใช้เลือกแนวทาง
4. **หลังลงมือเสร็จ** สรุปสั้น ๆ ว่าทำอะไรไป และจุดที่ควรทดสอบในเกม

## Tech Stack

Repository นี้พัฒนา **FiveM resource เดี่ยว** ด้วย stack ต่อไปนี้:

| Layer | เทคโนโลยี |
|---|---|
| Game Server | FiveM (CitizenFX) |
| Framework | **ESX Legacy 1.10+** (ใช้ `imports.lua` / `exports`, ไม่ใช่ `TriggerEvent('esx:getSharedObject')`) |
| Inventory | **ESX built-in inventory** (`xPlayer.addInventoryItem`, `xPlayer.removeInventoryItem`, `xPlayer.getInventoryItem`) — ไม่ใช่ ox_inventory |
| Database | MySQL ผ่าน **oxmysql** (`MySQL.query`, `MySQL.update`, `MySQL.insert`, `MySQL.scalar`, `MySQL.single`) |
| Utility Library | **ox_lib** (`lib.notify`, `lib.callback`, `lib.registerContext`, `lib.points`, `lib.locale`) |
| Server-side | Lua |
| Client-side | Lua |
| NUI / UI | HTML + CSS + JavaScript (vanilla เป็นค่า default เว้นแต่ตกลงเป็นอย่างอื่น) |

## Resource Structure (Convention)

FiveM resource เดี่ยวควรมีโครงสร้างนี้ — ห้ามเดา path เอง ถ้ายังไม่มีไฟล์ให้ถามก่อนสร้าง:

```
<resource-name>/
├── fxmanifest.lua          # manifest (fx_version 'cerulean', game 'gta5')
├── config.lua              # ค่า config ที่ admin/owner เซิร์ฟต้องปรับ
├── locales/                # ถ้าใช้ ox_lib locale
│   ├── th.json
│   └── en.json
├── client/
│   └── main.lua            # client logic
├── server/
│   └── main.lua            # server logic (validate ทุก event ที่มาจาก client)
├── shared/
│   └── utils.lua           # ฟังก์ชันที่ client+server ใช้ร่วม
└── html/                   # NUI (เฉพาะ resource ที่มี UI)
    ├── index.html
    ├── style.css
    └── script.js
```

`fxmanifest.lua` ต้องประกาศ shared/client/server scripts ตามลำดับ และ `dependencies` ต้องระบุ `es_extended`, `oxmysql`, `ox_lib`

## Performance Rules

โค้ดทุกชิ้นใน repo นี้ต้องเขียนโดยคำนึงถึง performance — FiveM resource ที่เขียนไม่ดีจะลด server FPS ทั้งเซิร์ฟ:

- **ห้าม busy loop** — `while true do ... end` ทุกตัวต้องมี `Wait()` อย่างน้อย 1ms; ถ้าไม่ต้องการ realtime ให้ใช้ `Wait(500)`, `Wait(1000)` หรือมากกว่า
- **ใช้ event-driven แทน polling** ทุกครั้งที่ทำได้ (เช่น ใช้ `ox_target` เปิด menu แทน loop เช็คระยะตลอดเวลา)
- **Cache ค่าที่ดึงบ่อย** — `PlayerPedId()`, `GetEntityCoords()` ห้ามเรียกซ้ำในลูปเดียวกัน
- **Server query ต้องเป็น async** — ใช้ `MySQL.query.await()` ใน thread แยก, อย่า block main thread
- **NUI message** ใช้เมื่อจำเป็น — ปิด NUI focus เมื่อใช้งานเสร็จ (`SetNuiFocus(false, false)`)

## Security Rules

**Server เป็นเจ้าของความจริงเสมอ — Client ไม่ได้รับความเชื่อถือใด ๆ**

- **Validate ทุก event ที่มาจาก client** ใน `RegisterNetEvent` / `lib.callback.register`:
  - ตรวจว่า `source` (player id) มี xPlayer จริง
  - ตรวจว่าผู้เล่นมีไอเทม/เงิน/job/permission ที่ event อ้าง
  - ตรวจว่าระยะห่างของผู้เล่นกับ entity/coords สมเหตุสมผล (anti-teleport exploit)
- **ห้ามใส่ราคา/จำนวน/item name มาจาก client** — server ต้องดูจาก `Config` หรือ database ของตัวเองเท่านั้น
- **SQL ต้องใช้ parameterized query** — ห้าม concatenate string เข้า query เด็ดขาด
  ```lua
  -- ถูก
  MySQL.query('SELECT * FROM users WHERE identifier = ?', { identifier })
  -- ผิด (SQL Injection)
  MySQL.query('SELECT * FROM users WHERE identifier = "' .. identifier .. '"')
  ```
- **ห้าม trigger server event จาก NUI โดยตรง** — ผ่าน client Lua แล้วให้ client เรียก server callback
- **Rate limit** event ที่ผู้เล่น spam ได้ (เช่น ซื้อของ, ใช้ skill)

## ESX Legacy Pattern (1.10+)

ใช้ pattern ใหม่เสมอ:

```lua
-- ✅ ถูก (Legacy 1.10+)
ESX = exports['es_extended']:getSharedObject()

-- ❌ ผิด (เก่ามาก ห้ามใช้)
ESX = nil
TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
```

Inventory operation:
```lua
local xPlayer = ESX.GetPlayerFromId(source)
xPlayer.addInventoryItem('bread', 1)
xPlayer.removeInventoryItem('bread', 1)
local item = xPlayer.getInventoryItem('bread')
if item.count >= 1 then ... end
```

## Database (oxmysql)

- ใช้ `.await` form ใน thread ที่ async ได้ (callback, command handler) เพื่อให้โค้ดอ่านง่าย
- ใช้ callback form เมื่ออยู่ใน synchronous context
- เปลี่ยน schema → ต้องสร้างไฟล์ `.sql` ใน root resource และแจ้งผู้ใช้ให้ import เอง

```lua
local result = MySQL.query.await('SELECT * FROM owned_vehicles WHERE owner = ?', { identifier })
local id     = MySQL.insert.await('INSERT INTO logs (player, action) VALUES (?, ?)', { identifier, 'buy' })
local exists = MySQL.scalar.await('SELECT 1 FROM users WHERE identifier = ?', { identifier })
```

## Commands ที่มักใช้ใน FiveM dev

Repository นี้ไม่มี build/test pipeline ในตัว resource จะถูกรันโดย FXServer ของผู้ใช้เอง:

| คำสั่ง (พิมพ์ใน server console / F8) | ใช้เมื่อ |
|---|---|
| `ensure <resource-name>` | โหลด resource ครั้งแรก |
| `restart <resource-name>` | reload หลังแก้โค้ด |
| `refresh` | refresh manifest หลังเพิ่ม resource ใหม่ |
| `stop <resource-name>` | หยุด resource |

ไม่มี unit test framework สำหรับ FiveM Lua ที่ใช้กันแพร่หลาย — การทดสอบทำในเกมเป็นหลัก ให้แจ้งผู้ใช้ทุกครั้งหลังแก้โค้ดว่า "ต้อง restart resource และทดสอบ scenario อะไรบ้าง"

## Git Workflow

- branch ปัจจุบันที่ทำงาน: `claude/add-claude-documentation-xQBSk`
- ห้าม commit/push หากผู้ใช้ไม่ได้ขอ
- commit message เป็นภาษาอังกฤษ สั้น เน้น "why"

## สิ่งที่ยังต้องถามผู้ใช้เมื่อเริ่มเขียน resource ใหม่

หากผู้ใช้สั่งให้สร้าง resource ใหม่ ให้ถามข้อมูลเหล่านี้ก่อน:
1. ชื่อ resource และวัตถุประสงค์ (1 ประโยค)
2. ต้องการ UI (NUI) หรือเป็น in-world interaction เท่านั้น
3. ต้องการ database table ใหม่หรือใช้ของ ESX/resource อื่น
4. permission/job ที่จำกัดการใช้งาน (ถ้ามี)
5. config ที่ admin ควรปรับได้ มีอะไรบ้าง
