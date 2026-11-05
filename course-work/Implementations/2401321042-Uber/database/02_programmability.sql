/* =====================================================================
   Uber – курсова работа
   02. Функции, съхранени процедури и тригери (UberDB)
   ===================================================================== */
USE UberDB;
GO

/* =====================================================================
   ФУНКЦИИ
   ===================================================================== */

/* Скаларна функция: изчислява цената на курс по тарифата на типа превоз,
   коефициента за натоварване (surge) и евентуален промо код.            */
CREATE OR ALTER FUNCTION dbo.fn_CalculateFare
(
    @VehicleTypeID   INT,
    @DistanceKm      DECIMAL(6,2),
    @DurationMin     DECIMAL(6,2),
    @SurgeMultiplier DECIMAL(3,2),
    @PromoCodeID     INT            -- NULL = без промо код
)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @Fare DECIMAL(10,2), @MinimumFare DECIMAL(6,2), @Discount DECIMAL(10,2) = 0;

    SELECT @Fare = (BaseFare + PricePerKm * @DistanceKm + PricePerMinute * @DurationMin)
                   * ISNULL(@SurgeMultiplier, 1.00),
           @MinimumFare = MinimumFare
    FROM dbo.VehicleTypes
    WHERE VehicleTypeID = @VehicleTypeID;

    IF @Fare IS NULL RETURN NULL;
    IF @Fare < @MinimumFare SET @Fare = @MinimumFare;

    IF @PromoCodeID IS NOT NULL
        SELECT @Discount = CASE WHEN @Fare * DiscountPercent / 100.0 > MaxDiscount
                                THEN MaxDiscount
                                ELSE @Fare * DiscountPercent / 100.0 END
        FROM dbo.PromoCodes
        WHERE PromoCodeID = @PromoCodeID;

    RETURN ROUND(@Fare - @Discount, 2);
END
GO

/* Таблична функция: приходи на шофьор за период.
   Платформата задържа 25% комисиона от цената; бакшишът е изцяло за шофьора.
   @DriverID = NULL връща всички шофьори.                                 */
CREATE OR ALTER FUNCTION dbo.fn_GetDriverEarnings
(
    @DriverID INT,
    @From     DATE,
    @To       DATE
)
RETURNS TABLE
AS
RETURN
(
    SELECT  d.DriverID,
            d.FirstName + N' ' + d.LastName                          AS DriverName,
            COUNT(p.PaymentID)                                       AS CompletedTrips,
            CAST(ISNULL(SUM(p.Amount), 0)     AS DECIMAL(12,2))      AS GrossFares,
            CAST(ISNULL(SUM(p.TipAmount), 0)  AS DECIMAL(12,2))      AS Tips,
            CAST(ISNULL(SUM(p.Amount), 0) * 0.25 AS DECIMAL(12,2))   AS PlatformFee,
            CAST(ISNULL(SUM(p.Amount), 0) * 0.75
                 + ISNULL(SUM(p.TipAmount), 0) AS DECIMAL(12,2))     AS DriverEarnings
    FROM dbo.Drivers d
    LEFT JOIN dbo.Trips t
           ON t.DriverID = d.DriverID
          AND t.Status   = N'Completed'
          AND t.EndedAt >= @From
          AND t.EndedAt <  DATEADD(DAY, 1, @To)
    LEFT JOIN dbo.Payments p
           ON p.TripID = t.TripID
          AND p.Status = N'Paid'
    WHERE @DriverID IS NULL OR d.DriverID = @DriverID
    GROUP BY d.DriverID, d.FirstName, d.LastName
);
GO

/* =====================================================================
   СЪХРАНЕНИ ПРОЦЕДУРИ
   ===================================================================== */

/* Заявка за курс: валидира пътника и промо кода, намира свободен шофьор
   с автомобил от търсения тип в същия град и създава курса.            */
