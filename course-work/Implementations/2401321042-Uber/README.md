# Uber – база данни, Data Warehouse и Power BI отчет

| | |
|---|---|
| **Студент** | Шефкет Молаали |
| **Факултетен номер** | 2401321042 |
| **Тема (платформа)** | Uber |

## Описание

**Uber** е платформа за поръчка на превоз (ride-hailing), която свързва пътници с шофьори в реално време. Пътникът заявява курс и избира тип превоз (UberX, Comfort, Black, XL, Green). Системата намира свободен шофьор в същия град и изчислява цената по тарифата, натоварването (surge) и евентуален промо код. След курса се записва плащане, а пътникът и шофьорът се оценяват взаимно.

Проектът моделира платформата на три нива:

1. **OLTP база `UberDB`** (MS SQL Server) – 12 таблици, ~6 200 курса за периода 01.2025 – 10.2026 в 8 европейски града, с функции, процедури и тригери.
2. **Data Warehouse `UberDW`** – звездна схема с 3 таблици факти и 9 таблици измерения, заредена чрез ETL процедура.
3. **Power BI отчет** върху `UberDW`.

## Структура

```
course-work/Implementations/2401321042-Uber/
├── README.md
├── database/
│   ├── 01_create_oltp.sql        – UberDB: таблици, ключове, ограничения, индекси
│   ├── 02_programmability.sql    – функции, съхранени процедури, тригери
│   ├── 03_seed_data.sql          – данни (+ демонстрация на процедурите и тригерите)
│   ├── 04_create_dw.sql          – UberDW: звездна схема
│   ├── 05_etl_load_dw.sql        – ETL процедура usp_LoadDW + първоначално зареждане
│   └── install.ps1               – пуска всичко наведнъж
├── diagrams/
│   ├── conceptual_chen.drawio (+ .png)    – концептуален модел (Chen)
│   ├── logical_crowsfoot.drawio (+ .png)  – логически модел (Crow's Foot)
│   └── dw_uml.drawio (+ .png)             – физически модел на DW (UML)
└── powerbi/
    ├── Uber-report.pbix          – Power BI отчетът
    ├── Uber - pdf.pdf            – отчетът във формат PDF
    ├── POWERBI_GUIDE.md          – как е изграден отчетът
    └── measures.dax              – DAX мерки
```

## Изпълнение на изискванията

