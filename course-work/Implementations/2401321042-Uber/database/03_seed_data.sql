/* =====================================================================
   Uber – курсова работа
   03. Попълване на UberDB с данни
       - справочни данни (градове, типове превоз, начини на плащане, промо кодове)
       - 300 пътници, 80 шофьори, ~90 автомобила
       - ~6 000 исторически курса (01.01.2025 – 31.10.2026) с плащания и оценки
       - демонстрация на процедурите и тригерите с „живи“ курсове
   Скриптът се пуска върху празна база (след 01 и 02).
   ===================================================================== */
USE UberDB;
GO
SET NOCOUNT ON;
GO

IF EXISTS (SELECT 1 FROM dbo.Trips) OR EXISTS (SELECT 1 FROM dbo.Cities)
    THROW 50100, N'Базата вече съдържа данни. Пуснете отново 01_create_oltp.sql и 02_programmability.sql.', 1;
GO

/* Детерминиран „случаен“ генератор: едни и същи данни при всяко пускане,
   за да съвпадат числата в отчета на всяка машина. Изтрива се в края. */
CREATE OR ALTER FUNCTION dbo.fn_SeedRand (@Id INT, @Salt INT)
RETURNS INT
AS
BEGIN
    RETURN CAST(ABS(CAST(HASHBYTES('MD5', CONCAT(@Id, '|', @Salt)) AS BIGINT)) % 1000000000 AS INT);
END
GO

/* ---------------------------------------------------------------------
   1. Справочни данни
   --------------------------------------------------------------------- */
INSERT dbo.Cities (Name, Country, Currency, SurgeMultiplier, LaunchDate) VALUES
 (N'Sofia',     N'Bulgaria',    'EUR', 1.00, '2023-10-01'),
 (N'Plovdiv',   N'Bulgaria',    'EUR', 1.00, '2024-01-15'),
 (N'Athens',    N'Greece',      'EUR', 1.10, '2019-05-01'),
 (N'Vienna',    N'Austria',     'EUR', 1.00, '2014-04-01'),
 (N'Berlin',    N'Germany',     'EUR', 1.20, '2014-02-01'),
 (N'Paris',     N'France',      'EUR', 1.30, '2012-01-01'),
 (N'Madrid',    N'Spain',       'EUR', 1.00, '2014-09-01'),
 (N'Amsterdam', N'Netherlands', 'EUR', 1.10, '2012-08-01');

INSERT dbo.VehicleTypes (Name, Capacity, BaseFare, PricePerKm, PricePerMinute, MinimumFare) VALUES
 (N'UberX',       4, 2.00, 0.90, 0.25,  5.00),
 (N'Comfort',     4, 2.50, 1.10, 0.30,  7.00),
 (N'Uber Black',  4, 4.00, 1.80, 0.45, 12.00),
 (N'UberXL',      6, 3.50, 1.40, 0.35,  9.00),
 (N'Uber Green',  4, 2.20, 0.95, 0.25,  5.50);

INSERT dbo.PaymentMethods (Name, IsCashless) VALUES
 (N'Credit Card', 1),
 (N'Debit Card',  1),
 (N'Cash',        0),
 (N'Apple Pay',   1),
 (N'Google Pay',  1),
 (N'Uber Cash',   1);

INSERT dbo.PromoCodes (Code, Description, DiscountPercent, MaxDiscount, ValidFrom, ValidTo) VALUES
 (N'WELCOME25',     N'Отстъпка за нови пътници',           50, 10.00, '2025-01-01', '2026-12-31'),
 (N'AIRPORT10',     N'Курсове до/от летище',                10,  4.00, '2025-01-01', '2026-12-31'),
 (N'SUMMER25',      N'Лятна кампания 2025',                 20,  6.00, '2025-06-01', '2025-08-31'),
 (N'STUDENT15',     N'Студентска отстъпка',                 15,  4.00, '2025-09-15', '2026-07-15'),
 (N'BLACKFRIDAY25', N'Black Friday 2025',                   30,  8.00, '2025-11-25', '2025-11-30'),
 (N'XMAS25',        N'Коледни празници 2025',               15,  5.00, '2025-12-15', '2026-01-07'),
 (N'NEWYEAR26',     N'Новогодишна нощ',                     25,  7.00, '2025-12-31', '2026-01-02'),
 (N'SPRING26',      N'Пролетна кампания 2026',              15,  5.00, '2026-03-01', '2026-05-31'),
 (N'SUMMER26',      N'Лятна кампания 2026',                 20,  6.00, '2026-06-01', '2026-08-31'),
 (N'AUTUMN26',      N'Есенна кампания 2026',                20,  5.00, '2026-09-01', '2026-11-30');

