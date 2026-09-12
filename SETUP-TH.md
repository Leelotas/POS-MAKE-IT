# เปิด MAKE IT บนเครื่องใหม่

ข้อมูลร้าน สินค้า บิล สต็อก รูป และสิทธิ์ Admin อยู่ใน Supabase เดิม จึงไม่ต้องย้ายฐานข้อมูลเมื่อเปลี่ยนเครื่องพัฒนา

## เตรียมเครื่อง

ติดตั้ง Git และ Node.js 24 LTS แล้วเปิด Terminal:

```powershell
git clone https://github.com/Leelotas/POS-MAKE-IT.git
cd POS-MAKE-IT
npm ci
Copy-Item .env.example .env.local
```

เปิด `.env.local` เติมค่า URL และ publishable key จาก Supabase → Project Settings → API Keys ของโปรเจ็กต์ `xzzkhbxrttnbqguiohkh` สำหรับเปิดเว็บในเครื่อง ส่วน secret key และ `CRON_SECRET` ใช้เฉพาะงาน cleanup ฝั่งเซิร์ฟเวอร์และสคริปต์ผู้ดูแล เติม `TYPHOON_OCR_API_KEY` จาก OpenTyphoon เพื่อเปิดใช้การอ่านวัน–เวลาจากสลิป โดยคีย์นี้เป็นความลับฝั่งเซิร์ฟเวอร์และห้ามใช้ชื่อตัวแปรที่ขึ้นต้นด้วย `NEXT_PUBLIC_`

อีกทางหนึ่ง ผู้ที่มีสิทธิ์ Vercel สามารถใช้ `npx vercel link` เลือกทีม `lee-co` และโปรเจ็กต์ `make-it-pos` แล้วใช้ `npx vercel env pull .env.local --environment=preview` ดึงตัวแปรผ่านการเข้าสู่ระบบของตนเอง อย่าสร้างโปรเจ็กต์ซ้ำ

ห้ามส่งรหัสลับขึ้น GitHub หรือใส่ secret key ในตัวแปรชื่อขึ้นต้น `NEXT_PUBLIC_` หากจะย้าย `.env.local` จากเครื่องเดิม ให้ส่งผ่านช่องทางส่วนตัวที่ปลอดภัย

```powershell
npm run dev
```

เปิด `http://localhost:3000` หรือ `http://localhost:3000/admin` แล้วเข้าสู่ระบบด้วยบัญชีเดิม การย้ายเครื่องไม่เปลี่ยนสิทธิ์ Admin

## ทดสอบและเผยแพร่

```powershell
npm test
npm run typecheck
npm run build
```

Production อยู่ที่ https://make-it-pos.vercel.app และหน้า Admin อยู่ที่ https://make-it-pos.vercel.app/admin

โปรเจ็กต์ Supabase เดิมติดตั้ง migrations 001, 002 และ 003 แล้ว ระบบเวลาและประเภทลูกค้าต้องติดตั้ง migration `202609120001_sale_time_and_customer.sql` เพิ่มหนึ่งครั้ง **อย่ารัน migrations เก่าซ้ำกับฐานข้อมูลเดิม** หากสร้างฐานข้อมูลใหม่จึงรันไฟล์ทั้งหมดตามลำดับ พร้อมตั้ง Auth URL, Storage และสิทธิ์ Admin ใหม่

การ deploy ด้วย CLI: `npx vercel deploy --target preview --scope lee-co` ตรวจ Preview แล้วจึง `npx vercel promote <preview-url> --scope lee-co` การ push โค้ดเข้า GitHub เพียงอย่างเดียวไม่ได้รับประกันการ deploy จนกว่าจะเชื่อม Git integration ของ Vercel

SMTP สำหรับส่งอีเมลยืนยันและกู้รหัสผ่านให้ผู้ใช้ทั่วไปยังต้องตั้งค่าใน Supabase ก่อนเปิดรับสมัครทั่วไป

## ไฟล์ที่ไม่อยู่ใน repository

- `.env.local`, `.env.qa`, `.vercel/`: รหัสลับ ตัวแปรเครื่อง และข้อมูลบัญชีทดสอบ
- `node_modules/`, `.next/`, `*.tsbuildinfo`: สร้างใหม่ด้วย npm
- `test-output/`: ภาพและรายงานจากการทดสอบ

โค้ดแอป รูปโลโก้ ฟอนต์พร้อม license, migrations, tests, scripts และ package lock อยู่ใน repository ครบ
