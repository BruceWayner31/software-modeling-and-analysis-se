/* =====================================================================
   Uber – курсова работа
   05. ETL: зареждане на UberDW от UberDB (пълно презареждане)
       EXEC UberDW.dbo.usp_LoadDW;   -- може да се пуска многократно
   ===================================================================== */
USE UberDW;
GO

IF OBJECT_ID(N'dbo.EtlLog') IS NULL
    CREATE TABLE dbo.EtlLog (
        LoadID       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EtlLog PRIMARY KEY,
        StartedAt    DATETIME2(0) NOT NULL,
        FinishedAt   DATETIME2(0) NULL,
        TripsRows    INT NULL,
        PaymentsRows INT NULL,
        RatingsRows  INT NULL
    );
GO

CREATE OR ALTER PROCEDURE dbo.usp_LoadDW
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LoadID INT, @MinDate DATE, @MaxDate DATE;

    INSERT dbo.EtlLog (StartedAt) VALUES (SYSDATETIME());
    SET @LoadID = SCOPE_IDENTITY();

    BEGIN TRANSACTION;

    /* ---------- 1. изчистване (фактите първо, после измеренията) ---------- */
    TRUNCATE TABLE dbo.FactRatings;
    TRUNCATE TABLE dbo.FactPayments;
    TRUNCATE TABLE dbo.FactTrips;

    DELETE FROM dbo.DimDate;
    DELETE FROM dbo.DimTime;
    DELETE FROM dbo.DimCity;
    DELETE FROM dbo.DimRider;
    DELETE FROM dbo.DimDriver;
    DELETE FROM dbo.DimVehicle;
    DELETE FROM dbo.DimPaymentMethod;
    DELETE FROM dbo.DimPromoCode;
    DELETE FROM dbo.DimTripStatus;

    /* ---------- 2. DimDate: от 1 януари на първата година до 31 декември на последната ---------- */
    SELECT @MinDate = DATEFROMPARTS(YEAR(MIN(RequestedAt)), 1, 1) FROM UberDB.dbo.Trips;
    SELECT @MaxDate = DATEFROMPARTS(YEAR(MAX(d)), 12, 31)
    FROM (SELECT MAX(RequestedAt) AS d FROM UberDB.dbo.Trips
          UNION ALL SELECT MAX(CreatedAt) FROM UberDB.dbo.Ratings
          UNION ALL SELECT MAX(PaidAt)    FROM UberDB.dbo.Payments
          UNION ALL SELECT SYSDATETIME()) x;

    ;WITH N AS (
        SELECT TOP (DATEDIFF(DAY, @MinDate, @MaxDate) + 1)
               ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS k
        FROM sys.all_objects a CROSS JOIN sys.all_objects b
    ), D AS (
        SELECT DATEADD(DAY, k, @MinDate) AS d FROM N
    ), D2 AS (
        SELECT d, DATEDIFF(DAY, '19000101', d) % 7 + 1 AS dow FROM D   -- 1 = понеделник
    )
    INSERT dbo.DimDate (DateKey, FullDate, DayOfMonth, DayOfWeek, DayName, DayNameBG, IsWeekend,
                        WeekOfYear, MonthNumber, MonthName, MonthNameBG, YearMonth, Quarter, Year)
    SELECT YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d),
           d, DAY(d), dow,
           CHOOSE(dow, N'Monday', N'Tuesday', N'Wednesday', N'Thursday', N'Friday', N'Saturday', N'Sunday'),
           CHOOSE(dow, N'Понеделник', N'Вторник', N'Сряда', N'Четвъртък', N'Петък', N'Събота', N'Неделя'),
           CASE WHEN dow >= 6 THEN 1 ELSE 0 END,
           DATEPART(ISO_WEEK, d),
           MONTH(d),
           CHOOSE(MONTH(d), N'January', N'February', N'March', N'April', N'May', N'June',
                            N'July', N'August', N'September', N'October', N'November', N'December'),
           CHOOSE(MONTH(d), N'Януари', N'Февруари', N'Март', N'Април', N'Май', N'Юни',
                            N'Юли', N'Август', N'Септември', N'Октомври', N'Ноември', N'Декември'),
           CONVERT(CHAR(7), d, 126),
           DATEPART(QUARTER, d),
           YEAR(d)
    FROM D2;

    /* ---------- 3. DimTime (часове) ---------- */
    ;WITH H AS (SELECT TOP (24) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS TINYINT) AS h FROM sys.all_objects)
    INSERT dbo.DimTime (TimeKey, HourLabel, PartOfDay, PartOfDayBG, IsPeakHour)
    SELECT h,
           RIGHT('0' + CAST(h AS VARCHAR(2)), 2) + ':00',
           CASE WHEN h < 6 THEN N'Night'  WHEN h < 12 THEN N'Morning' WHEN h < 18 THEN N'Afternoon' ELSE N'Evening' END,
           CASE WHEN h < 6 THEN N'Нощ'    WHEN h < 12 THEN N'Сутрин'  WHEN h < 18 THEN N'Следобед'  ELSE N'Вечер'   END,
           CASE WHEN h IN (7, 8, 17, 18, 19) THEN 1 ELSE 0 END
    FROM H;

    /* ---------- 4. останалите измерения (-1 = „неизвестен / няма“) ---------- */
    INSERT dbo.DimCity (CityKey, CityID, CityName, Country, Currency)
    SELECT ROW_NUMBER() OVER (ORDER BY CityID), CityID, Name, Country, Currency
    FROM UberDB.dbo.Cities;

    INSERT dbo.DimRider (RiderKey, RiderID, FullName, Email, HomeCity, AgeGroup, RegistrationDate, RegistrationYear, AverageRating)
    VALUES (-1, -1, N'Unknown', N'-', N'Unknown', N'Unknown', NULL, NULL, NULL);

    INSERT dbo.DimRider (RiderKey, RiderID, FullName, Email, HomeCity, AgeGroup, RegistrationDate, RegistrationYear, AverageRating)
    SELECT ROW_NUMBER() OVER (ORDER BY r.RiderID), r.RiderID,
           r.FirstName + N' ' + r.LastName, r.Email, c.Name,
           CASE WHEN a.Age IS NULL THEN N'Unknown'
                WHEN a.Age < 25 THEN N'18-24' WHEN a.Age < 35 THEN N'25-34'
                WHEN a.Age < 45 THEN N'35-44' WHEN a.Age < 55 THEN N'45-54' ELSE N'55+' END,
           r.RegistrationDate, YEAR(r.RegistrationDate), r.AverageRating
    FROM UberDB.dbo.Riders r
    JOIN UberDB.dbo.Cities c ON c.CityID = r.HomeCityID
    CROSS APPLY (SELECT DATEDIFF(YEAR, r.DateOfBirth, SYSDATETIME())
                        - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, r.DateOfBirth, SYSDATETIME()), r.DateOfBirth) > SYSDATETIME()
                               THEN 1 ELSE 0 END AS Age) a;

    INSERT dbo.DimDriver (DriverKey, DriverID, FullName, City, HireDate, ExperienceYears, AverageRating, RatingBand, IsActive)
    VALUES (-1, -1, N'Unknown / not assigned', N'Unknown', NULL, NULL, NULL, N'No ratings', 0);

    INSERT dbo.DimDriver (DriverKey, DriverID, FullName, City, HireDate, ExperienceYears, AverageRating, RatingBand, IsActive)
    SELECT ROW_NUMBER() OVER (ORDER BY d.DriverID), d.DriverID,
           d.FirstName + N' ' + d.LastName, c.Name, d.HireDate,
           DATEDIFF(YEAR, d.HireDate, SYSDATETIME()),
           d.AverageRating,
           CASE WHEN d.AverageRating IS NULL THEN N'No ratings'
                WHEN d.AverageRating >= 4.80 THEN N'4.8+'
                WHEN d.AverageRating >= 4.50 THEN N'4.5 - 4.79'
                ELSE N'< 4.5' END,
           d.IsActive
    FROM UberDB.dbo.Drivers d
    JOIN UberDB.dbo.Cities c ON c.CityID = d.CityID;

    INSERT dbo.DimVehicle (VehicleKey, VehicleID, Make, Model, ProductionYear, Color, PlateNumber, VehicleType, Capacity)
    VALUES (-1, -1, N'Unknown', N'Unknown', NULL, N'-', N'-', N'Unknown', NULL);

    INSERT dbo.DimVehicle (VehicleKey, VehicleID, Make, Model, ProductionYear, Color, PlateNumber, VehicleType, Capacity)
    SELECT ROW_NUMBER() OVER (ORDER BY v.VehicleID), v.VehicleID, v.Make, v.Model, v.ProductionYear,
           v.Color, v.PlateNumber, vt.Name, vt.Capacity
    FROM UberDB.dbo.Vehicles v
    JOIN UberDB.dbo.VehicleTypes vt ON vt.VehicleTypeID = v.VehicleTypeID;

    INSERT dbo.DimPaymentMethod (PaymentMethodKey, PaymentMethodID, MethodName, Category, IsCashless)
    SELECT ROW_NUMBER() OVER (ORDER BY PaymentMethodID), PaymentMethodID, Name,
           CASE WHEN Name = N'Cash' THEN N'Cash'
                WHEN Name IN (N'Apple Pay', N'Google Pay', N'Uber Cash') THEN N'Wallet'
                ELSE N'Card' END,
           IsCashless
    FROM UberDB.dbo.PaymentMethods;

    INSERT dbo.DimPromoCode (PromoCodeKey, PromoCodeID, Code, Description, DiscountPercent, MaxDiscount, ValidFrom, ValidTo)
    VALUES (-1, -1, N'NO PROMO', N'Без промо код', 0, 0, NULL, NULL);

    INSERT dbo.DimPromoCode (PromoCodeKey, PromoCodeID, Code, Description, DiscountPercent, MaxDiscount, ValidFrom, ValidTo)
    SELECT ROW_NUMBER() OVER (ORDER BY PromoCodeID), PromoCodeID, Code, Description, DiscountPercent,
           MaxDiscount, ValidFrom, ValidTo
    FROM UberDB.dbo.PromoCodes;

    INSERT dbo.DimTripStatus (StatusKey, StatusName, StatusNameBG, CancelledBy, IsSuccessful) VALUES
     (1, N'Completed',  N'Приключен',            N'N/A',    1),
     (2, N'Cancelled',  N'Отказан от пътник',    N'Rider',  0),
     (3, N'Cancelled',  N'Отказан от шофьор',    N'Driver', 0),
     (4, N'Cancelled',  N'Отказан от системата', N'System', 0),
     (5, N'Requested',  N'Изчакващ шофьор',      N'N/A',    0),
     (6, N'Accepted',   N'Приет',                N'N/A',    0),
     (7, N'InProgress', N'В процес',             N'N/A',    0);

    /* ---------- 5. FactTrips ---------- */
    INSERT dbo.FactTrips (TripID, DateKey, TimeKey, CityKey, RiderKey, DriverKey, VehicleKey, PromoCodeKey, StatusKey,
                          DistanceKm, DurationMin, WaitTimeMin, SurgeMultiplier, Fare, DiscountAmount,
                          TripCount, IsCompleted, IsCancelled)
    SELECT t.TripID,
           YEAR(t.RequestedAt) * 10000 + MONTH(t.RequestedAt) * 100 + DAY(t.RequestedAt),
           DATEPART(HOUR, t.RequestedAt),
           dc.CityKey,
           ISNULL(dr.RiderKey, -1),
           ISNULL(dd.DriverKey, -1),
           ISNULL(dv.VehicleKey, -1),
           ISNULL(dp.PromoCodeKey, -1),
           ds.StatusKey,
           t.DistanceKm, t.DurationMin,
           CAST(DATEDIFF(SECOND, t.RequestedAt, t.StartedAt) / 60.0 AS DECIMAL(6,2)),
           t.SurgeMultiplier, t.Fare, t.DiscountAmount,
           1,
           CASE WHEN t.Status = N'Completed' THEN 1 ELSE 0 END,
           CASE WHEN t.Status = N'Cancelled' THEN 1 ELSE 0 END
    FROM UberDB.dbo.Trips t
    JOIN      dbo.DimCity       dc ON dc.CityID = t.CityID
    LEFT JOIN dbo.DimRider      dr ON dr.RiderID = t.RiderID
    LEFT JOIN dbo.DimDriver     dd ON dd.DriverID = t.DriverID
    LEFT JOIN dbo.DimVehicle    dv ON dv.VehicleID = t.VehicleID
    LEFT JOIN dbo.DimPromoCode  dp ON dp.PromoCodeID = t.PromoCodeID
    JOIN      dbo.DimTripStatus ds ON ds.StatusName = t.Status AND ds.CancelledBy = ISNULL(t.CancelledBy, N'N/A')
    ORDER BY t.TripID;

    /* ---------- 6. FactPayments ---------- */
    INSERT dbo.FactPayments (PaymentID, TripID, DateKey, TimeKey, CityKey, RiderKey, DriverKey, PaymentMethodKey, PromoCodeKey,
                             FareAmount, TipAmount, TotalAmount, PlatformFee, DriverEarnings, IsRefunded)
    SELECT p.PaymentID, p.TripID,
           YEAR(p.PaidAt) * 10000 + MONTH(p.PaidAt) * 100 + DAY(p.PaidAt),
           DATEPART(HOUR, p.PaidAt),
           dc.CityKey,
           ISNULL(dr.RiderKey, -1),
           ISNULL(dd.DriverKey, -1),
           dm.PaymentMethodKey,
           ISNULL(dp.PromoCodeKey, -1),
           p.Amount, p.TipAmount, p.Amount + p.TipAmount,
           f.Fee,
           p.Amount - f.Fee + p.TipAmount,
           CASE WHEN p.Status = N'Refunded' THEN 1 ELSE 0 END
    FROM UberDB.dbo.Payments p
    JOIN UberDB.dbo.Trips t ON t.TripID = p.TripID
    CROSS APPLY (SELECT CAST(ROUND(p.Amount * 0.25, 2) AS DECIMAL(10,2)) AS Fee) f
    JOIN      dbo.DimCity          dc ON dc.CityID = t.CityID
    JOIN      dbo.DimPaymentMethod dm ON dm.PaymentMethodID = p.PaymentMethodID
    LEFT JOIN dbo.DimRider         dr ON dr.RiderID = t.RiderID
    LEFT JOIN dbo.DimDriver        dd ON dd.DriverID = t.DriverID
    LEFT JOIN dbo.DimPromoCode     dp ON dp.PromoCodeID = t.PromoCodeID
    ORDER BY p.PaymentID;

    /* ---------- 7. FactRatings ---------- */
    INSERT dbo.FactRatings (RatingID, TripID, DateKey, CityKey, RiderKey, DriverKey, VehicleKey, DriverScore, RiderScore, HasComment)
    SELECT r.RatingID, r.TripID,
           YEAR(r.CreatedAt) * 10000 + MONTH(r.CreatedAt) * 100 + DAY(r.CreatedAt),
           dc.CityKey,
           ISNULL(dr.RiderKey, -1),
           ISNULL(dd.DriverKey, -1),
           ISNULL(dv.VehicleKey, -1),
           r.DriverScore, r.RiderScore,
           CASE WHEN r.Comment IS NULL THEN 0 ELSE 1 END
    FROM UberDB.dbo.Ratings r
    JOIN UberDB.dbo.Trips t ON t.TripID = r.TripID
    JOIN      dbo.DimCity    dc ON dc.CityID = t.CityID
    LEFT JOIN dbo.DimRider   dr ON dr.RiderID = t.RiderID
    LEFT JOIN dbo.DimDriver  dd ON dd.DriverID = t.DriverID
    LEFT JOIN dbo.DimVehicle dv ON dv.VehicleID = t.VehicleID
    ORDER BY r.RatingID;

    COMMIT TRANSACTION;

    UPDATE dbo.EtlLog
    SET FinishedAt   = SYSDATETIME(),
        TripsRows    = (SELECT COUNT(*) FROM dbo.FactTrips),
        PaymentsRows = (SELECT COUNT(*) FROM dbo.FactPayments),
        RatingsRows  = (SELECT COUNT(*) FROM dbo.FactRatings)
    WHERE LoadID = @LoadID;

    SELECT * FROM dbo.EtlLog WHERE LoadID = @LoadID;
END
GO

EXEC dbo.usp_LoadDW;
GO