-- промо код за демонстрацията в края на скрипта (валиден спрямо датата на пускане)
INSERT dbo.PromoCodes (Code, Description, DiscountPercent, MaxDiscount, ValidFrom, ValidTo)
VALUES (N'DEMO26', N'Демо код за usp_RequestTrip', 30, 6.00,
        DATEADD(DAY, -1, CAST(SYSDATETIME() AS DATE)), DATEADD(DAY, 60, CAST(SYSDATETIME() AS DATE)));
GO

/* ---------------------------------------------------------------------
   2. Пътници и шофьори (имената се комбинират от два списъка)
   --------------------------------------------------------------------- */
DECLARE @First TABLE (n INT IDENTITY(1,1) PRIMARY KEY, Name NVARCHAR(50));
INSERT @First (Name) VALUES
 (N'Ivan'),(N'Maria'),(N'Georgi'),(N'Elena'),(N'Nikolay'),(N'Petya'),(N'Dimitar'),(N'Yana'),
 (N'Alexander'),(N'Sofia'),(N'Kalin'),(N'Victoria'),(N'Martin'),(N'Ana'),(N'Stefan'),(N'Daniela'),
 (N'Lukas'),(N'Emma'),(N'Jonas'),(N'Lea'),(N'Nikos'),(N'Eleni'),(N'Pablo'),(N'Lucia'),
 (N'Hugo'),(N'Chloe'),(N'Daan'),(N'Sanne'),(N'Felix'),(N'Clara'),(N'Mateo'),(N'Ines'),
 (N'Theo'),(N'Mila'),(N'Kostas'),(N'Katerina'),(N'Javier'),(N'Camille'),(N'Max'),(N'Laura');

DECLARE @Last TABLE (n INT IDENTITY(1,1) PRIMARY KEY, Name NVARCHAR(50));
INSERT @Last (Name) VALUES
 (N'Petrov'),(N'Ivanova'),(N'Dimitrov'),(N'Georgieva'),(N'Stoyanov'),(N'Nikolova'),(N'Todorov'),(N'Koleva'),
 (N'Müller'),(N'Schmidt'),(N'Weber'),(N'Fischer'),(N'Papadopoulos'),(N'Georgiou'),(N'Garcia'),(N'Martinez'),
 (N'Lopez'),(N'Fernandez'),(N'Dubois'),(N'Martin'),(N'Bernard'),(N'Lefebvre'),(N'de Jong'),(N'Jansen'),
 (N'de Vries'),(N'Bakker'),(N'Gruber'),(N'Huber'),(N'Wagner'),(N'Bauer'),(N'Angelov'),(N'Hristova'),
 (N'Vasilev'),(N'Marinova'),(N'Popov'),(N'Iliev'),(N'Sanchez'),(N'Moreau'),(N'Visser'),(N'Becker');

DECLARE @FC INT = (SELECT COUNT(*) FROM @First), @LC INT = (SELECT COUNT(*) FROM @Last);

DECLARE @Dial TABLE (CityID INT PRIMARY KEY, DialCode VARCHAR(5), PlatePrefix NVARCHAR(4));
INSERT @Dial VALUES (1,'359',N'CB'),(2,'359',N'PB'),(3,'30',N'ATH'),(4,'43',N'W'),
                    (5,'49',N'B'),(6,'33',N'PA'),(7,'34',N'M'),(8,'31',N'AMS');

-- 300 пътници; София е най-големият пазар (25%)
;WITH N AS (
    SELECT TOP (300) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
), R AS (
    SELECT i,
           CHOOSE(i % 20 + 1, 1,1,1,1,1,2,2,3,3,4,4,5,5,5,6,6,6,7,7,8) AS CityID,
           dbo.fn_SeedRand(i, 1) % 100000000 AS PhoneNo,
           dbo.fn_SeedRand(i, 2) % 16800     AS DobOffset,
           dbo.fn_SeedRand(i, 3) % 912       AS RegOffset
    FROM N
)
INSERT dbo.Riders (FirstName, LastName, Email, Phone, DateOfBirth, RegistrationDate, HomeCityID)
SELECT f.Name, l.Name,
       LOWER(REPLACE(f.Name + N'.' + l.Name, N' ', N'')) + CAST(R.i AS NVARCHAR(10)) + N'@example.com',
       N'+' + d.DialCode + N' ' + RIGHT('00000000' + CAST(R.PhoneNo AS VARCHAR(8)), 8),
       DATEADD(DAY, R.DobOffset, '1960-01-01'),            -- 1960 – 2005
       DATEADD(DAY, R.RegOffset, '2024-01-01'),            -- 01.2024 – 06.2026
       R.CityID
FROM R
JOIN @First f ON f.n = 1 + R.i % @FC
JOIN @Last  l ON l.n = 1 + (R.i / @FC + R.i) % @LC
JOIN @Dial  d ON d.CityID = R.CityID
ORDER BY R.i;