| Изискване | Реализация |
|---|---|
| Концептуален модел (Chen) | `diagrams/conceptual_chen.drawio` – 11 същности (вкл. слабата същност `TripStatusLog`), 14 връзки с кардиналност, ключови и производни атрибути, атрибути на M:N връзка |
| Логически модел (Crow's Foot) | `diagrams/logical_crowsfoot.drawio` – **12 таблици** (изискване: ≥ 6), **95 атрибута** (≥ 30) |
| Връзка много към много | `Riders` ⟷ `PromoCodes` чрез `RiderPromoCodes` (пътник получава много кодове, код се дава на много пътници). Съставен FK `Trips(RiderID, PromoCodeID)` гарантира, че курсът ползва само код, присвоен на същия пътник |
| База данни в MS SQL Server | `UberDB` – PK, FK, UNIQUE, CHECK, DEFAULT ограничения и индекси |
| Функция | `fn_CalculateFare` (скаларна – цена по тарифа, surge и промо код), `fn_GetDriverEarnings` (таблична – приходи на шофьор за период) |
| Съхранена процедура | `usp_RequestTrip`, `usp_StartTrip`, `usp_CompleteTrip`, `usp_CancelTrip`, `usp_RateTrip`, `usp_GetCityStatistics` |
| Тригер | `trg_Ratings_UpdateAverages` (средни оценки), `trg_Trips_StatusLog` (одит на статусите), `trg_Drivers_SoftDelete` (INSTEAD OF DELETE → деактивиране) |
| Данни | 8 града, 5 типа превоз, 300 пътници, 80 шофьори, 88 автомобила, 11 промо кода, ~6 200 курса, ~5 600 плащания, ~4 300 оценки |
| Data Warehouse (≥ 3 факта, ≥ 6 измерения), UML | `UberDW` + `diagrams/dw_uml.drawio` – факти: `FactTrips`, `FactPayments`, `FactRatings`; измерения: `DimDate`, `DimTime`, `DimCity`, `DimRider`, `DimDriver`, `DimVehicle`, `DimPaymentMethod`, `DimPromoCode`, `DimTripStatus` |
| Power BI (≥ 3 визуализации) | 11 визуализации на 3 страници – вижте `powerbi/POWERBI_GUIDE.md` |

### Допълнения извън условието

- **ETL процедура** `UberDW.dbo.usp_LoadDW` с журнал `EtlLog`. Може да се пуска многократно (пълно презареждане в транзакция).
- **Реалистични данни:** растеж през времето, пикови часове, повече нощни курсове през уикенда, по-голям дял плащания в брой в България, шофьори с различно качество. Генераторът е **детерминиран**, така че резултатите са еднакви на всяка машина.
- **Съставен външен ключ** към M:N таблицата и множество CHECK ограничения за валидност на статусите и времената.
- **Транзакции** и `THROW` грешки с ясни съобщения в процедурите.
- **INSTEAD OF тригер** за „меко“ изтриване на шофьори с история.
- **Двуезични измерения** (`DayNameBG`, `MonthNameBG`, `PartOfDayBG`, `StatusNameBG`) за отчет на български.
- **Скрипт за инсталация** с една команда (`install.ps1`).

## Инсталация и стартиране

### Изисквания

- MS SQL Server 2019 или по-нов (Developer/Express) и `sqlcmd`
- SQL Server Management Studio (по желание)
- Power BI Desktop
- draw.io (desktop) или https://app.diagrams.net за диаграмите

### 1. База данни и Data Warehouse

**Вариант А – с една команда (PowerShell):**

```powershell
cd course-work/Implementations/2401321042-Uber/database
.\install.ps1                      # локален сървър по подразбиране
.\install.ps1 -Server ".\SQLEXPRESS"   # именувана инстанция
```

**Вариант Б – през SSMS:** отворете и изпълнете (F5) скриптовете по ред `01` → `02` → `03` → `04` → `05`.

Скриптовете пресъздават `UberDB` и `UberDW` от нулата, затова могат да се пускат многократно.

### 2. Проверка

```sql
USE UberDB;
EXEC dbo.usp_GetCityStatistics '2026-01-01', '2026-10-31';
SELECT TOP 10 * FROM dbo.fn_GetDriverEarnings(NULL, '2025-01-01', '2026-12-31') ORDER BY DriverEarnings DESC;
SELECT dbo.fn_CalculateFare(1, 12.5, 25, 1.30, NULL) AS FareUberX_12km_25min_surge;

-- пълен жизнен цикъл на курс
DECLARE @Trip INT;
EXEC dbo.usp_RequestTrip  @RiderID = 10, @CityID = 1, @VehicleTypeID = 2,
     @PickupAddress = N'Vitosha Blvd 1', @DropoffAddress = N'Sofia Airport, Terminal 2', @TripID = @Trip OUTPUT;
EXEC dbo.usp_StartTrip    @TripID = @Trip;
EXEC dbo.usp_CompleteTrip @TripID = @Trip, @DistanceKm = 11.2, @DurationMin = 24, @PaymentMethodID = 1, @TipAmount = 1.5;
EXEC dbo.usp_RateTrip     @TripID = @Trip, @DriverScore = 5, @RiderScore = 5;
SELECT * FROM dbo.TripStatusLog WHERE TripID = @Trip;   -- записано от тригера

-- презареждане на хранилището след промени
EXEC UberDW.dbo.usp_LoadDW;
```

### 3. Диаграми

Отворете файловете `.drawio` в draw.io (или https://app.diagrams.net). Готовите изображения са във файловете `.png` в същата папка.

### 4. Power BI

Отворете `powerbi/Uber-report.pbix` (или `powerbi/Uber - pdf.pdf` за преглед без Power BI). Ако сървърът ви не е `localhost`, сменете го от **Transform data → Data source settings**. Описание на модела, мерките и визуализациите има в [`powerbi/POWERBI_GUIDE.md`](powerbi/POWERBI_GUIDE.md).
