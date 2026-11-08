---
title: "Finance Tracker — Product Requirements Document"
subtitle: "Web + Flutter | Supabase | REST API + MCP AI Agents"
version: "1.0"
date: "2026-11-07"
status: "Baseline specification for implementation"
language: "id-ID"
---

# FINANCE TRACKER

## Product Requirements Document (PRD) — v1.0

**Platform:** Flutter Web, Android, iOS  
**Backend:** Supabase Auth, PostgreSQL, Storage, Realtime, Edge Functions / dedicated API  
**Integrasi:** REST API, OpenAPI, remote MCP Server  
**UI:** Professional minimal finance UI; dark/light/system; sidebar di desktop dan mobile  
**Status dokumen:** Spesifikasi rancangan, belum merupakan fitur yang telah dibangun  
**Tanggal:** 7 November 2026

> **Keputusan produk utama:** Web dan Flutter memiliki **100% kesetaraan fitur**, bukan harus identik secara layout. Semua pengguna dapat menggunakan transaksi, budget, forecast, import/export CSV dan PDF, akun, kategori, AI agent, dan pengaturan di kedua platform. User admin juga mendapatkan admin page di kedua platform.

### Document control

| Item | Keputusan |
|---|---|
| Product name | Finance Tracker (working title) |
| Product category | Personal finance management / finance operations |
| Target | Pengguna pribadi dengan akun terpisah; dapat diperluas ke household |
| Sign-up | Username + email + password + confirm password; tanpa email confirmation |
| Password recovery | Tidak ada self-service forgot/reset password di v1 |
| Admin | Role terpisah, user management, suspend, reset password melalui admin |
| Core value | Catat keuangan dengan akurat; bandingkan budget vs actual; forecast; kontrol via AI agent |
| Navigation | Collapsible left sidebar di desktop; side drawer di mobile; tanpa bottom tabs |
| API agent default | MCP **Read & Write** untuk transaksi biasa, tindakan berisiko memerlukan approval |
| Money movement | Hanya pencatatan keuangan; tidak melakukan transfer uang bank nyata |

### Peta isi dokumen

| Bagian 1-10 | Bagian 11-19 |
|---|---|
| 1. Ringkasan eksekutif | 11. REST API |
| 2. Persona dan user stories | 12. Sync dan offline |
| 3. Ruang lingkup dan prioritas | 13. Non-functional requirements |
| 4. Navigasi dan information architecture | 14. QA dan acceptance criteria |
| 5. Functional requirements | 15. Delivery plan |
| 6. MCP AI Agent Integration | 16. Risks dan decisions |
| 7. Admin Panel dan RBAC | 17. Glossary |
| 8. UI/UX specification | 18. Annotated wireframes |
| 9. Technical architecture | 19. Source references |
| 10. PostgreSQL data model | |

## 1. Ringkasan eksekutif

Finance Tracker adalah aplikasi pengelolaan keuangan lintas platform yang berfungsi sebagai sumber kebenaran tunggal untuk akun/dompet, transaksi, anggaran, tabungan, utang, dan proyeksi. Aplikasi memprioritaskan keakuratan nominal, kecepatan input, transparansi kalkulasi, keamanan data antar-user, serta portabilitas melalui import/export. Selain UI Web dan Mobile, seluruh fungsi utama tersedia melalui REST API dan MCP agar AI agent dapat melakukan analisis dan tindakan dengan akses terkontrol.

### 1.1 Masalah yang diselesaikan

- Data pengeluaran tersebar di cash, rekening, dan e-wallet, sehingga saldo dan cash flow sulit dipantau.
- Anggaran sering tidak dibandingkan dengan realisasi dan prediksi akhir periode.
- Rekap manual dalam spreadsheet menghabiskan waktu dan rentan duplikasi.
- Aplikasi keuangan kerap membatasi fitur desktop/mobile atau sulit diekspor.
- AI agent biasanya hanya bisa menjawab dari teks, bukan melakukan perubahan yang tervalidasi dan dapat diaudit.

### 1.2 Prinsip produk

1. **Correctness first:** saldo, transfer, utang, refund, dan forecast mempunyai definisi yang konsisten.
2. **Parity first:** seluruh kapabilitas produk ada di Web dan Mobile, dengan UI responsif masing-masing.
3. **User control:** user dapat melihat asal nilai, mengoreksi data, mengekspor data, dan mencabut agent.
4. **Useful, not flashy:** UI profesional, minim ornamen, mendahulukan keterbacaan angka dan tabel.
5. **Privacy by default:** akses setiap baris data dilindungi dan admin tidak otomatis membaca finansial user lain.
6. **Agent is a client, not a superuser:** MCP/REST mematuhi izin dan aturan yang sama dengan UI.

### 1.3 Tujuan dan metrik keberhasilan (target awal, perlu divalidasi)

| Tujuan | KPI usulan | Acceptance awal |
|---|---|---|
| Cepat mencatat | Waktu median manual add | <= 15 detik untuk transaksi sederhana pada perangkat yang wajar |
| Akurasi | Saldo rekonsiliasi | 0 ketidaksesuaian akibat kesalahan perhitungan software dalam skenario tes |
| Parity | Matriks fitur | Semua P0 tersedia dan lulus pengujian Web dan Mobile |
| Portabilitas | Round-trip CSV | Impor hasil ekspor CSV tanpa duplikasi/kehilangan field yang didukung |
| AI safety | Unauthorized mutation | 0 operasi berhasil tanpa permission + approval yang disyaratkan |
| Reliability | Duplicate after retry | 0 duplikasi pada mutasi ber-idempotency key yang sama |
| Forecast | Transparansi prediksi | Metode dan asumsi tampil untuk setiap forecast |

### 1.4 Non-goals versi awal

- Mengirim uang, pembayaran QRIS, transfer bank sungguhan, atau menyimpan kredensial internet banking.
- Integrasi otomatis seluruh bank di Indonesia.
- Perdagangan saham/kripto atau pemberian nasihat investasi otomatis.
- Akuntansi perusahaan kompleks, pajak badan, dan pembukuan ERP.
- Sistem AI yang boleh mengubah saldo tanpa catatan ledger dan audit.

## 2. Persona, roles, dan user stories

### 2.1 Persona

- **Regular User:** ingin mencatat pemasukan/pengeluaran, budget, laporan, dan ekspor.
- **Power User:** memiliki banyak akun, butuh custom field, impor bulk, aturan berulang, dan forecast.
- **AI-Connected User:** ingin memerintah agent untuk mencari, mencatat, memperbaiki transaksi, dan membuat laporan.
- **Administrator:** mengelola lifecycle akun tanpa mengakses otomatis isi finansial pribadi user.

### 2.2 User stories utama

| ID | User story | Prioritas |
|---|---|---|
| US-01 | Sebagai user, saya dapat signup dan langsung login tanpa konfirmasi email. | P0 |
| US-02 | Saya dapat mencatat expense/income dengan akun, tanggal, kategori, dan catatan. | P0 |
| US-03 | Saya dapat memindahkan dana antar akun tanpa menaikkan income/expense. | P0 |
| US-04 | Saya dapat memilih template kategori atau membuat kategori dan transaksi custom. | P0 |
| US-05 | Saya dapat memfilter Day/Week/Month/Year serta custom range. | P0 |
| US-06 | Saya dapat import/export CSV dan PDF di Web maupun Mobile. | P0 |
| US-07 | Saya dapat membandingkan budget dengan actual dan forecast akhir periode. | P0 |
| US-08 | Saya dapat menghubungkan agent MCP dan memberinya akses read/write terbatas. | P0 |
| US-09 | Saya dapat menyetujui/menolak tindakan agent yang berisiko. | P0 |
| US-10 | Saya dapat menggunakan sidebar pada web/mobile tanpa bottom navigation. | P0 |
| US-11 | Sebagai admin, saya dapat mencari user, suspend, dan reset password. | P0 |
| US-12 | Saya dapat bekerja tanpa internet dan menyinkronkan transaksi saat online. | P1 |
| US-13 | Saya dapat membuat recurring rules, savings goals, dan schedule utang. | P1 |
| US-14 | Saya dapat melihat historis akurasi forecast dan scenario simulation. | P1 |

## 3. Ruang lingkup dan prioritas release

**P0 (initial usable release):** authentication, profiles, user roles, accounts, categories, transactions, transfer, filtering, transaction templates, dashboard, budgeting, actual-vs-budget + basic forecast, CSV/PDF import/export, REST API, MCP read/write + approval, audit, admin page, dark/light UI, sidebar, validation/security.