CREATE OR ALTER PROCEDURE dbo.usp_RequestTrip
    @RiderID        INT,
    @CityID         INT,
    @VehicleTypeID  INT,
    @PickupAddress  NVARCHAR(200),
    @DropoffAddress NVARCHAR(200),
    @PromoCode      NVARCHAR(30) = NULL,
    @TripID         INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @PromoCodeID INT, @DriverID INT, @VehicleID INT, @Surge DECIMAL(3,2);

    IF NOT EXISTS (SELECT 1 FROM dbo.Riders WHERE RiderID = @RiderID)
        THROW 50001, N'Пътникът не съществува.', 1;

    SELECT @Surge = SurgeMultiplier FROM dbo.Cities WHERE CityID = @CityID;
    IF @Surge IS NULL
        THROW 50002, N'Градът не съществува.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.VehicleTypes WHERE VehicleTypeID = @VehicleTypeID)
        THROW 50003, N'Типът превоз не съществува.', 1;

    IF @PromoCode IS NOT NULL
    BEGIN
        SELECT @PromoCodeID = pc.PromoCodeID
        FROM dbo.PromoCodes pc
        JOIN dbo.RiderPromoCodes rpc
          ON rpc.PromoCodeID = pc.PromoCodeID
         AND rpc.RiderID     = @RiderID
        WHERE pc.Code   = @PromoCode
          AND rpc.IsUsed = 0
          AND CAST(SYSDATETIME() AS DATE) BETWEEN pc.ValidFrom AND pc.ValidTo;

        IF @PromoCodeID IS NULL
            THROW 50004, N'Промо кодът е невалиден, изтекъл, вече използван или не е на този пътник.', 1;
    END

    BEGIN TRANSACTION;

    -- свободен шофьор: активен, в същия град, с активен автомобил от типа, без текущ курс
    SELECT TOP (1) @DriverID = d.DriverID, @VehicleID = v.VehicleID
    FROM dbo.Drivers d WITH (UPDLOCK, HOLDLOCK)
    JOIN dbo.Vehicles v
      ON v.DriverID = d.DriverID
     AND v.IsActive = 1
     AND v.VehicleTypeID = @VehicleTypeID
    WHERE d.CityID = @CityID
      AND d.IsActive = 1
      AND NOT EXISTS (SELECT 1 FROM dbo.Trips t
                      WHERE t.DriverID = d.DriverID
                        AND t.Status IN (N'Accepted', N'InProgress'))
    ORDER BY d.AverageRating DESC, NEWID();

    INSERT dbo.Trips (RiderID, DriverID, VehicleID, CityID, RequestedVehicleTypeID, PromoCodeID,
                      PickupAddress, DropoffAddress, RequestedAt, SurgeMultiplier, Status)
    VALUES (@RiderID, @DriverID, @VehicleID, @CityID, @VehicleTypeID, @PromoCodeID,
            @PickupAddress, @DropoffAddress, SYSDATETIME(), @Surge,
            CASE WHEN @DriverID IS NULL THEN N'Requested' ELSE N'Accepted' END);

    SET @TripID = SCOPE_IDENTITY();

    COMMIT TRANSACTION;

    IF @DriverID IS NULL
        PRINT N'Няма свободен шофьор – курсът остава в статус Requested.';
END
GO

/* Начало на курс (шофьорът е взел пътника). */
CREATE OR ALTER PROCEDURE dbo.usp_StartTrip
    @TripID INT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Trips
    SET Status = N'InProgress', StartedAt = SYSDATETIME()
    WHERE TripID = @TripID AND Status = N'Accepted';

    IF @@ROWCOUNT = 0
        THROW 50010, N'Курсът не съществува или не е в статус Accepted.', 1;
END
GO

/* Приключване на курс: изчислява цената чрез fn_CalculateFare, записва
   плащането и маркира промо кода като използван – в една транзакция.   */