-- 80 шофьори: по 10 във всеки град
;WITH N AS (
    SELECT TOP (80) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
    FROM sys.all_objects
)
INSERT dbo.Drivers (FirstName, LastName, Email, Phone, LicenseNumber, HireDate, CityID, IsActive)
SELECT f.Name, l.Name,
       LOWER(REPLACE(f.Name + N'.' + l.Name, N' ', N'')) + CAST(N.i AS NVARCHAR(10)) + N'@drivers.example.com',
       N'+' + d.DialCode + N' ' + RIGHT('00000000' + CAST(dbo.fn_SeedRand(N.i, 4) % 100000000 AS VARCHAR(8)), 8),
       N'DL-' + d.PlatePrefix + N'-' + RIGHT(N'000000' + CAST(100000 + N.i * 7919 % 900000 AS NVARCHAR(6)), 6),
       DATEADD(DAY, dbo.fn_SeedRand(N.i, 5) % 1090, '2022-01-01'),   -- 2022 – 2024
       1 + (N.i - 1) % 8,
       1
FROM N
JOIN @First f ON f.n = 1 + (N.i + 17) % @FC
JOIN @Last  l ON l.n = 1 + (N.i * 3 + 5 + N.i / @LC) % @LC
JOIN @Dial  d ON d.CityID = 1 + (N.i - 1) % 8
ORDER BY N.i;

/* ---------------------------------------------------------------------
   3. Автомобили: всеки шофьор има активен автомобил; някои имат и стар (неактивен)
      Тип по позиция в града: 1-5 UberX, 6-7 Comfort, 8 Black, 9 XL, 10 Green
   --------------------------------------------------------------------- */
DECLARE @Models TABLE (VehicleTypeID INT, Make NVARCHAR(50), Model NVARCHAR(50));
INSERT @Models VALUES
 (1,N'Toyota',N'Corolla'),(1,N'Skoda',N'Octavia'),(1,N'Volkswagen',N'Golf'),(1,N'Hyundai',N'i30'),(1,N'Kia',N'Ceed'),
 (2,N'Toyota',N'Camry'),(2,N'Skoda',N'Superb'),(2,N'Volkswagen',N'Passat'),
 (3,N'Mercedes-Benz',N'E-Class'),(3,N'BMW',N'5 Series'),
 (4,N'Volkswagen',N'Touran'),(4,N'Ford',N'Galaxy'),(4,N'Toyota',N'Proace Verso'),
 (5,N'Tesla',N'Model 3'),(5,N'Hyundai',N'Ioniq 5'),(5,N'Toyota',N'Prius');

;WITH M AS (
    SELECT VehicleTypeID, Make, Model,
           ROW_NUMBER() OVER (PARTITION BY VehicleTypeID ORDER BY Make, Model) - 1 AS k,
           COUNT(*)     OVER (PARTITION BY VehicleTypeID) AS cnt
    FROM @Models
), D AS (
    SELECT d.DriverID, d.CityID,
           1 + (d.DriverID - 1) / 8 AS Slot
    FROM dbo.Drivers d
), DT AS (
    SELECT D.*,
           CASE WHEN Slot <= 5 THEN 1 WHEN Slot <= 7 THEN 2 WHEN Slot = 8 THEN 3 WHEN Slot = 9 THEN 4 ELSE 5 END AS VehicleTypeID
    FROM D
)
INSERT dbo.Vehicles (DriverID, VehicleTypeID, Make, Model, ProductionYear, PlateNumber, Color, IsActive)
SELECT DT.DriverID, DT.VehicleTypeID, M.Make, M.Model,
       2017 + (DT.DriverID * 3) % 9,
       p.PlatePrefix + N' ' + CAST(1000 + DT.DriverID * 37 AS NVARCHAR(6)) + N' ' + CHAR(65 + DT.DriverID % 26) + CHAR(65 + DT.DriverID * 7 % 26),
       CASE WHEN DT.VehicleTypeID = 3 THEN N'Black'
            ELSE CHOOSE(DT.DriverID % 6 + 1, N'Black', N'White', N'Silver', N'Grey', N'Blue', N'Red') END,
       1
FROM DT
JOIN M ON M.VehicleTypeID = DT.VehicleTypeID AND M.k = DT.DriverID % M.cnt
JOIN @Dial p ON p.CityID = DT.CityID
ORDER BY DT.DriverID;

-- стари (неактивни) автомобили на всеки 9-и шофьор
INSERT dbo.Vehicles (DriverID, VehicleTypeID, Make, Model, ProductionYear, PlateNumber, Color, IsActive)
SELECT v.DriverID, 1, N'Dacia', N'Logan', 2014 + v.DriverID % 4,
       p.PlatePrefix + N' ' + CAST(5000 + v.DriverID AS NVARCHAR(6)) + N' XX',
       N'White', 0
FROM dbo.Vehicles v
JOIN dbo.Drivers d ON d.DriverID = v.DriverID
JOIN @Dial p ON p.CityID = d.CityID
WHERE v.DriverID % 9 = 0;
GO