**P1 (enhancement release):** offline queue matang, advanced forecast historis, recurring automation, debt & installment, savings goals, subcategory merge, bulk edit, report builder, advanced import mapping, transaction attachments, activity review.

**P2 (advanced):** OCR scanned PDF, AI suggested categorization, enhanced anomaly detection, shared household, investment/net worth tracker, complex rules engine, plugin marketplace. Fitur impor PDF digital ada di P0; OCR untuk PDF hasil scan ditambahkan P2.

> **Scope note:** Semua fitur yang sudah dirilis wajib tersedia pada Web dan Flutter pada rilis yang sama. Tahapan P0/P1/P2 merupakan urutan pengerjaan, bukan pembatasan platform.

## 4. Information architecture dan navigasi

### 4.1 Sidebar final

```text
FINANCE TRACKER
OVERVIEW
  Dashboard
  Transactions
  Accounts & Wallets
  Analytics
PLANNING
  Budgets
  Forecast
  Savings Goals
  Debts & Installments
MANAGEMENT
  Categories
  Transaction Templates
  Recurring Transactions
  Import & Export
SYSTEM
  API & AI Agents
  Settings
ADMIN (role admin only)
  User Management
  Admin Audit Logs
```

### 4.2 Responsive navigation behavior

| Breakpoint (rancangan) | Sidebar behavior | Konten |
|---|---|---|
| Desktop >= 1200px | Sidebar 240px; bisa collapse menjadi rail 64px | Tabel penuh, 2–4 kolom cards |
| Tablet 768–1199px | Sidebar collapsible; state dapat diingat | Grid 2 kolom, tabel horizontal atau adaptive |
| Mobile < 768px | Navigation drawer dari kiri, dibuka hamburger/menu; tanpa bottom tab | Konten 1 kolom, transaksi berbentuk list/card |

Setelah berpindah menu pada mobile, drawer tertutup otomatis. Gesture kembali menutup drawer terlebih dahulu; keyboard navigation dan screen-reader harus didukung. Menu admin hanya tampil pada user berrole admin, namun otorisasi tetap wajib pada backend.

### 4.3 Page inventory

| Route konseptual | Halaman | Fungsi |
|---|---|---|
| `/auth/sign-up` | Create Account | Signup langsung |
| `/auth/login` | Login | Username/email + password |
| `/dashboard` | Overview | Saldo, summary, charts, activity |
| `/transactions` | Transaction List | Search/filter/sort/pagination |
| `/transactions/new` | Transaction Form | Create income/expense/transfer |
| `/transactions/:id` | Transaction Detail | Edit, audit, attachment, split |
| `/accounts` | Accounts | Rekening/dompet dan saldo |
| `/categories` | Categories | Template dan custom hierarchy |
| `/templates` | Quick Transaction Templates | Preset reusable |
| `/budgets` | Budgets | Plan vs Actual |
| `/forecast` | Forecast | Prediksi, asumsi, scenarios |
| `/analytics` | Analytics | Breakdown dan komparasi |
| `/savings` | Savings | Goal tracking |
| `/debts` | Debt & Installments | Piutang, cicilan, due date |
| `/recurring` | Recurring | Jadwal otomatis |
| `/data` | Import & Export | CSV/PDF import/export jobs |
| `/agents` | API & AI Agents | MCP/REST, clients, permissions, approvals, logs |
| `/settings` | Settings | Profil, tema, mata uang, keamanan |
| `/admin/users` | User Management | Akun dan status |
| `/admin/audit` | Admin Audit | Jejak tindakan admin |

## 5. Detailed functional requirements

### 5.1 Authentication dan account security

**Fields signup:** username, email, password, confirm password. Username unik case-insensitive, 3–24 karakter (huruf, angka, underscore); email wajib berformat valid; password minimal 8 karakter (rekomendasi UI 12+), tidak boleh sama dengan username/email; confirm wajib cocok. Validasi client dan server. Setelah signup sukses, sesi aktif dan user masuk dashboard. Tidak ada email confirmation atau OTP.

**Login:** input `Username or Email` dan password. Lookup username dijalankan oleh endpoint aman dengan pesan error generik, throttling, dan tanpa endpoint publik untuk melihat email dari username. Jika user `suspended`, semua operasi harus ditolak; status dipastikan server-side. Logout pada Web dan Mobile, change password menggunakan old password.

**Tidak tersedia di v1:** tombol atau flow self-service forgot password/reset via email. **Admin-assisted password reset** diperbolehkan melalui UI admin dengan reason, konfirmasi tambahan, audit, dan kewajiban user mengganti password sementara pada login berikutnya. Admin tidak pernah melihat password asli user. Penanganan akun yang didaftarkan dengan email orang lain adalah risiko produk penting: tanpa verifikasi email, kepemilikan alamat tidak dapat diasumsikan; admin reset hanya dilakukan dengan pembuktian identitas melalui proses operasional yang didefinisikan.

**Acceptance:** signup berhasil tanpa email OTP; username duplikat ditolak; error login tidak mengungkap akun ada/tidak; user A tidak dapat mengambil session user B; suspend user ditolak di API meski token belum expire.

### 5.2 Accounts and wallets

- Tipe default: Cash, Bank, E-wallet, Other; nama custom, warna/ikon, currency, saldo awal, status active/archive.
- Setiap akun mempunyai balance dari posting ledger, bukan angka yang bebas diubah tanpa histori.
- Transfer antar akun dibuat sebagai satu operasi atomik dengan debit dan kredit yang setara.
- Saldo negatif dapat dilarang atau diperbolehkan per akun (default: warning dan preferensi user).
- Rekonsiliasi: snapshot saldo, adjustment dengan reason, dan audit.
- Arsip akun tidak menghapus transaksi historis; delete akun hanya jika belum memiliki transaksi.

**Acceptance:** transfer Rp100.000 Cash -> Bank mengurangi Cash, menambah Bank, tidak memengaruhi income/expense ataupun total net worth.

### 5.3 Transaction management

**Types:** `expense`, `income`, `transfer`, `adjustment`; refund/reversal memakai linkage ke original transaction. **Required fields:** amount > 0, currency, type, account/related accounts, effective_at, category (kecuali transfer), description optional. **Optional:** tags, merchant/payee, notes, attachment, external reference, location manual, status, custom fields, recurrence link.

**Actions:** create, read, edit, duplicate, reverse, archive/delete (soft delete with recovery policy), split per kategori, bulk tag/move (P1), search, sort, pagination. Status: draft/pending/posted/voided; hanya `posted` dihitung actual/cash balance; `pending` dapat dipertimbangkan forecast secara terpisah.

**Custom form:** user dapat mengatur urutan fields, visibility, default, required (di luar field inti); custom fields bertipe text, number, date, boolean, enum dengan skema validasi; perubahan custom field tidak merusak transaksi lama.

**Idempotency:** semua mutasi REST/MCP membawa `idempotency_key`; penyimpanan dengan constraint unik per user dan operation; request ulang mengembalikan hasil semula.

**Acceptance:** split total selalu sama dengan nominal transaksi; perubahan status dari pending ke posted menghitung actual sekali; refund tidak menghitung pendapatan rutin palsu.

### 5.4 Categories dan transaction templates

**Template categories prebuilt:** Income: Salary/Bonus, Freelance, Business, Gifts, Refund/Other; Expense: Food & Drinks, Groceries, Transport, Housing, Utilities, Shopping, Health, Family & Education, Entertainment, Subscriptions, Fees, Other. User dapat import preset default, memilih subset, dan membuat kategori sendiri.

Category fields: name, type, parent_id (maksimal 2 tingkat di v1), icon, color, order, status. User dapat rename, reorder, archive, merge (P1), serta menetapkan budget default. Kategori yang telah dipakai tidak hard-delete secara langsung.

**Transaction template:** nama preset, tipe transaksi, nominal default (opsional), akun, kategori, merchant, tags, description, custom fields, recurring option. Quick Add menampilkan favourites dan recent amounts. Penggunaan template selalu membuka preview yang dapat diedit sebelum submit; user boleh memilih auto-save untuk preset tertentu tanpa melewati aturan persetujuan agent.

### 5.5 Filtering, search, dan calendar

Filter periode wajib: **Day / Week / Month / Year / Custom Date Range**. Tambahan: pilih tanggal spesifik, week start preference, month/year picker, quick presets (today, yesterday, last 7 days, current pay cycle), prior-period compare. Semua filter berdasarkan timezone user; date-only range dikonversi ke boundary yang tepat di backend, sedangkan timestamp disimpan UTC.