CREATE OR ALTER PROCEDURE dbo.usp_CompleteTrip
    @TripID          INT,
    @DistanceKm      DECIMAL(6,2),
    @DurationMin     DECIMAL(6,2),
    @PaymentMethodID INT,
    @TipAmount       DECIMAL(10,2) = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @VehicleTypeID INT, @Surge DECIMAL(3,2), @PromoCodeID INT, @RiderID INT,
            @Status NVARCHAR(20), @Currency CHAR(3), @Fare DECIMAL(10,2), @FullFare DECIMAL(10,2);

    SELECT @VehicleTypeID = t.RequestedVehicleTypeID,
           @Surge         = t.SurgeMultiplier,
           @PromoCodeID   = t.PromoCodeID,
           @RiderID       = t.RiderID,
           @Status        = t.Status,
           @Currency      = c.Currency
    FROM dbo.Trips t
    JOIN dbo.Cities c ON c.CityID = t.CityID
    WHERE t.TripID = @TripID;

    IF @Status IS NULL
        THROW 50020, N'Курсът не съществува.', 1;
    IF @Status <> N'InProgress'
        THROW 50021, N'Само започнат курс (InProgress) може да бъде приключен.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PaymentMethods WHERE PaymentMethodID = @PaymentMethodID)
        THROW 50022, N'Невалиден начин на плащане.', 1;

    SET @FullFare = dbo.fn_CalculateFare(@VehicleTypeID, @DistanceKm, @DurationMin, @Surge, NULL);
    SET @Fare     = dbo.fn_CalculateFare(@VehicleTypeID, @DistanceKm, @DurationMin, @Surge, @PromoCodeID);

    BEGIN TRANSACTION;

    UPDATE dbo.Trips
    SET Status         = N'Completed',
        EndedAt        = SYSDATETIME(),
        DistanceKm     = @DistanceKm,
        DurationMin    = @DurationMin,
        Fare           = @Fare,
        DiscountAmount = @FullFare - @Fare
    WHERE TripID = @TripID;

    INSERT dbo.Payments (TripID, PaymentMethodID, Amount, TipAmount, Currency, PaidAt, Status)
    VALUES (@TripID, @PaymentMethodID, @Fare, ISNULL(@TipAmount, 0), @Currency, SYSDATETIME(), N'Paid');

    IF @PromoCodeID IS NOT NULL
        UPDATE dbo.RiderPromoCodes
        SET IsUsed = 1, UsedAt = SYSDATETIME()
        WHERE RiderID = @RiderID AND PromoCodeID = @PromoCodeID;

    COMMIT TRANSACTION;

    SELECT @TripID AS TripID, @FullFare AS FareBeforeDiscount, @FullFare - @Fare AS Discount,
           @Fare AS FinalFare, ISNULL(@TipAmount, 0) AS Tip;
END
GO

/* Отказ на курс (преди да е започнал). */
CREATE OR ALTER PROCEDURE dbo.usp_CancelTrip
    @TripID      INT,
    @CancelledBy NVARCHAR(10)   -- 'Rider' | 'Driver' | 'System'
AS
BEGIN
    SET NOCOUNT ON;

    IF @CancelledBy NOT IN (N'Rider', N'Driver', N'System')
        THROW 50030, N'CancelledBy трябва да е Rider, Driver или System.', 1;

    UPDATE dbo.Trips
    SET Status = N'Cancelled', CancelledBy = @CancelledBy
    WHERE TripID = @TripID AND Status IN (N'Requested', N'Accepted');

    IF @@ROWCOUNT = 0
        THROW 50031, N'Курсът не съществува или вече е започнал/приключил.', 1;
END
GO

/* Оценка на курс (вмъква или обновява). Средните оценки се преизчисляват
   автоматично от тригера trg_Ratings_UpdateAverages.                     */
CREATE OR ALTER PROCEDURE dbo.usp_RateTrip
    @TripID      INT,
    @DriverScore TINYINT = NULL,
    @RiderScore  TINYINT = NULL,
    @Comment     NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Trips WHERE TripID = @TripID AND Status = N'Completed')
        THROW 50040, N'Може да се оценява само приключил курс.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Ratings WHERE TripID = @TripID)
        UPDATE dbo.Ratings
        SET DriverScore = ISNULL(@DriverScore, DriverScore),
            RiderScore  = ISNULL(@RiderScore,  RiderScore),
            Comment     = ISNULL(@Comment,     Comment)
        WHERE TripID = @TripID;
    ELSE
        INSERT dbo.Ratings (TripID, DriverScore, RiderScore, Comment)
        VALUES (@TripID, @DriverScore, @RiderScore, @Comment);
END
GO

/* Справка по градове за период: курсове, процент откази, оборот, средна цена. */
CREATE OR ALTER PROCEDURE dbo.usp_GetCityStatistics
    @From DATE,
    @To   DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  c.Name                                                       AS City,
            COUNT(t.TripID)                                              AS TotalTrips,
            SUM(CASE WHEN t.Status = N'Completed' THEN 1 ELSE 0 END)     AS CompletedTrips,
            CAST(100.0 * SUM(CASE WHEN t.Status = N'Cancelled' THEN 1 ELSE 0 END)
                 / NULLIF(COUNT(t.TripID), 0) AS DECIMAL(5,2))           AS CancellationRatePct,
            CAST(ISNULL(SUM(t.Fare), 0) AS DECIMAL(12,2))                AS Revenue,
            CAST(AVG(t.Fare) AS DECIMAL(10,2))                           AS AvgFare,
            CAST(AVG(t.DistanceKm) AS DECIMAL(6,2))                      AS AvgDistanceKm
    FROM dbo.Cities c
    LEFT JOIN dbo.Trips t
           ON t.CityID = c.CityID
          AND t.RequestedAt >= @From
          AND t.RequestedAt <  DATEADD(DAY, 1, @To)
    GROUP BY c.Name
    ORDER BY Revenue DESC;
