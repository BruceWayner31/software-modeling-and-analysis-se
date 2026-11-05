# Power BI отчет – стъпка по стъпка

Отчетът се изгражда върху Data Warehouse базата **UberDW**. Отчетът е във файла `Uber-report.pbix`, а PDF версията е в `Uber - pdf.pdf`.

## 1. Свързване с данните

1. Power BI Desktop → **Get data → SQL Server**.
2. Server: `localhost` (или `.\SQLEXPRESS`), Database: `UberDW`, Data Connectivity mode: **Import**.
3. Изберете всички таблици `Dim*` и `Fact*` (без `EtlLog`) → **Load**.
4. **Model view**: Power BI създава връзките автоматично от външните ключове. Проверете, че има 9 + 3 таблици и всички връзки са **1 → \*** от измерението към факта (single direction).
5. **DimDate** → Table tools → **Mark as date table** → колона `FullDate`.
6. Сортиране (Column tools → **Sort by column**):
   - `DimDate[DayNameBG]` и `DimDate[DayName]` по `DayOfWeek`;
   - `DimDate[MonthNameBG]` и `DimDate[MonthName]` по `MonthNumber`;
   - `DimTime[HourLabel]` по `TimeKey`.
7. Скрийте ключовите колони (`*Key`, `TripID`, `PaymentID`, `RatingID`) от Report view, за да е чист списъкът с полета.

## 2. Мерки

Създайте празна таблица (**Home → Enter data**, име `_Measures`) и добавете мерките от [`measures.dax`](measures.dax) с **New measure**. Форматирайте:

- `Net Revenue`, `Platform Revenue`, `Driver Earnings`, `Avg Fare`, `Gross Bookings` като **Currency (€)**;
- всички мерки с `%` като **Percentage**, с 1 знак след десетичната запетая;
- `Avg Driver Rating` и `Avg Rider Rating` като Decimal с 2 знака.

## 3. Визуализации

### Страница 1 – „Общ преглед“

| # | Визуализация | Полета |
|---|---|---|
| 1 | **Card** (×5) – KPI лента | `Total Trips`, `Net Revenue`, `Avg Fare`, `Cancellation Rate %`, `Avg Driver Rating` |
| 2 | **Line chart** – приходи по месеци | X: `DimDate[YearMonth]`; Y: `Net Revenue`, `Platform Revenue` |
| 3 | **Clustered bar chart** – курсове по град | Y: `DimCity[CityName]`; X: `Completed Trips`, `Cancelled Trips` |
| 4 | **Donut chart** – начини на плащане | Legend: `DimPaymentMethod[MethodName]`; Values: `Net Revenue` |
| 5 | **Slicer** ×2 | `DimDate[Year]` (Tile), `DimCity[CityName]` (Dropdown) |

### Страница 2 – „Търсене и шофьори“

| # | Визуализация | Полета |
|---|---|---|
| 6 | **Matrix** – топлинна карта на търсенето | Rows: `DimDate[DayNameBG]`; Columns: `DimTime[HourLabel]`; Values: `Total Trips` → Conditional formatting → **Background color** (бяло → тъмнозелено) |
| 7 | **Table** – топ 10 шофьори | `DimDriver[FullName]`, `DimDriver[City]`, `Completed Trips`, `Driver Earnings`, `Avg Driver Rating`; Filter: Top N = 10 по `Driver Earnings` |
| 8 | **Clustered column chart** – оценка по тип превоз | X: `DimVehicle[VehicleType]`; Y: `Avg Driver Rating`, `Avg Fare` (secondary axis) |
| 9 | **Stacked column chart** – причини за откази | X: `DimCity[CityName]`; Y: `Cancelled Trips`; Legend: `DimTripStatus[CancelledBy]`; Filter: `DimTripStatus[StatusName] = Cancelled` |

### Страница 3 (по желание) – „Промоции“

| # | Визуализация | Полета |
|---|---|---|
| 10 | **Bar chart** | Y: `DimPromoCode[Code]` (филтър: без `NO PROMO`); X: `Completed Trips`, `Total Discounts` |
| 11 | **Card** | `Promo Usage %`, `Surge Trips %` |

## 4. Какво трябва да се вижда

Данните се генерират детерминирано, затова числата са еднакви на всяка машина:

- около 6 170 курса (01.2025 – 10.2026) с постоянен растеж през тримесечията;
- София е най-големият пазар (~28% от курсовете);
- пикове в търсенето в 08:00 и 17:00–19:00 в делничните дни и нощни курсове през уикенда;
- около 9% откази, средна оценка на шофьорите ~4,5.

## 5. Запис

**File → Save as** → `powerbi/Uber-report.pbix`. За преглед без Power BI: **File → Export → Export to PDF**.