Additional filters: type, account(s), category(s) + descendants, tag(s), merchant, min/max amount, status, attachment present, created_by (self/agent), text search. Multi-sort date/amount/name, saved views, export current filtered results, pagination. Semua filter tersedia Web dan Flutter.

**Acceptance:** `Month` selalu memilih bulan kalender terpilih, bukan asal 30 hari terakhir; `Year` tahun kalender terpilih; custom range inklusif untuk hari awal dan akhir sesuai timezone user.

### 5.6 Dashboard dan analytics

Widgets: consolidated account balance, income/expense/net cash flow, budget utilization, category spend, top merchants, last transactions, overdue bills, forecast status, upcoming recurring, savings progress. User dapat hide/show/reorder widget dan memilih periode global; drag-and-drop desktop dan move-up/down mobile. Chart: line/bar/donut terbatas, label dan tooltip selalu menyajikan angka sebenarnya. Table/list drilldown menuju transaksi yang membentuk angka.

Analytics: expense category breakdown, month-over-month, year-over-year, income sources, cashflow, spending trend, merchant leaderboard, account overview, net worth *cash-only* default; investasi net worth penuh P2. Analytics mendukung filter yang sama dengan transaction list.

### 5.7 Budgets dan budget vs actual

Jenis budget: global, per kategori, per akun (opsional), monthly/weekly/custom pay-cycle. Fields: `period_start`, `period_end`, `currency`, amount, category, rollover behavior, alerts 50/75/90/100% (configurable). Budget dapat disimpan sebagai template periode berikutnya dan memiliki versioning.

**Actual** = jumlah posting expense yang memenuhi periode dan kategori, disesuaikan refund/reversal; internal transfer tidak dianggap expense. **Variance to date** = budget prorata (opsional) - actual; **remaining** = full-period budget - actual; **projected variance** = full-period budget - forecast EOP. UI harus membedakan ketiganya dengan jelas.

**Acceptance:** edit budget tidak mengubah actual; category budget tidak membuat transaksi ganda pada total budget global; progress >100% tampil sebagai overspend.

### 5.8 Forecast dan scenario simulation

**P0 algorithms:**
1. `run_rate`: actual_to_date / elapsed_days * total_days (fallback, jangan digunakan tanpa label asumsi).
2. `scheduled`: posted actual + transaksi recurring/tagihan masa depan yang belum posted.
3. `hybrid`: posted actual + known scheduled future + historical variable spend estimate untuk hari tersisa, menghindari double count tagihan terjadwal.

**P1:** historical weighted averages, weekly seasonality, confidence bands, outlier trimming, forecast snapshot and error metrics. Semua metode deterministik dan versioned. `forecast_generated_at`, periode, basis data, known scheduled, model_version, confidence/assumptions disimpan. Bila sejarah data pendek, UI memberi *low confidence* dan tidak mengarang akurasi.

Outputs: EOP expense, projected variance, expected closing cash, days-to-zero scenario, category level forecast, cash balance curve, expected dues, and what-if. What-if hanya simulasi dan tidak mengubah transaksi/budget aktual sebelum user memilih tindakan eksplisit.

**Example:** Budget Rp5.000.000, actual Rp2.800.000 dalam 14 dari 30 hari => run-rate forecast Rp6.000.000; projected overspend Rp1.000.000. UI wajib memberi label bahwa ini ilustrasi metode sederhana, bukan forecast historis yang terkalibrasi.

### 5.9 Recurring transactions

Rule: cadence daily/weekly/monthly/yearly/custom interval, start/end, date policy (misalnya tanggal 31 di bulan pendek), expected amount, account, category, notes, execution mode `scheduled/draft/auto-post`. Default auto-create sebagai pending/draft agar user dapat memeriksa jika nominal berubah. Backend job harus idempotent. Timezone dan cut-off jelas.

### 5.10 Savings goals

Tujuan dana dengan target amount, target date, allocation account, milestone, contribution log, projection untuk target; pemindahan ke tabungan yang hanya relabel alokasi dana tidak boleh menggandakan pengeluaran. Tampilkan progress dan required monthly contribution.

### 5.11 Debts, receivables, installments

Entitas debt/receivable: creditor/debtor, principal, rate (optional), start, due, installment schedule, payment references, outstanding. Support partial payments, extra principal, reminder, payoff projection. Beban bunga/fee dipisah dari pembayaran pokok agar laporan cash flow dan expense tidak tumpang tindih. Tidak memberi rekomendasi kredit otomatis.

### 5.12 Import CSV dan PDF

**P0 kedua format bisa diimport di Web dan Flutter.** CSV berupa data berstruktur. PDF berarti laporan atau rekening koran digital yang teksnya dapat diekstraksi, dengan **preview + mapping + validasi wajib**; tidak semua template PDF dapat dibaca otomatis. PDF hasil scan/OCR tersedia P2 atau ditandai unsupported dengan penjelasan yang jelas.

**Pipeline import:** file select -> validate type/size -> parse -> detect columns / PDF template -> preview -> map date, description, amount, direction, account, category, reference -> detect duplicates -> user confirms -> atomic/batched save -> result report. Bila parsing PDF ambigu, baris tidak diimpor diam-diam; status `needs_review`. User dapat download error rows CSV.

**Duplicate strategy:** gunakan external transaction ID bila ada; fallback fingerprint account + date + amount + normalized description + source reference; tampilkan `skip/replace/create anyway` dan preview dampak, tidak auto-merge secara diam-diam. File asli disimpan temporer (encrypted private storage) dengan retention default 24 jam setelah job selesai; dapat dimatikan / segera dihapus.

**CSV templates:** format konsisten: `transaction_id, date_time, type, amount, currency, account, destination_account, category, subcategory, merchant, description, tags, status, source_ref`; dengan sample, UTF-8 BOM optional untuk Excel, delimiter configurable, escape CSV aman untuk formula injection pada spreadsheet. Import CSV dari pihak ketiga menggunakan mapping presets.

### 5.13 Export CSV dan PDF

Export menurut filter transaksi yang sedang aktif atau periode custom, seluruh data, kategori, akun, dan analytics. CSV raw ledger-friendly berisi row records, stable IDs, tipe, status, metadata terkait; PDF manusiawi berisi judul, periode, ringkasan, kategori, tabel transaksi, budget-vs-actual, asumsi forecast dan tanggal generated. Password-protected PDF (opsional P1). Job export besar dibuat async dengan status/polling dan link file dengan expiry.

**Acceptance:** export 12 bulan bisa difilter; data berbeda antara CSV/PDF hanya karena format presentasi, bukan jumlah/net amount; transfer tidak ditandai income/expense; PDF dapat dibuka di Web dan Flutter; unduhan membutuhkan identitas user yang sah.

### 5.14 REST API dan OpenAPI

API utama versioned `/api/v1/`, JSON, filtering parameter, cursor pagination, standardized errors, typed decimals/currency, `request_id`, audit context. OpenAPI 3.1 sebagai kontrak. API dan MCP memanggil service layer yang sama. Mutation memerlukan idempotency key dan memakai authorization policy yang sama. API documented dengan examples dan sandbox test environment, tidak mempublikasikan URL project secret.

## 6. MCP AI Agent Integration — final Read & Write policy

### 6.1 Goal dan threat model

MCP memungkinkan client AI yang mendapat consent user untuk membaca ringkasan, mencari transaksi, membuat/memperbaiki transaksi sederhana, serta meminta simulasi dan laporan. MCP adalah **interface sistem keuangan**, bukan akses database bebas. Ancaman utama: token dicuri; client agent memiliki prompt injection dari dokumen atau struk; perubahan data salah; tindakan diulang akibat retry; akses melampaui user/client; approval dibajak; agent mengekspor data sensitif tanpa izin.

**Architecture:** OAuth authorization server (Supabase Auth) -> protected MCP resource server (Streamable HTTP) -> finance authorization + policy engine -> shared finance service -> PostgreSQL/RLS. Remote MCP memakai HTTPS; adapter `stdio` lokal bersifat opsional dan mengakses server sebagai client yang diautentikasi, bukan membaca database langsung.

### 6.2 Permission matrix (initial defaults)