/* ---------------------------------------------------------------------
   4. Промо кодове към пътници (M:N) – всеки код към ~15% от пътниците
   --------------------------------------------------------------------- */
INSERT dbo.RiderPromoCodes (RiderID, PromoCodeID, AssignedAt)
SELECT r.RiderID, pc.PromoCodeID,
       CAST(CASE WHEN r.RegistrationDate > pc.ValidFrom THEN r.RegistrationDate ELSE pc.ValidFrom END AS DATETIME2(0))
FROM dbo.Riders r
CROSS JOIN dbo.PromoCodes pc
WHERE pc.Code <> N'DEMO26'
  AND r.RegistrationDate <= pc.ValidTo
  AND dbo.fn_SeedRand(r.RiderID * 100 + pc.PromoCodeID, 6) % 100 < CASE WHEN pc.Code = N'WELCOME25' THEN 40 ELSE 15 END;
GO

/* ---------------------------------------------------------------------
   5. Исторически курсове (генерирани)
   --------------------------------------------------------------------- */
DECLARE @EndDate    DATE = '2026-10-31';
DECLARE @RiderCount INT  = (SELECT COUNT(*) FROM dbo.Riders);

-- 5.1 псевдослучайни числа (материализират се веднъж)
IF OBJECT_ID('tempdb..#Gen') IS NOT NULL DROP TABLE #Gen;
WITH N AS (
    SELECT TOP (6800) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
SELECT i,
       dbo.fn_SeedRand(i, 101) % 10000 AS r1,
       dbo.fn_SeedRand(i, 102) % 10000 AS r2,
       dbo.fn_SeedRand(i, 103) % 10000 AS r3,
       dbo.fn_SeedRand(i, 104) % 10000 AS r4,
       dbo.fn_SeedRand(i, 105) % 10000 AS r5,
       dbo.fn_SeedRand(i, 106) % 10000 AS r6,
       dbo.fn_SeedRand(i, 107) % 10000 AS r7,
       dbo.fn_SeedRand(i, 108) % 10000 AS r8,
       dbo.fn_SeedRand(i, 109) % 10000 AS r9,
       dbo.fn_SeedRand(i, 110) % 10000 AS r10,
       dbo.fn_SeedRand(i, 111) % 10000 AS r11,
       dbo.fn_SeedRand(i, 112) % 10000 AS r12,
       dbo.fn_SeedRand(i, 113) % 10000 AS r13,
       dbo.fn_SeedRand(i, 114) % 10000 AS r14,
       dbo.fn_SeedRand(i, 115) % 10000 AS r15,
       dbo.fn_SeedRand(i, 116) % 10000 AS r16,
       dbo.fn_SeedRand(i, 117) % 10000 AS r17,
       dbo.fn_SeedRand(i, 118) % 10000 AS r18,
       dbo.fn_SeedRand(i, 119) % 10000 AS r19,
       dbo.fn_SeedRand(i, 120) % 10000 AS r20,
       dbo.fn_SeedRand(i, 121) % 10000 AS r21,
       dbo.fn_SeedRand(i, 122) % 10000 AS r22,
       dbo.fn_SeedRand(i, 123) % 10000 AS r23,
       dbo.fn_SeedRand(i, 124) % 10000 AS r24
INTO #Gen
FROM N;

-- 5.2 пътник (някои пътуват по-често), град и дата (след регистрацията)
IF OBJECT_ID('tempdb..#S1') IS NOT NULL DROP TABLE #S1;
SELECT g.*, r.RiderID, r.HomeCityID AS CityID,
       DATEADD(DAY, g.r2 * DATEDIFF(DAY, x.FromDate, @EndDate) / 10000, x.FromDate) AS TripDate
INTO #S1
FROM #Gen g
JOIN dbo.Riders r ON r.RiderID = 1 + CAST(@RiderCount * POWER(g.r1 / 10000.0, 1.6) AS INT)
CROSS APPLY (SELECT CASE WHEN r.RegistrationDate > '2025-01-01' THEN r.RegistrationDate
                         ELSE CAST('2025-01-01' AS DATE) END AS FromDate) x;

ALTER TABLE #S1 ADD Dow TINYINT NULL;   -- 1 = понеделник ... 7 = неделя
GO
UPDATE #S1 SET Dow = DATEDIFF(DAY, '19000101', TripDate) % 7 + 1;

-- по-малко курсове в началото на седмицата и през зимата → реалистично разпределение
DELETE FROM #S1
WHERE (Dow IN (1, 2) AND r20 % 100 < 20)
   OR (Dow = 3       AND r20 % 100 < 10)
   OR (MONTH(TripDate) IN (1, 2) AND r24 % 100 < 15);

-- 5.3 час на заявката: различни профили за делник и уикенд
DECLARE @HW TABLE (HourOfDay TINYINT PRIMARY KEY, WD INT, WE INT);
INSERT @HW VALUES
 (0,2,6),(1,1,5),(2,1,4),(3,1,3),(4,1,2),(5,2,1),(6,4,1),(7,8,2),(8,10,3),(9,7,4),(10,5,5),(11,5,6),
 (12,6,7),(13,6,7),(14,5,6),(15,5,6),(16,7,6),(17,9,7),(18,10,8),(19,8,8),(20,6,8),(21,5,8),(22,4,9),(23,3,9);

DECLARE @WDTotal INT = (SELECT SUM(WD) FROM @HW), @WETotal INT = (SELECT SUM(WE) FROM @HW);

IF OBJECT_ID('tempdb..#H') IS NOT NULL DROP TABLE #H;
SELECT HourOfDay,
       SUM(WD) OVER (ORDER BY HourOfDay ROWS UNBOUNDED PRECEDING) - WD AS WDFrom,
       SUM(WD) OVER (ORDER BY HourOfDay ROWS UNBOUNDED PRECEDING)      AS WDTo,
       SUM(WE) OVER (ORDER BY HourOfDay ROWS UNBOUNDED PRECEDING) - WE AS WEFrom,
       SUM(WE) OVER (ORDER BY HourOfDay ROWS UNBOUNDED PRECEDING)      AS WETo
INTO #H
FROM @HW;

-- 5.4 шофьор по град (позиция в града)
IF OBJECT_ID('tempdb..#DriverSlots') IS NOT NULL DROP TABLE #DriverSlots;
SELECT d.DriverID, d.CityID, v.VehicleID, v.VehicleTypeID,
       ROW_NUMBER() OVER (PARTITION BY d.CityID ORDER BY d.DriverID) - 1 AS SlotNo,
       COUNT(*)     OVER (PARTITION BY d.CityID)                         AS CityDrivers
INTO #DriverSlots
FROM dbo.Drivers d
JOIN dbo.Vehicles v ON v.DriverID = d.DriverID AND v.IsActive = 1;

-- 5.5 адреси по град (последните две са гара/летище – без номер)
DECLARE @Streets TABLE (CityID INT, n INT, Name NVARCHAR(100));
INSERT @Streets VALUES
 (1,1,N'Vitosha Blvd'),(1,2,N'Tsarigradsko Shose Blvd'),(1,3,N'Bulgaria Blvd'),(1,4,N'Graf Ignatiev St'),(1,5,N'Central Railway Station'),(1,6,N'Sofia Airport, Terminal 2'),
 (2,1,N'Knyaz Alexander I St'),(2,2,N'Maritsa Blvd'),(2,3,N'Ruski Blvd'),(2,4,N'Kapitan Raycho St'),(2,5,N'Plovdiv Central Station'),(2,6,N'Plovdiv Airport'),
 (3,1,N'Ermou St'),(3,2,N'Kifisias Ave'),(3,3,N'Vasilissis Sofias Ave'),(3,4,N'Panepistimiou St'),(3,5,N'Port of Piraeus'),(3,6,N'Athens International Airport'),
 (4,1,N'Kärntner Straße'),(4,2,N'Mariahilfer Straße'),(4,3,N'Praterstraße'),(4,4,N'Landstraßer Hauptstraße'),(4,5,N'Wien Hauptbahnhof'),(4,6,N'Vienna International Airport'),
 (5,1,N'Unter den Linden'),(5,2,N'Kurfürstendamm'),(5,3,N'Friedrichstraße'),(5,4,N'Karl-Marx-Allee'),(5,5,N'Berlin Hauptbahnhof'),(5,6,N'BER Airport'),
 (6,1,N'Avenue des Champs-Élysées'),(6,2,N'Rue de Rivoli'),(6,3,N'Boulevard Saint-Germain'),(6,4,N'Rue de la Paix'),(6,5,N'Gare du Nord'),(6,6,N'Charles de Gaulle Airport'),
 (7,1,N'Gran Vía'),(7,2,N'Calle de Alcalá'),(7,3,N'Paseo de la Castellana'),(7,4,N'Calle Mayor'),(7,5,N'Atocha Station'),(7,6,N'Madrid-Barajas Airport'),
 (8,1,N'Damrak'),(8,2,N'Kalverstraat'),(8,3,N'Prinsengracht'),(8,4,N'Leidsestraat'),(8,5,N'Amsterdam Centraal'),(8,6,N'Schiphol Airport');

-- 5.6 окончателни стойности на всеки курс
IF OBJECT_ID('tempdb..#Stage') IS NOT NULL DROP TABLE #Stage;
SELECT s.*,
       h.HourOfDay,
       DATEADD(SECOND, s.r4 % 3600, DATEADD(HOUR, h.HourOfDay, CAST(s.TripDate AS DATETIME2(0)))) AS RequestedAt,
       CASE WHEN (s.Dow <= 5 AND h.HourOfDay IN (7, 8, 17, 18, 19))
              OR (s.Dow >= 6 AND h.HourOfDay IN (22, 23, 0, 1, 2)) THEN 1 ELSE 0 END             AS IsPeak,
       ds.DriverID, ds.VehicleID, ds.VehicleTypeID,
       CASE WHEN s.r5 % 100 < 9 THEN N'Cancelled' ELSE N'Completed' END                          AS Status,
       CASE WHEN s.r5 % 100 >= 9 THEN NULL
            WHEN s.r6 % 100 < 68 THEN N'Rider'
            WHEN s.r6 % 100 < 93 THEN N'Driver'
            ELSE N'System' END                                                                    AS CancelledBy,
       CAST(1.5 + 23.5 * SQUARE(s.r10 / 10000.0) AS DECIMAL(6,2))                               AS DistanceKm,
       pu.Name + CASE WHEN pu.n <= 4 THEN N' ' + CAST(1 + s.r13 % 120 AS NVARCHAR(5)) ELSE N'' END AS PickupAddress,
       dr.Name + CASE WHEN dr.n <= 4 THEN N' ' + CAST(1 + s.r14 % 120 AS NVARCHAR(5)) ELSE N'' END AS DropoffAddress
INTO #Stage
FROM #S1 s
JOIN #H h
  ON (s.Dow <= 5 AND s.r3 % @WDTotal >= h.WDFrom AND s.r3 % @WDTotal < h.WDTo)
  OR (s.Dow >= 6 AND s.r3 % @WETotal >= h.WEFrom AND s.r3 % @WETotal < h.WETo)
JOIN #DriverSlots ds
  ON ds.CityID = s.CityID AND ds.SlotNo = s.r7 % ds.CityDrivers
JOIN @Streets pu ON pu.CityID = s.CityID AND pu.n = 1 + s.r13 % 6
JOIN @Streets dr ON dr.CityID = s.CityID AND dr.n = 1 + (s.r13 % 6 + 1 + s.r14 % 5) % 6;

ALTER TABLE #Stage ADD Seq INT NULL, Surge DECIMAL(3,2) NULL, DurationMin DECIMAL(6,2) NULL,
                       StartedAt DATETIME2(0) NULL, EndedAt DATETIME2(0) NULL;
GO

;WITH x AS (SELECT Seq, ROW_NUMBER() OVER (ORDER BY RequestedAt, i) AS rn FROM #Stage)
UPDATE x SET Seq = rn;

UPDATE #Stage
SET Surge       = CASE WHEN IsPeak = 1 AND r8 % 100 < 70 THEN 1.00 + (r8 % 60) / 100.0 ELSE 1.00 END,
    DurationMin = CAST(DistanceKm * (1.6 + (r11 % 180) / 100.0) * CASE WHEN IsPeak = 1 THEN 1.25 ELSE 1.0 END
                       + 1 + r12 % 5 AS DECIMAL(6,2));

UPDATE #Stage
SET StartedAt = CASE WHEN Status = N'Completed' THEN DATEADD(SECOND, 120 + r9 % 720, RequestedAt) END;

UPDATE #Stage
SET EndedAt = CASE WHEN Status = N'Completed' THEN DATEADD(SECOND, CAST(DurationMin * 60 AS INT), StartedAt) END;

-- 5.7 запис в Trips (TripID = хронологичен номер)
SET IDENTITY_INSERT dbo.Trips ON;

INSERT dbo.Trips (TripID, RiderID, DriverID, VehicleID, CityID, RequestedVehicleTypeID, PromoCodeID,
                  PickupAddress, DropoffAddress, RequestedAt, StartedAt, EndedAt,
                  DistanceKm, DurationMin, SurgeMultiplier, Fare, DiscountAmount, Status, CancelledBy)
SELECT Seq, RiderID,
       CASE WHEN CancelledBy = N'System' THEN NULL ELSE DriverID  END,
       CASE WHEN CancelledBy = N'System' THEN NULL ELSE VehicleID END,
       CityID, VehicleTypeID, NULL,
       PickupAddress, DropoffAddress, RequestedAt, StartedAt, EndedAt,
       CASE WHEN Status = N'Completed' THEN DistanceKm  END,
       CASE WHEN Status = N'Completed' THEN DurationMin END,
       Surge, NULL, 0, Status, CancelledBy
FROM #Stage
ORDER BY Seq;

SET IDENTITY_INSERT dbo.Trips OFF;

-- 5.8 използване на промо кодове: първият подходящ курс на пътника в периода на кода (~70%)
IF OBJECT_ID('tempdb..#PromoUse') IS NOT NULL DROP TABLE #PromoUse;
;WITH Cand AS (
    SELECT rpc.RiderID, rpc.PromoCodeID, t.TripID, t.EndedAt,
           ROW_NUMBER() OVER (PARTITION BY rpc.RiderID, rpc.PromoCodeID ORDER BY t.RequestedAt) AS rn
    FROM dbo.RiderPromoCodes rpc
    JOIN dbo.PromoCodes pc ON pc.PromoCodeID = rpc.PromoCodeID
    JOIN dbo.Trips t
      ON t.RiderID = rpc.RiderID
     AND t.Status  = N'Completed'
     AND t.RequestedAt >= rpc.AssignedAt
     AND CAST(t.RequestedAt AS DATE) BETWEEN pc.ValidFrom AND pc.ValidTo
     AND (pc.Code <> N'AIRPORT10' OR t.PickupAddress LIKE N'%Airport%' OR t.DropoffAddress LIKE N'%Airport%')
), FirstPerCode AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY TripID ORDER BY PromoCodeID) AS rnTrip
    FROM Cand WHERE rn = 1
)
SELECT RiderID, PromoCodeID, TripID, EndedAt
INTO #PromoUse
FROM FirstPerCode
WHERE rnTrip = 1;

