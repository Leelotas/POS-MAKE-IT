# MAKE IT

Thai, mobile-first POS with a real Supabase backend. Production: https://make-it-pos.vercel.app

## Run locally

Use Node.js 24, then `npm ci`, copy `.env.example` to `.env.local`, set the Supabase keys, and run `npm run dev`.
Never commit `.env.local`, `.env.qa`, the Vercel credentials, or any service key.

## Deployment

Vercel project: `lee-co/make-it-pos`. Supabase project: `xzzkhbxrttnbqguiohkh`.
The migrations in `supabase/migrations/` were applied through the Supabase SQL editor after verifying that the public schema was empty. The second migration adds finite-number validation and prevents referenced files from starving cleanup batches. Do not re-run them against existing production tables. Subsequent database changes belong in new migrations.

Vercel preview and production need:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` (supports the publishable key)
- `SUPABASE_SERVICE_ROLE_KEY` (server only; supports a Supabase secret key)
- `CRON_SECRET` (server only)
- `TYPHOON_OCR_API_KEY` (server only; used to read the transaction date/time from transfer slips)
- `ADMIN_ACTION_SECRET` (server only; confirmation secret for deleting a shop from the Admin page)

`/api/cleanup` accepts only `Authorization: Bearer <CRON_SECRET>` and runs daily at 20:00 UTC. It removes unreferenced uploads older than 24 hours using a mark-under-shop-lock protocol so deletion cannot race checkout. Failed Storage removals are retried on the next run. Never expose the service key in a `NEXT_PUBLIC_` variable.

Authentication Site URL is `https://make-it-pos.vercel.app`; the redirect allowlist is limited to `https://make-it-pos.vercel.app/**`. Email confirmation remains enabled. **Custom SMTP must be configured in Supabase Authentication → Emails → SMTP Settings before general public registration and password-reset delivery can work.** Supabase's default sender only delivers to authorized organization-member addresses. No email-verification bypass was introduced.

## Data and accounting

- One authenticated owner manages each shop and can invite confirmed users with a private shop code. Members can operate the POS but cannot export Excel/PDF, manage other members, rename the shop, or delete it. RLS and database functions resolve every request to the caller's current shop.
- Product creation records opening stock without fabricating historical cash expenses. Restocking uses moving weighted-average cost. Adjustments record a reason and change the count, not cash flow.
- Every sale stores immutable product name, unit price, and unit cost snapshots. A shop row lock serializes inventory mutations; checkout and stock decrements commit together. Retried request UUIDs return the existing result.
- Cash sales require no photo. Transfers require an existing, private upload belonging to the shop. Signed image links expire after five minutes. Photos are evidence, not bank verification.
- Canceling a whole sale restores its historical cost basis to the current stock pool. Canceled sales are excluded from the original sale-date totals. The app does not initiate actual refunds.
- Shop owners cannot rewrite income/expense entries; authorized Admin corrections retain an audit trail. Paid purchases are linked to stock movements and counted as cash out, not operating expense. Unpaid purchases can be marked paid later, once only.
- Gross profit = non-canceled sales − cost of goods sold. Net profit = gross profit + other income − operating expenses. Cash balance change = sales + other income − paid purchases − operating expenses.
- Forecast = current stock × (current sale price − current average cost), including inactive stock; it does not deduct future operating expenses.
- Report dates use Asia/Bangkok. Database timestamps are UTC; SQL monetary values are numeric; JavaScript calculations use Decimal. Exports contain the same calculations as the UI.
- Checkout records the actual sale date/time either from a seller-confirmed manual entry or from OpenTyphoon OCR. OCR only pre-fills the fields; the seller must review them before saving. Customer type is stored with each sale, and the Week 3 export produces `Date | Time | Product | Quantity | Price | Total | Customer Type | Gender` rows for Google Sheets.

## Verification

`npm test`: a real embedded PostgreSQL engine (PGlite) executes the entire migration and exercises RLS, restricted writes, costs, duplicate requests, failed/voided sales, deferred purchase payments, file policies, garbage-collection races, and Bangkok midnight report boundaries.

`npm run typecheck` and `npm run build` validate the application. `npm audit --omit=dev` checks dependencies. ExcelJS's UUID dependency is overridden to the patched CJS-compatible 11.x release.

`node --import tsx scripts/live-smoke.ts` is an **opt-in integration test** that creates two disposable QA users and shop data in the configured Supabase project. It tests real simultaneous HTTP requests for duplicate checkout and last-item stock, private image access and ledger writes. It saves temporary account credentials to ignored `.env.qa` for browser tests. Run `node --import tsx scripts/cleanup-qa.ts` when done; cleanup validates the exact recorded user IDs, QA metadata and `example.invalid` addresses before deleting only those test accounts and their data. It does not touch ordinary shops.

Browser checks performed on desktop Chrome and a 390px responsive viewport: sign-in, catalog, cart, cash checkout, transfer-without-slip validation, history, reports, Excel/PDF downloads. Report files were reopened and Thai PDF pages rendered for visual inspection. Actual iPhone Safari / Android camera hardware still requires testing on those devices. Chrome extension file-chooser automation needs “Allow access to file URLs”; direct authenticated Storage upload was tested independently.

There are no offline sale submissions, multiple employee permission levels, partial returns, taxes, discounts, or automatic bank/slip validation in v1. Local storage retains only each shop's cart and pending checkout request for safe retries.
# Admin และฟอนต์ (9 กันยายน 2569)

- หน้า `/admin` ใช้บัญชี Supabase เดิม บัญชีที่ยืนยันอีเมลและมีรายชื่อใน `makeit_admins` เท่านั้นจึงเข้าได้ ไม่มีการกำหนดสิทธิ์จากข้อมูลที่ผู้ใช้แก้เอง
- ติดตั้ง migration `202609090003_admin.sql` ต่อจาก 001 และ 002; บัญชีหลักได้รับการกำหนดผ่านช่องทางผู้ดูแล Supabase โดยไม่เก็บรหัสผ่านใน repository
- ดูจำนวนร้าน ค้นหาชื่อ/อีเมล เปิดกิจกรรม สินค้า บิล หลักฐาน รายรับรายจ่าย และรายงานแยกร้าน
- แก้ชื่อร้าน สินค้า สต็อก ต้นทุนปัจจุบัน รายรับรายจ่าย และบิล พร้อมเหตุผลและข้อมูลก่อน–หลังใน `makeit_admin_audit` ซึ่งไคลเอนต์แก้หรือลบไม่ได้
- การแก้บิลยกเลิกบิลเดิมและสร้างบิลใหม่ในธุรกรรมเดียว รักษาต้นทุนเดิมของจำนวนเดิม ใช้ต้นทุนปัจจุบันกับจำนวนที่เพิ่ม ล็อกสต็อก และตรวจข้อมูลเก่าเพื่อกันแก้ทับการขายจากร้าน รหัสคำขอใช้ซ้ำได้เมื่อเครือข่ายขัดข้อง
- ฟอนต์หน้าเว็บและ PDF เป็น Prompt แบบไทยไม่มีหัว เก็บไฟล์และ OFL license ใน `public/fonts` โลโก้ต้นฉบับคงเดิม
- `npm test` ตรวจสิทธิ์ Admin/ร้านค้า การเพิ่มสิทธิ์เอง ประวัติแก้ไข สต็อกและต้นทุนเมื่อแก้บิล พร้อมการส่งคำขอซ้ำ; `scripts/admin-smoke.ts` ใช้บัญชีชั่วคราวจาก `live-smoke.ts` ทดสอบกับ Supabase จริง แล้วล้างด้วย `cleanup-qa.ts`