| Scope internal aplikasi | Default MCP Write | Approval |
|---|---|---|
| `accounts:read` | Allow | Tidak |
| `transactions:read` | Allow | Tidak |
| `transactions:create` | Allow | Kondisional berdasarkan nominal/risiko |
| `transactions:update` | Allow | Kondisional berdasarkan selisih/perubahan sensitif |
| `transactions:delete` | Deny | Jika enable, selalu approve |
| `categories:read` | Allow | Tidak |
| `categories:write` | Deny | Jika enable, approval untuk merge/delete |
| `budgets:read` | Allow | Tidak |
| `budgets:write` | Deny | Jika enable, approval |
| `forecasts:read` | Allow | Tidak |
| `forecasts:simulate` | Allow | Tidak |
| `analytics:read` | Allow | Tidak |
| `reports:export` | Deny | Jika enable, approval tiap job berisi data sensitif |
| `transactions:import` | Deny | Jika enable, preview+approval |
| `recurring:write` | Deny | Jika enable, approval |
| `admin:*` | Never | Tidak dapat diaktifkan pada koneksi standar |
| `agent_permissions:write` | Never | Hanya user dari trusted UI, bukan agent |

Permission tidak sama dengan role akun: agent bertindak atas nama user dan hanya boleh subset dari akses user. Admin management tidak boleh diekspos sebagai MCP tool default, sekalipun admin terhubung ke agent. Tindakan diizinkan hanya bila `ownership AND token validity AND connection active AND permission AND approval policy` seluruhnya lolos.

### 6.3 Default approval limits

| Aksi | Kebijakan default | Catatan |
|---|---|---|
| Baca summary/filter transaksi | Auto allow | Audit minimal |
| Buat income/expense <= Rp1.000.000 | Auto allow | Batas per aksi, bukan total harian; validasi klasifikasi |
| Buat income/expense > Rp1.000.000 | Requires approval | Nominal limit bisa dikonfigurasi user |
| Ubah nominal transaksi posted <= Rp250.000 selisih | Auto allow jika bukan rekonsiliasi | Perubahan akun, tipe, mata uang tetap perlu approval |
| Edit selisih > Rp250.000 | Requires approval | Tampilkan old/new values |
| Transfer internal | Requires approval | Tidak mengirim dana sungguhan |
| Delete, bulk edit, adjustment saldo | Requires approval | Eksekusi eksplisit, audit wajib |
| Budget/category destructive changes | Requires approval | Harus permission aktif |
| Export ke agent | Requires approval | Tampilkan rentang dan jenis data |
| Reset password, manage user, grant scope | Prohibited via agent | Tidak tersedia di MCP |

**High-risk rules tambahan:** threshold nilai harus sesuai currency; konversi currency tidak otomatis mengubah limit tanpa kurs yang jelas. User dapat menetapkan daily write cap, max actions per hour, allowed account list, allowed category list, approval-always mode dan emergency pause. Sistem menolak nominal negatif/invalid, transaksi backdated di luar batas yang diset user, dan operation dari suspended account.

### 6.4 Pending approval lifecycle

`proposed -> pending -> approved | rejected | expired | cancelled -> executed | failed`.

- Client mengirim tool call dengan request_id, idempotency_key, payload tervalidasi.
- Server menghitung risk policy dan menyimpan immutable proposal, hash payload, expected row version, expiry default 10 menit.
- User menerima in-app approval di Web/Flutter: nama agent, ikon, action, account, category, old/new values, nominal, timestamp, alasan, risiko, opsi Approve/Reject.
- Approval hanya melalui sesi user aplikasi yang terverifikasi, **bukan** melalui MCP tool milik agent. Untuk operasi sensitif gunakan recent-login/step-up jika tersedia tanpa mengharuskan OTP produk secara umum.
- Server memeriksa ulang role, status agent, permissions, limits, payload hash, row version, expiry, dan kepemilikan. Hanya satu eksekusi atomik per proposal.
- Agent menerima `pending_approval` plus opaque action ID, lalu dapat mengecek status dengan `get_action_status` (tanpa mampu approve dirinya sendiri).
- Jika expired/revoked/rejected, tindakan tidak dieksekusi dan agent menerima error terstruktur.

### 6.5 Authentication dan authorization MCP

1. Supabase Auth OAuth 2.1 sebagai authorization server, Authorization Code + PKCE, consent UI dengan identitas agent/client dan izin aplikasi.
2. Protected Resource Metadata untuk discovery, issuer discovery, resource indicator/audience binding, JWKS JWT signature validation, `iss`, `aud`, `exp`, `nbf` (jika ada), `sub`, dan `client_id`.
3. Supabase native OAuth scopes yang tersedia saat dokumen dibuat hanya `openid`, `email`, `profile`, `phone`; **custom domain scopes tidak boleh diasumsikan native**. Izin `transactions:*`, `budgets:*`, dst. harus disimpan pada backend Finance Tracker dan ditegakkan di service authorization + database RLS, termasuk untuk semua akses yang mungkin bypass MCP/REST.
4. `client_id` pada token harus cocok dengan koneksi agent milik user; status/izin diverifikasi online pada request mutasi agar revoke efektif.
5. Akses OAuth client ke direct Supabase Data API ditutup atau dipersempit sehingga tidak bisa melewati approval/limits. Jangan berasumsi `authenticated` + `auth.uid()` saja sudah aman untuk third-party OAuth.
6. Supabase secret/service-role key hanya di backend terisolasi; frontends dan agents hanya memakai public publishable key ketika diperlukan untuk auth yang sah.
7. Throttling login, consent anti-CSRF, PKCE, secure redirect allowlist, rotating signing keys, minimal data response, non-sensitive error messages.
8. Bila remote client tidak mendukung authorization flow yang diperlukan, tampilkan unsupported guidance, jangan diam-diam downgrade ke anonymous/static universal token.

### 6.6 MCP tool contract

| Tool | Input inti | Output / side effect |
|---|---|---|
| `get_financial_summary` | period, currency, account_ids | angka + breakdown + calculation metadata |
| `list_accounts` | cursor, status | akun milik user |
| `list_transactions` | range, account_ids, category_ids, tags, search, cursor | paged rows, count, filter echo |
| `get_transaction` | transaction_id | satu transaksi, ownership enforced |
| `create_transaction` | type, amount_minor, currency, account_id, category_id, timestamp, idempotency_key | posted/pending action result |
| `update_transaction` | transaction_id, patch, expected_version, idempotency_key | updated or needs_approval |
| `request_delete_transaction` | transaction_id, reason, idempotency_key | pending action; jika permission disabled -> denied |
| `get_budget_vs_actual` | period, category filters | budget, actual, remaining, variance |
| `generate_forecast` | period, model, grouping | forecast, known scheduled, confidence/assumptions |
| `simulate_scenario` | scenario changes, timeframe | hypothetical results, no mutations |
| `list_categories` | type, status | owned/default taxonomy |
| `update_budget` | budget_id, amount, version | denied/pending/updated according to policy |
| `request_export_report` | format, range, filters | pending action or export job |
| `get_action_status` | action_id | pending/approved/rejected/executed/failed |

**Tool response statuses:** `ok`, `validation_error`, `permission_denied`, `approval_required`, `pending_approval`, `conflict`, `rate_limited`, `revoked`, `not_found`, `internal_error`; always include `request_id`, minimal user-safe reason, retryable boolean. Structured tool inputs/outputs mengikuti JSON Schema; no arbitrary SQL, no unbounded record dump. Tool listing harus akurat sesuai permission agent.

### 6.7 Agent activity, audit, dan observability

Catat connection create/revoke, consent, permission changes, read audit summary, every mutation proposal, approval outcomes, execution outcomes, denied requests, suspicious patterns, and rate limiting. Fields: event_id, occurred_at, user_id, connection_id, oauth_client_id, tool_name, operation, target_id, request_id, idempotency_key, policy_version, permission_set, approval_id, state, safe before/after diff, result, error_code, IP/user-agent as necessary, actor_type. Data audit append-only terhadap user biasa; admin audit pun tidak memberi hak membaca transaksi pribadi. Token, password, authorization code, raw PDF financial content tidak pernah dicatat ke logs. Retention rekomendasi 365 hari, configurable. Audit log UI dapat difilter berdasarkan agent, date, action, status.

### 6.8 MCP tests (must pass)

- Token client A milik user A tidak dapat membaca/mengubah data user B.
- Agent tidak dapat menambah scope dirinya, termasuk via REST/Supabase Data API.
- Setelah revoke, next authorized request ditolak meski access token belum expire.
- Retry create dengan idempotency key identik hanya menghasilkan 1 transaksi.
- Approval expired/rejected tidak pernah mem-post transaksi.
- Approval user A tidak bisa menyetujui action milik user B.
- Change payload after approval invalidates approval.
- Prompt injection pada import notes/PDF tidak boleh dieksekusi sebagai instruksi agent.
- MCP result dan UI ledger snapshot konsisten setelah sync.