DELETE FROM #PromoUse WHERE dbo.fn_SeedRand(TripID, 7) % 100 >= 70;

UPDATE t SET PromoCodeID = pu.PromoCodeID
FROM dbo.Trips t JOIN #PromoUse pu ON pu.TripID = t.TripID;

UPDATE rpc SET IsUsed = 1, UsedAt = pu.EndedAt
FROM dbo.RiderPromoCodes rpc
JOIN #PromoUse pu ON pu.RiderID = rpc.RiderID AND pu.PromoCodeID = rpc.PromoCodeID;

-- 5.9 цена чрез функцията fn_CalculateFare
UPDATE dbo.Trips
SET Fare           = dbo.fn_CalculateFare(RequestedVehicleTypeID, DistanceKm, DurationMin, SurgeMultiplier, PromoCodeID),
    DiscountAmount = dbo.fn_CalculateFare(RequestedVehicleTypeID, DistanceKm, DurationMin, SurgeMultiplier, NULL)
                   - dbo.fn_CalculateFare(RequestedVehicleTypeID, DistanceKm, DurationMin, SurgeMultiplier, PromoCodeID)
WHERE Status = N'Completed';

-- 5.10 плащания (в България повече плащания в брой)
INSERT dbo.Payments (TripID, PaymentMethodID, Amount, TipAmount, Currency, PaidAt, Status)
SELECT t.TripID,
       CASE WHEN t.CityID IN (1, 2) AND s.r15 % 100 < 22 THEN 3
            WHEN s.r16 % 100 < 34 THEN 1
            WHEN s.r16 % 100 < 54 THEN 2
            WHEN s.r16 % 100 < 64 THEN 3
            WHEN s.r16 % 100 < 80 THEN 4
            WHEN s.r16 % 100 < 94 THEN 5
            ELSE 6 END,
       t.Fare,
       CASE WHEN s.r17 % 100 < 28 THEN 0.50 + (s.r17 % 9) * 0.50 ELSE 0 END,
       c.Currency,
       t.EndedAt,
       CASE WHEN s.r18 % 1000 < 15 THEN N'Refunded' ELSE N'Paid' END