END
GO

/* =====================================================================
   ТРИГЕРИ
   ===================================================================== */

/* AFTER тригер: при всяка нова/променена/изтрита оценка преизчислява
   средната оценка на засегнатите шофьори и пътници.                    */
CREATE OR ALTER TRIGGER dbo.trg_Ratings_UpdateAverages
ON dbo.Ratings
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AffectedTrips TABLE (TripID INT PRIMARY KEY);
    INSERT @AffectedTrips (TripID)
    SELECT TripID FROM inserted
    UNION
    SELECT TripID FROM deleted;

    UPDATE d
    SET AverageRating = x.AvgScore
    FROM dbo.Drivers d
    JOIN (SELECT DISTINCT t.DriverID
          FROM @AffectedTrips a
          JOIN dbo.Trips t ON t.TripID = a.TripID
          WHERE t.DriverID IS NOT NULL) ad ON ad.DriverID = d.DriverID
    CROSS APPLY (SELECT CAST(AVG(CAST(r.DriverScore AS DECIMAL(5,2))) AS DECIMAL(3,2)) AS AvgScore
                 FROM dbo.Ratings r
                 JOIN dbo.Trips t2 ON t2.TripID = r.TripID
                 WHERE t2.DriverID = d.DriverID
                   AND r.DriverScore IS NOT NULL) x;

    UPDATE rd
    SET AverageRating = x.AvgScore
    FROM dbo.Riders rd
    JOIN (SELECT DISTINCT t.RiderID
          FROM @AffectedTrips a
          JOIN dbo.Trips t ON t.TripID = a.TripID) ar ON ar.RiderID = rd.RiderID
    CROSS APPLY (SELECT CAST(AVG(CAST(r.RiderScore AS DECIMAL(5,2))) AS DECIMAL(3,2)) AS AvgScore
                 FROM dbo.Ratings r
                 JOIN dbo.Trips t2 ON t2.TripID = r.TripID
                 WHERE t2.RiderID = rd.RiderID
                   AND r.RiderScore IS NOT NULL) x;
END
GO

/* AFTER тригер: записва всяка промяна на статуса на курс в TripStatusLog. */
CREATE OR ALTER TRIGGER dbo.trg_Trips_StatusLog
ON dbo.Trips
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(Status) RETURN;

    INSERT dbo.TripStatusLog (TripID, OldStatus, NewStatus)
    SELECT i.TripID, d.Status, i.Status
    FROM inserted i
    LEFT JOIN deleted d ON d.TripID = i.TripID
    WHERE d.TripID IS NULL OR d.Status <> i.Status;
END
GO

/* INSTEAD OF тригер: шофьор с курсове не се изтрива физически,
   а се деактивира (soft delete) заедно с автомобилите си.            */
CREATE OR ALTER TRIGGER dbo.trg_Drivers_SoftDelete
ON dbo.Drivers
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE d SET IsActive = 0
    FROM dbo.Drivers d
    JOIN deleted x ON x.DriverID = d.DriverID
    WHERE EXISTS (SELECT 1 FROM dbo.Trips t WHERE t.DriverID = d.DriverID);

    UPDATE v SET IsActive = 0
    FROM dbo.Vehicles v
    JOIN deleted x ON x.DriverID = v.DriverID
    WHERE EXISTS (SELECT 1 FROM dbo.Trips t WHERE t.DriverID = v.DriverID);

    -- шофьори без нито един курс могат да се изтрият реално
    DELETE v FROM dbo.Vehicles v
    JOIN deleted x ON x.DriverID = v.DriverID
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Trips t WHERE t.DriverID = v.DriverID);

    DELETE d FROM dbo.Drivers d
    JOIN deleted x ON x.DriverID = d.DriverID
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Trips t WHERE t.DriverID = d.DriverID);
END
GO

PRINT N'UberDB: функциите, процедурите и тригерите са създадени.';
GO