## 7. Admin Panel dan RBAC

### 7.1 Admin page: User Management

Admin sidebar mempunyai `User Management` dan `Admin Audit Logs`. User List mencakup search username/email, status (active/suspended), role, created date, last sign-in (jika metadata valid), sorting, pagination. Row -> User Detail: identitas, status, role, auth summary, login history metadata yang aman, admin actions.

### 7.2 Admin actions

| Action | Requirement |
|---|---|
| Suspend/reactivate | Confirm + reason + audit; block at API, refresh/access token checks |
| Change role | Hanya admin dengan izin khusus; cegah kehilangan admin terakhir |
| Admin-assisted reset password | Generate secure temporary credential; force change on first login; audit; access proof workflow |
| Force logout/revoke sessions | Lakukan revoke yang sesuai dan periksa status sesi pada operasi sensitif |
| Search users | Read admin-safe metadata, bukan transaction details |
| Delete account | Disable -> retention/backup policy -> purge scheduled, double confirm |

**First admin bootstrap:** dibuat melalui deployment/admin script yang terautentikasi di server, **bukan** otomatis akun pertama dan bukan endpoint publik. `admin` tidak dapat self-assign lewat client metadata. Gunakan authorization data server-owned, bukan user-editable metadata. Setiap action admin memerlukan validasi backend walaupun UI admin tersembunyi bagi user biasa.

### 7.3 Admin audit

Columns: actor_admin, target_user, action, reason, old/new role or status, timestamp, request_id, result. Admin audit tidak mengandung password dan tidak mengungkap data finansial user. Tidak dapat dihapus dari UI admin biasa.

## 8. UI/UX specification — professional dark/light, no AI look

### 8.1 Visual identity

Arah: *restrained professional fintech*. Sederhana, padat informasi, relevan; tidak ada pseudo-3D, neon, glassmorphism, glow, gradasi dominan, emoji dekoratif, chatbot di setiap layar, atau bentuk kartu terlalu bulat. Desain bukan menyalin aset aplikasi lain.

### 8.2 Design tokens

| Token | Dark | Light | Usage |
|---|---|---|---|
| `bg.canvas` | `#101317` | `#F7F8FA` | Main canvas |
| `bg.surface` | `#191D22` | `#FFFFFF` | Cards, sidebar |
| `bg.elevated` | `#22272D` | `#EFF2F5` | Hover, subtle secondary |
| `border.default` | `#30363D` | `#DFE3E8` | Dividers, input outlines |
| `text.primary` | `#EDF0F2` | `#20252B` | Main text |
| `text.secondary` | `#9BA4AE` | `#68727D` | Supporting labels |
| `accent.primary` | `#7B9BC0` | `#456D9A` | Selected nav, links |
| `finance.positive` | `#72B39A` | `#287C60` | Income, positive variance |
| `finance.negative` | `#D88989` | `#B64D52` | Expense, overbudget |
| `finance.warning` | `#D6B071` | `#A76A22` | Warning |

Typography: Inter (fallback platform sans), base 14px on web desktop / 15–16sp mobile, headings 18/22/28, line-height 1.4–1.6, numeric values tabular/monospaced figures, no all-caps paragraph text. Spacing scale `4,8,12,16,24,32`. Card radius 8px (range 6–10); button radius 8; default border 1px; shadows minimal or none. Touch target minimum recommended 44–48 logical px, keyboard focus visible. Animations 120–200ms, respect reduced motion.

### 8.3 Core components

- Sidebar item: 20px outline icon, text label, active background with muted tint and 2px active indicator (subtle).
- Topbar: breadcrumb/title, period switcher, global search, profile, notification.
- KPI tiles: small context label, large aligned number, optional subtle trend; no giant decorative icons.
- Inputs: clear labels, helper/error below, no placeholder-only identification.
- Tables: sticky header, right aligned numeric columns, zebra only when needed, row menu, safe responsive fallbacks.
- Charts: reduced palette, axis units, legend, accessible table view, no unnecessary 3D.
- Empty states: concise explanation + primary action, minimal line illustration optional.
- Toasts: operation success/failure, undo when safe; errors with actionable next step.
- Confirmation modal: action summary, consequences, destructive emphasis when appropriate.
- Drawer: modal overlay on mobile, focus trap, swipe/back close, no bottom navigation.

### 8.4 Screen-level layouts

**Dashboard desktop:** fixed left sidebar; topbar with period; first row Balance, Income, Expense, Net Cashflow; second row cashflow chart (2/3) + budget status (1/3); third row recent transactions, upcoming bills, forecast alerts. Mobile: same data as stacked sections, scrollable; quick add FAB allowed as an *action* (not navigation), accessible from topbar as well.

**Transactions desktop:** filter toolbar; saved views; transactions table with date, merchant/name, account, category, tags, amount, status; right-side detail drawer or route; `Add Transaction` visible. Mobile: filter chips + search, transaction cards grouped by date, `Add` primary action topbar; advanced filter via full-height sheet/page. Menu actions available per-row.

**Transaction Form:** segmented Income/Expense/Transfer; amount prominent; account, category, date/time, merchant, notes, tags, custom fields and attachment collapsible advanced section; Save and Save & Add Another; unsaved change guard; inline validation. Transfer mode swaps category field with destination account.

**Budgets:** category rows with budget, actual, remaining, forecast and dual progress indicators; sort by overspend; drilldown filtered transactions; clear timeframe label. Mobile uses one category per section, numbers maintain same meaning.

**Forecast:** big chart actual solid vs forecast dotted, target/budget guide line, model selector, known scheduled list, assumptions panel, sliders/form for scenario; explicit 'Simulation only' visual marker. Expose historical accuracy once P1 enabled.

**Import:** Select file, detect, mapping preview (10–50 sample rows), row validation badges, duplicates review, final confirmation, job result/errors. PDF import previews extracted text rows; user must verify confidence. Mobile steps in full-screen wizard; desktop 2-column preview/mapping.

**Export:** choose format CSV/PDF, dataset transactions/budget/forecast, range or saved filter, include summary, initiate job; display download/share once ready. All report operations linked to filter snapshot at initiation.

**API & AI Agents:** Connected Agents table/list, Connect Agent, permissions read/write toggles, numeric thresholds, account restrictions, pending approvals, activity log, revoke, emergency pause. Agent profile shows last used, tools permitted, consent date, recent actions. Mobile parity via stacked sections.

**Admin:** User Management table/list, search/filter, user detail drawer/page, suspend/reactivate, change role, reset password, audit; require explicit confirmation and reason.

**Settings:** profile, timezone/locale, base currency IDR (configurable), week start, theme dark/light/system, privacy, sessions, imports defaults, export defaults, data backup/restore, accessibility.

### 8.5 UX microflows

| Flow | Interaction sequence | Failure / edge behavior |
|---|---|---|
| First-time signup | Fields -> validation -> create -> initialize default categories -> dashboard | Username collision, network retry, partial profile initialization roll-forward |
| Quick transaction | Dashboard Add -> amount -> category/account -> Save -> optimistic display | Duplicate tap locked, status pending until server confirmed |
| Transfer | Select Transfer -> from/to -> amount -> confirm -> balance update | Same source/destination blocked, currency rule verified |
| Filter/export | Choose Month + category -> list updates -> Export -> format -> confirm -> file | Export honors exact filter snapshot |
| CSV import | Choose -> map -> preview -> duplicates -> confirm -> result | Partial errors downloadable, successful rows not retried |
| PDF import | Choose PDF -> extract -> confidence/review -> mapping -> confirm | Unreadable pages clearly flagged; cannot silently insert wrong values |
| MCP consent | Agent connect -> OAuth flow -> consent -> app permissions -> connected | Unknown agent rejected, revocation accessible |
| Agent write approval | Proposed operation -> pending inbox -> user approve -> verified execution | Expire/deny/revoke -> no mutation |

### 8.6 Accessibility & localization

- Keyboard support for all desktop controls; focus indicators and form error announcements.
- Contrast target WCAG AA for text and interactive components; never rely solely on green/red for status.
- Screen-reader labels for money values, icons, progress, buttons, charts.
- Dark and Light are equal first-class themes, including data visualization colors.
- Default locale Indonesian (`id-ID`), currency `IDR`, timezone `Asia/Jakarta`; timezone customizable with currency-independent ledger.
- Internationalization-ready string resources (EN planned), decimal separator/CSV locale disambiguation, reduced motion, text scaling, responsive at 200% zoom.