FROM dbo.Trips t
JOIN #Stage s      ON s.Seq = t.TripID
JOIN dbo.Cities c  ON c.CityID = t.CityID
WHERE t.Status = N'Completed'
ORDER BY t.TripID;

-- 5.11 оценки (~78% от приключилите курсове); тригерът обновява средните оценки
INSERT dbo.Ratings (TripID, DriverScore, RiderScore, Comment, CreatedAt)
SELECT q.TripID, q.DriverScore, q.RiderScore,
       CASE WHEN q.DriverScore = 5 AND q.r22 % 100 < 30 THEN
                 CHOOSE(q.r22 % 6 + 1, N'Great driver, very polite!', N'Clean car and smooth ride.', N'Arrived early, thank you!',
                                       N'Excellent music and conversation.', N'Best ride so far.', N'Safe and fast, recommended.')
            WHEN q.DriverScore <= 2 AND q.r22 % 100 < 80 THEN
                 CHOOSE(q.r22 % 5 + 1, N'Driver took a longer route.', N'Car was not clean.', N'Driver was on the phone the whole time.',
                                       N'Late pickup, waited too long.', N'Rough driving.')
            WHEN q.DriverScore IN (3, 4) AND q.r22 % 100 < 20 THEN
                 CHOOSE(q.r22 % 4 + 1, N'OK ride.', N'A bit late but fine.', N'Car smelled of smoke.', N'Good, but the AC was off.')
       END,
       DATEADD(MINUTE, 3 + q.r23 % 240, q.EndedAt)