## 9. Technical architecture dan data integrity

### 9.1 Logical deployment

```text
Flutter shared Dart application
  |-- Flutter Web (responsive desktop/tablet/browser)
  |-- Flutter Android / iOS (responsive sidebar drawer)
  |-- Shared design system, business DTOs, validation, routing
  |-- Local encrypted cache + offline mutation queue [P1]
                 |
                 v
        Finance API / Service Layer
       /      |        |          \
      Auth  REST v1   MCP Server  Background workers
       \      |        |          /
                 v
        Supabase PostgreSQL (RLS)
        Supabase Storage (private)
        Realtime (update signal, not balance engine)
```

**Principle:** Financial writes must go through centralized validated functions/services with atomic database transaction; do not rely on optimistic client balance computations as authoritative. Flutter Web and Mobile share codebase, but file picker, local storage, biometric and download integration need platform adapters.

### 9.2 Supabase responsibilities

- **Auth:** email/password, persistent sessions, role-aware frontend; username mapping handled securely in app API.
- **PostgreSQL:** relational data, ledger, schema constraints, transactions, financial reporting.
- **RLS:** ownership, role restrictions, OAuth `client_id` restrictions; views with security invoker or private schema as needed.
- **Storage:** per-user private buckets for attachments/import temp/export temp; signed URLs scoped/expiring.
- **Realtime:** transaction/budget changes trigger refresh/invalidation; not guaranteed message ordering and not authority for balance.
- **Edge Functions:** small operations, OAuth-adjacent logic, import/export orchestration, MCP if compatible with workload; heavy PDF processing/workers may use dedicated backend.

### 9.3 Ledger model (recommended)

For dependable balances use `journal_entries` (one economic event) and `journal_lines` (2+ lines per entry, balanced by currency), with business-level `transactions` containing user-friendly fields and links to ledger entry. Account balances are computed from posted journal lines, optionally cached via transactional materialized summaries. For personal finance, an expense posts decrease to asset plus increase to expense account; income posts increase to asset plus increase to income offset (ledger sign convention documented). Transfers post debit/credit among assets and remain neutral to income/expense. All journal entries need idempotency, version and reversal chain. `posted` entries are never silently overwritten; correction posts an adjusting/reversal entry while UI shows edited logical transaction.

### 9.4 Monetary and date rules

- **Amounts:** PostgreSQL `NUMERIC(20,4)` or integer minor units (with currency exponent metadata); never IEEE float for authoritative money.
- **Multiple currencies:** store original amount and currency, base conversion for analytics only with explicit FX source/time. No aggregation across currencies without conversion policy.
- **Time:** timestamps UTC with user timezone for reporting; budgeting period boundaries local.
- **Soft delete:** traceable void/reversal, preserve ledger history and audit; retention policy documented.
- **Isolation:** transactions write in DB atomic unit; optimistic concurrency `row_version` for edits.
- **Denormalized balances:** updated transactionally and periodically reconciled with journal lines.
- **Search:** indexed by user_id/effective_at/account/category; cursor pagination for large datasets.

## 10. Proposed PostgreSQL data model

All entities include `id UUID`, `created_at`, `updated_at` where applicable; user-owned entities include `user_id UUID REFERENCES auth.users(id)` and appropriate RLS. Columns shown focus on functional data, not every constraint.

| Table | Key fields | Notes |
|---|---|---|
| `profiles` | user_id, username_normalized, display_name, base_currency, timezone, theme, status | Username unique; auth email remains canonical in Supabase Auth |
| `user_roles` | user_id, role, created_by | Server-owned, no client self-assign |
| `accounts` | user_id, name, type, currency, opening_balance, status | Opening balance posted through journal |
| `categories` | user_id nullable for system template, type, parent_id, name, color, icon, archived | Templates copied/assigned to user |
| `transactions` | user_id, type, status, account_id, destination_account_id, effective_at, amount, currency, category_id, merchant, description, row_version, source | User-friendly economic record |
| `transaction_splits` | transaction_id, category_id, amount | Sum = parent amount; triggers/constraints |
| `journal_entries` | user_id, transaction_id, posted_at, status, reversal_of | Economic events |
| `journal_lines` | entry_id, ledger_account_id, amount_signed, currency | Balanced per entry/currency |
| `transaction_templates` | user_id, name, payload_json, favourite, sort_order | Sanitized prefill only |
| `custom_field_definitions` | user_id, entity_type, field_key, field_type, options_json | Validation definition |
| `custom_field_values` | transaction_id, field_definition_id, value_json | Type-safe app validation |
| `tags` / `transaction_tags` | user_id, name; transaction_id, tag_id | Many-to-many |
| `budgets` | user_id, name, category_id, amount, currency, cadence, rollover | Budget template |
| `budget_periods` | budget_id, start_at, end_at, planned_amount, version | Period snapshot |
| `forecast_runs` | user_id, period, method, model_version, assumptions_json, totals_json | Reproducibility |
| `forecast_points` | run_id, date, actual_amount, predicted_amount, lower, upper | Charts, historical errors |
| `forecast_scenarios` | user_id, base_run_id, changes_json, result_json | Simulation only |
| `recurring_rules` | user_id, next_at, cadence, payload_json, mode, active | Idempotent schedule |
| `savings_goals` / `goal_allocations` | user_id, target_amount, target_date; goal_id, amount | Distinguish allocations vs expenses |
| `debts` / `debt_payments` | principal, rate, due; debt_id, transaction_id, principal_paid, interest_paid | Ledger linkage |
| `import_jobs` | user_id, format, status, mapping_json, source_ref, totals_json | Job state |
| `import_rows` | job_id, line_no, normalized_json, confidence, disposition, error_code | Preview and review |
| `export_jobs` | user_id, type, format, filter_snapshot, status, output_path, expires_at | Private output |
| `agent_connections` | user_id, oauth_client_id, display_name, status, connected_at, revoked_at | Ownership |
| `agent_permissions` | connection_id, permission, enabled, updated_at | Internal app scopes |
| `agent_policies` | connection_id, limits_json, account_allowlist, approval_mode | Dynamic checks |
| `agent_pending_actions` | connection_id, user_id, payload_hash, payload_json, expected_version, expires_at, status | Immutable proposal |
| `agent_executions` | action_id, idempotency_key, execution_result, executed_at | Exactly-once outcome semantics |
| `agent_audit_logs` | connection_id, user_id, event_type, tool, actor, safe_diff_json, outcome | Append-only |
| `admin_audit_logs` | admin_user_id, target_user_id, action, reason, result, timestamp | Admin actions only |
| `idempotency_records` | user_id, operation, key, request_hash, response_ref, expires_at | Unique scoped keys |

**Indexes:** `profiles(username_normalized)` unique; `(user_id,effective_at DESC,id)` transactions; `(user_id,category_id,effective_at)`; `(user_id,status)`; `(connection_id,permission)` unique; `(user_id,operation,key)` idempotency unique. Check constraints for amount > 0, source != target, valid enum/status, appropriate FK ownership. Multi-user FK ownership needs server validation or composite keys to prevent attaching user's transaction to another user's category/account.

### 10.1 Data retention & backup

- Full backup/restore includes transactions, accounts, categories, custom fields, templates, budgets, goals, recurring rules, and settings; native JSON/ZIP package with manifest and checksums (P1), separate from CSV/PDF export.
- Exports stored in private storage with short-lived download URLs; expired files purged.
- DB backups and point-in-time restore depend on selected Supabase plan/operational setup; review availability and retention before launch.
- Account deletion needs explicit policy for audit and financial-data purging, consistent with local laws and privacy commitments.

## 11. REST API specification outline

### 11.1 Conventions

Base route `/api/v1`; bearer auth; `Idempotency-Key` for mutating operations; request JSON; UTC timestamps ISO 8601; monetary amounts as decimal strings or minor-unit integers; errors `{code,message,request_id,details?}`; cursor pagination `limit`, `cursor`; API timeouts and rate limits documented. Versioning with backward-compatibility policy.

| Resource | Methods / endpoints | Purpose |
|---|---|---|
| Accounts | `GET /accounts`, `POST /accounts`, `PATCH /accounts/{id}` | Manage wallets |
| Transactions | `GET /transactions`, `POST /transactions`, `GET/PATCH /transactions/{id}` | Transaction CRUD |
| Transfers | `POST /transfers` | Atomic transfer |
| Categories | `GET/POST /categories`, `PATCH /categories/{id}` | Taxonomy |
| Templates | `GET/POST /transaction-templates`, `PATCH/DELETE /.../{id}` | Reusable transaction |
| Budgets | `GET/POST /budgets`, `PATCH /budgets/{id}` | Planning |
| Analytics | `GET /analytics/summary`, `/analytics/categories`, `/analytics/cashflow` | Reporting |
| Forecast | `GET /forecasts`, `POST /forecasts/simulate` | Predictions |
| Import | `POST /imports`, `GET /imports/{id}`, `POST /imports/{id}/confirm` | Two-step import |
| Export | `POST /exports`, `GET /exports/{id}` | Async reporting |
| Agents | `GET/POST /agents/connections`, `PATCH /agents/connections/{id}` | Agent lifecycle |
| Approvals | `GET /agents/approvals`, `POST /agents/approvals/{id}/approve|reject` | Trusted UI only |
| Audit | `GET /agents/audit` | User-owned agent logs |
| Admin | `GET /admin/users`, `POST /admin/users/{id}/suspend|reactivate|reset-password` | Role-gated operations |

### 11.2 Representative contract examples

**Create expense request:**

```json
{
  "type": "expense",
  "amount_minor": 35000,
  "currency": "IDR",
  "account_id": "<account-uuid>",
  "category_id": "<category-uuid>",
  "effective_at": "2026-11-07T10:00:00+07:00",
  "description": "Makan siang"
}
```

**Budget vs actual response:**

```json
{
  "period": {"start": "2026-11-01", "end": "2026-11-30", "timezone": "Asia/Jakarta"},
  "currency": "IDR",
  "budget_minor": 5000000,
  "actual_minor": 2800000,
  "forecast_eop_minor": 6000000,
  "remaining_minor": 2200000,
  "projected_variance_minor": -1000000,
  "forecast_method": "run_rate_v1",
  "assumptions": ["14 hari elapsed", "30 hari in period", "tanpa jadwal future terpisah"]
}
```

## 12. Sync, offline, error handling, dan resilience

**P0:** online-first dengan cache list dan pengiriman ulang idempotent untuk jaringan terputus, plus recovery screen. **P1:** offline-first queue dengan local persistent database di mobile dan browser IndexedDB adapter di web, sync cursors, upload retries, conflict detection.

- Client-generated UUID untuk pending operations; `idempotency_key` konsisten saat retry.
- Queue record menyimpan action, payload_hash, created_at, retry_count, expected_version, status.
- Ubah row yang diedit dua perangkat menggunakan optimistic `row_version`: jika konflik, tampilkan compare/resolve, bukan last-write-wins diam-diam pada nominal.
- Data server authoritative; UI menampilkan `Pending sync`, `Synced`, `Conflict`, `Failed`.
- Realtime event berarti **refresh hint**, bukan eksekusi transaksi kedua.
- Setelah reconnect, queue dikirim urut untuk operasi terkait akun yang sama; setiap request punya retry budget dan backoff.
- Jika import/export worker gagal, job berada di status terminal yang eksplisit dan menyediakan retry aman.

## 13. Non-functional requirements

| Area | Baseline requirement / target |
|---|---|
| Security | HTTPS/TLS, RLS, server authz, no secrets in client, log sanitization |
| Privacy | User data isolated; private attachments; consent for agent exports |
| Performance | Typical filtered list <= 1.5s p95 (target), dashboard <= 2s p95 on tested baseline |
| Reliability | Finance writes atomic; idempotent retries; monitor failed jobs and ledger imbalance |
| Accessibility | WCAG AA target; keyboard/focus/screen-reader; no color-only status |
| Availability | Target defined before production SLA; clear degraded/offline states |
| Capacity | Cursor paginate 100k+ transactions/user; indexes and lazy aggregation |
| Observability | Structured logs + metrics with PII redaction; correlation/request IDs |
| Maintainability | Shared Flutter code, versioned service API, migrations, migration rollback plan |
| Testability | Unit, integration, RLS, contract, golden UI, E2E, performance, chaos testing |
| Internationalization | id-ID first, EN-ready, multi-currency data model |
| Backup & restore | Verified database backups; documented restore drills |
| Data protection | Retention and deletion policies; export files short-lived |

**Performance numbers are proposed targets, not measured outcomes.** Define benchmark device/network and data volume before making a production promise.

## 14. QA plan and acceptance criteria

### 14.1 Automated tests

- **Unit:** amount arithmetic, splits, category rollups, period boundaries, budget variance, forecast assumptions, CSV quoting, PDF templates.
- **DB integration:** balanced journal, FK ownership, RLS select/insert/update/delete for anon/authenticated/OAuth client, idempotency constraints.
- **API contracts:** OpenAPI schema conformance, invalid input, duplicate retry, authorization and status codes.
- **MCP compatibility:** list tools, call tools, structured response, OAuth discovery, consent, revoke, malicious tool calls.
- **Flutter widget/golden:** light/dark, responsive width, text scale, sidebar/drawer, form validation, approval modal.
- **End-to-end:** signup -> create account -> add expense -> budget -> forecast -> export -> import -> agent mutation -> audit -> admin suspend.
- **Property-based testing:** random transfer/balanced ledger, CSV round-trip, no negative net balance from mere transfer, split summation.

### 14.2 Acceptance matrix (minimum)

| ID | Scenario | Expected result |
|---|---|---|
| AC-01 | Signup valid tanpa confirm email | Session langsung aktif; profiles/default categories tersedia |
| AC-02 | Username sama berbeda kapital | Unique enforcement case-insensitive |
| AC-03 | Email tak dikenal login | Generic auth error, no enumeration leak |
| AC-04 | User suspended mencoba API | Server menolak, bukan sekadar UI hide |
| AC-05 | Create expense Rp35.000 dari Cash | Saldo Cash turun Rp35.000; actual expense naik Rp35.000 |
| AC-06 | Transfer Cash -> Bank Rp100.000 | Total asset tidak berubah; cashflow expense/income tetap |
| AC-07 | Duplicate POST request idem key sama | Hanya satu transaction dan ledger entry |
| AC-08 | Month November filter | Termasuk Nov 1 00:00 hingga Nov 30 23:59:59.999 local |
| AC-09 | Custom range timezone Asia/Jakarta | Boundaries tepat, tidak off by one day |
| AC-10 | Import CSV 100 baris, 10 duplicate | Preview 10 flagged; user memilih tindakan; final count cocok |
| AC-11 | Import PDF digital ambigu | User review wajib; tidak silent-import data salah |
| AC-12 | Import PDF scanned tanpa OCR P0 | Pesan unsupported/need OCR, no corruption |
| AC-13 | Export CSV/PDF dengan filter sama | Jumlah/nilai transaksi sama setelah format logic accounting diterapkan |
| AC-14 | Budget 5jt, actual 2.8jt, forecast 6jt | Remaining 2.2jt; projected variance -1jt |
| AC-15 | Forecast scenario tambah expense 1jt | Simulasi berubah, original transaction tidak |
| AC-16 | MCP agent create expense <= limit | Tercatat dengan actor_type agent dan audit |
| AC-17 | MCP create > limit | Approval required; no journal write before approve |
| AC-18 | Agent self-approves | Rejected; trusted user session required |
| AC-19 | Revoke agent dan retry request | Access denied immediately by server policy |
| AC-20 | Agent memakai token user A untuk item user B | Denied/no information leak |
| AC-21 | Admin reset password user | Temporary credential + forced change + admin audit |
| AC-22 | Admin ordinary queries user's finances | Denied unless specifically lawful product authorization exists |
| AC-23 | Fitur P0 sama di Web dan Flutter | Parity checklist lulus untuk kedua |
| AC-24 | Mobile viewport kecil | Drawer available; no bottom nav; no clipped currency text |
| AC-25 | Dark/light themes | Contrast readable, no neon/glow, no chart color-only dependency |

## 15. Delivery plan, dependencies, dan milestones

| Phase | Output | Exit gate |
|---|---|---|
| 0. Architecture & design | PRD frozen, design tokens, flow maps, ERD, API contract | Sign-off data model & threat model |
| 1. Identity & accounts | Flutter scaffold, sidebar, dark/light, Supabase Auth, profiles, admin bootstrap | Auth, RBAC, basic accessibility |
| 2. Transactions core | Accounts, categories, templates, journal, transactions, filters | Ledger reconciliation, RLS tests |
| 3. Planning & analytics | Dashboard, budgets, actual, forecast basic, reports | Numbers test suite and parity |
| 4. Data portability | CSV/PDF import/export, mapping, duplicate checks | Round-trip and PDF review tests |
| 5. MCP/REST | API, OAuth, MCP tools, consent/approval, audit | Security and revocation E2E |
| 6. Admin and release | Admin page, monitoring, feature parity regression | UAT and release checklist |
| 7. Enhancements | Offline P1, recurring, debts, goals, confidence models | Release separately with parity |