FROM (
    SELECT t.TripID, t.EndedAt, s.r22, s.r23,
           CASE WHEN p.v < 70 THEN 5 WHEN p.v < 90 THEN 4 WHEN p.v < 96 THEN 3 WHEN p.v < 99 THEN 2 ELSE 1 END AS DriverScore,
           CASE WHEN s.r21 % 10 = 0 THEN NULL
                WHEN s.r21 % 100 < 72 THEN 5 WHEN s.r21 % 100 < 92 THEN 4 WHEN s.r21 % 100 < 97 THEN 3 ELSE 2 END AS RiderScore
    FROM dbo.Trips t
    JOIN #Stage s ON s.Seq = t.TripID
    -- „качество“ на шофьора: някои са по-добри, други по-слаби
    CROSS APPLY (SELECT s.r19 % 100 + CASE WHEN t.DriverID % 7 = 0 THEN 14
                                           WHEN t.DriverID % 5 = 0 THEN -12 ELSE 0 END AS v) p
    WHERE t.Status = N'Completed'
      AND s.r18 % 100 < 78
) q
ORDER BY q.TripID;
GO

/* ---------------------------------------------------------------------
   6. Демонстрация на процедурите и тригерите
   --------------------------------------------------------------------- */
DECLARE @City INT, @Trip1 INT, @Trip2 INT, @Trip3 INT;