**Dependencies:** Supabase project and environment separation (dev/staging/prod), host/domain for redirect/MCP discovery, email delivery decision for administrative account support, file storage policy, job processing infrastructure for PDF exports/imports, charting/CSV/PDF Flutter libraries selected during spike. Track version pinning and lockfiles.

## 16. Risks, trade-offs, dan decisions

| Risk / decision | Impact | Mitigation |
|---|---|---|
| Sign-up without email verification | Email may be owned by someone else; account recovery dispute | UI warning, anti-abuse limits, admin verification process, optional verification future |
| No self-service password reset | Lost access without admin | Admin-assisted reset, require identity proof, clear help instructions |
| Flutter Web one codebase | SEO and desktop-native table experience may differ vs Next.js | Responsive widgets, web keyboard/mouse optimization; SEO not product priority |
| Realtime interpreted as strong consistency | Duplicate/lagged UI | Server authoritative ledger, refetch and sync cursor |
| MCP OAuth scopes not custom-native | Overbroad DB access if RLS naive | Per-client RLS + service checks + block direct Data API bypass |
| PDF import nonstandard | Extraction errors | Review gate, confidence warnings, OCR phase gating |
| Multi-currency | Misleading totals | Explicit base FX and original amount preservation |
| Forecast with sparse history | Misleading predictive confidence | Method labels, low confidence, known scheduled separation |
| Admin reset security | Social engineering and privilege abuse | Admin audit, proof policy, temporary password, forced change |
| Operational complexity | Async jobs, receipts, approvals | Staged releases, observability, clear error recovery |

### 16.1 Decisions locked by user

- Sidebar navigation di **Web dan Flutter**, bukan bottom nav.
- Visual professional minimal, light/dark, tanpa neon/glass/AI look.
- Features same in Web and Flutter; shared Flutter codebase with adaptive layouts.
- Supabase PostgreSQL as core backend.
- Signup requires username/email/password/confirmation; email verification disabled.
- No self-service password reset at launch; admin user management provided.
- Support custom categories/templates/transactions and filtering Day/Week/Month/Year/custom.
- Import dan export **CSV dan PDF**; parsing PDF digital in P0 and OCR scan in later phase.
- Budget vs Actual with forecast.
- REST API and remote MCP to allow AI agent Read & Write with policy/approval/audit.

### 16.2 Proposed defaults still configurable / needing implementation sign-off

- Agent auto-write cap Rp1.000.000 and small-edit limit Rp250.000; daily caps/account allowlists.
- Agent approval expiry 10 minutes; logs retention 365 days.
- P0 online-first with P1 full offline queue; user originally asked synchronized platform, not explicitly guaranteed full offline MVP.
- PDF scanned OCR deferred; digital PDF import P0.
- Username 3–24 chars; password >=8; stronger strength hints.
- Amount representation uses integer minor units for API, NUMERIC ledger, no floats.

## 17. Glossary

| Term | Definition |
|---|---|
| Actual | Realisasi dari posted transactions yang relevan |
| Budget | Rencana maksimum/target penggunaan untuk periode tertentu |
| Forecast EOP | Estimasi realisasi akhir periode menggunakan data yang tersedia |
| Remaining budget | Budget satu periode dikurangi actual-to-date |
| Projected variance | Budget full period dikurangi forecast end-of-period |
| Internal transfer | Perpindahan dana antar akun user, net asset unchanged |
| Ledger | Catatan jurnal debit-kredit yang menjadi basis saldo |
| MCP | Model Context Protocol, antarmuka tools untuk AI agent |
| Agent connection | OAuth client + grants + application permissions untuk user tertentu |
| Approval | Persetujuan user melalui aplikasi terpercaya sebelum action berisiko |
| RLS | Row Level Security di PostgreSQL untuk isolasi data |
| Idempotency | Retry request yang sama tidak menggandakan side effects |
| Feature parity | Kapabilitas setara pada Web dan Flutter, layout boleh berbeda |

## 18. Annotated UI wireframes (layout blueprint)

### 18.1 Web / desktop dashboard

```text
+----------------------+--------------------------------------------------------------+
| FINANCE TRACKER      | Dashboard                  [Nov 2026 v] [Search] [Profile]  |
|                      +--------------------------------------------------------------+
| OVERVIEW             | [Total Balance] [Income] [Expense] [Net Cash Flow]          |
|  > Dashboard         |                                                              |
|    Transactions      | [Cash Flow: Actual / Forecast ........................]    |
|    Accounts          | [Chart with period selector, tooltip, legend             ]    |
|    Analytics         |                                                              |
| PLANNING             | [Budget vs Actual]     [Upcoming Bills / Alerts]             |
|    Budgets           |                                                              |
|    Forecast          | [Recent Transactions Table: date, account, amount, status]  |
| MANAGEMENT           |                                                              |
|    Import & Export   |                                                              |
| SYSTEM               |                                                              |
|    API & AI Agents   |                                                              |
+----------------------+--------------------------------------------------------------+
```

**Web interactions:** sidebar collapse icon-only, persistent search/filter, keyboard shortcuts (optional), table sorting, stable chart legends, responsive chart drilldown, high density without tiny hit targets. Critical totals remain visible without scrolling on typical desktop 1366x768 where feasible.

### 18.2 Mobile dashboard with sidebar drawer

```text
+----------------------------------+
| [hamburger] Dashboard  [profile] |
+----------------------------------+
| NOVEMBER 2026             [v]    |
| Total Balance                    |
| Rp 12.450.000                    |
+----------------------------------+
| Income          | Expense        |
| Rp 6.000.000    | Rp 3.850.000   |
+----------------------------------+
| Cash Flow [chart / compact]      |
+----------------------------------+
| Budget vs Actual                 |
| [progress]      [See details]    |
+----------------------------------+
| Recent transactions              |
| Lunch                  -35.000   |
| Salary              +6.000.000   |
+----------------------------------+
| [Add transaction action]         |
+----------------------------------+
```

**Mobile interactions:** hamburger opens left drawer; no bottom navigation, floating *Add Transaction* action is acceptable but optional. Form fields are full width; sticky Save CTA only inside editing flows. Drawer shows same menu entries as desktop including Admin for admins.

### 18.3 Desktop transaction entry and approvals

```text
ADD TRANSACTION
[ Expense | Income | Transfer ]
[ Amount: Rp __________ ]     [ Account: __________ ]
[ Category: __________ ]       [ Date/Time: ________ ]
[ Merchant: __________ ]       [ Template: _________ ]
[ Description _____________________________________ ]
[ Tags ] [ Attach receipt ] [ Advanced custom fields ]
                        [Cancel] [Save] [Save & Add Another]

AGENT APPROVAL
Agent: OpenCode (example)           State: Pending - expires in 10m
Requested: Update expense "Transport" Rp50.000 -> Rp500.000
Account: Cash   Category: Transport   Delta: +Rp450.000
Reason: Requested by external agent
                         [Reject] [Approve change]
```

**UI guardrails:** human-readable preview, no approvals granted through MCP, changed payload invalidates prior approval, success/failure states always visible. Avoid showing tokens in approval views.

## 19. Source references and implementation notes

Sumber berikut adalah rujukan teknis untuk implementasi. Selalu cek perubahan versi sebelum coding/deployment:

1. Supabase Auth OAuth 2.1 Server: https://supabase.com/docs/guides/auth/oauth-server
2. Supabase OAuth flows (custom scopes availability): https://supabase.com/docs/guides/auth/oauth-server/oauth-flows
3. Supabase OAuth token security and RLS: https://supabase.com/docs/guides/auth/oauth-server/token-security
4. Supabase Row Level Security: https://supabase.com/docs/guides/database/postgres/row-level-security
5. Supabase Edge Functions: https://supabase.com/docs/guides/functions
6. Supabase Auth configuration (Confirm Email): https://supabase.com/docs/guides/auth/general-configuration
7. MCP specification 2025-11-25, Authorization: https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization
8. MCP specification 2025-11-25, Transports: https://modelcontextprotocol.io/specification/2025-11-25/basic/transports