-- пътник 1 получава демо промо кода (M:N)
INSERT dbo.RiderPromoCodes (RiderID, PromoCodeID)
SELECT 1, PromoCodeID FROM dbo.PromoCodes WHERE Code = N'DEMO26';

SELECT @City = HomeCityID FROM dbo.Riders WHERE RiderID = 1;

-- курс 1: заявка с промо код -> начало -> край с плащане -> оценка
EXEC dbo.usp_RequestTrip @RiderID = 1, @CityID = @City, @VehicleTypeID = 1,
     @PickupAddress = N'Demo Street 1', @DropoffAddress = N'Demo Street 99',
     @PromoCode = N'DEMO26', @TripID = @Trip1 OUTPUT;
EXEC dbo.usp_StartTrip    @TripID = @Trip1;
EXEC dbo.usp_CompleteTrip @TripID = @Trip1, @DistanceKm = 8.40, @DurationMin = 19, @PaymentMethodID = 4, @TipAmount = 2.00;
EXEC dbo.usp_RateTrip     @TripID = @Trip1, @DriverScore = 5, @RiderScore = 5, @Comment = N'Demo: great ride!';

-- курс 2: заявка -> отказ от пътника
SELECT @City = HomeCityID FROM dbo.Riders WHERE RiderID = 2;
EXEC dbo.usp_RequestTrip @RiderID = 2, @CityID = @City, @VehicleTypeID = 2,
     @PickupAddress = N'Demo Street 5', @DropoffAddress = N'Demo Street 42', @TripID = @Trip2 OUTPUT;
EXEC dbo.usp_CancelTrip @TripID = @Trip2, @CancelledBy = N'Rider';

-- курс 3: остава текущ (Accepted) – шофьорът е зает за нови заявки
SELECT @City = HomeCityID FROM dbo.Riders WHERE RiderID = 3;
EXEC dbo.usp_RequestTrip @RiderID = 3, @CityID = @City, @VehicleTypeID = 1,
     @PickupAddress = N'Demo Street 7', @DropoffAddress = N'Demo Street 12', @TripID = @Trip3 OUTPUT;

-- INSTEAD OF DELETE тригерът превръща изтриването в деактивиране
DELETE FROM dbo.Drivers WHERE DriverID = 80;
GO

/* ---------------------------------------------------------------------
   7. Обобщение
   --------------------------------------------------------------------- */
SELECT 'Cities' AS TableName, COUNT(*) AS RowsCount FROM dbo.Cities
UNION ALL SELECT 'VehicleTypes',    COUNT(*) FROM dbo.VehicleTypes
UNION ALL SELECT 'Riders',          COUNT(*) FROM dbo.Riders
UNION ALL SELECT 'Drivers',         COUNT(*) FROM dbo.Drivers
UNION ALL SELECT 'Vehicles',        COUNT(*) FROM dbo.Vehicles
UNION ALL SELECT 'PaymentMethods',  COUNT(*) FROM dbo.PaymentMethods
UNION ALL SELECT 'PromoCodes',      COUNT(*) FROM dbo.PromoCodes
UNION ALL SELECT 'RiderPromoCodes', COUNT(*) FROM dbo.RiderPromoCodes
UNION ALL SELECT 'Trips',           COUNT(*) FROM dbo.Trips
UNION ALL SELECT 'Payments',        COUNT(*) FROM dbo.Payments
UNION ALL SELECT 'Ratings',         COUNT(*) FROM dbo.Ratings
UNION ALL SELECT 'TripStatusLog',   COUNT(*) FROM dbo.TripStatusLog;
GO

DROP FUNCTION dbo.fn_SeedRand;
GO
