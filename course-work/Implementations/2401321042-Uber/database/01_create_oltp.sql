/* =====================================================================
   Uber – курсова работа
   01. OLTP база данни (UberDB): създаване на базата и таблиците
   ===================================================================== */
USE master;
GO

IF DB_ID(N'UberDB') IS NOT NULL
BEGIN
    ALTER DATABASE UberDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE UberDB;
END
GO

CREATE DATABASE UberDB;
GO

USE UberDB;
GO

/* ---------- Градове, в които платформата работи ---------- */
CREATE TABLE dbo.Cities (
    CityID          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Cities PRIMARY KEY,
    Name            NVARCHAR(100)     NOT NULL,
    Country         NVARCHAR(100)     NOT NULL,
    Currency        CHAR(3)           NOT NULL CONSTRAINT DF_Cities_Currency DEFAULT ('EUR'),
    SurgeMultiplier DECIMAL(3,2)      NOT NULL CONSTRAINT DF_Cities_Surge DEFAULT (1.00),
    LaunchDate      DATE              NOT NULL,
    CONSTRAINT UQ_Cities_Name_Country UNIQUE (Name, Country),
    CONSTRAINT CK_Cities_Surge CHECK (SurgeMultiplier BETWEEN 1.00 AND 5.00)
);
GO

/* ---------- Типове превоз (UberX, Comfort, Black, ...) и тарифи ---------- */
CREATE TABLE dbo.VehicleTypes (
    VehicleTypeID  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_VehicleTypes PRIMARY KEY,
    Name           NVARCHAR(50)      NOT NULL CONSTRAINT UQ_VehicleTypes_Name UNIQUE,
    Capacity       TINYINT           NOT NULL,
    BaseFare       DECIMAL(6,2)      NOT NULL,
    PricePerKm     DECIMAL(6,2)      NOT NULL,
    PricePerMinute DECIMAL(6,2)      NOT NULL,
    MinimumFare    DECIMAL(6,2)      NOT NULL,
    CONSTRAINT CK_VehicleTypes_Capacity CHECK (Capacity BETWEEN 1 AND 8),
    CONSTRAINT CK_VehicleTypes_Prices   CHECK (BaseFare >= 0 AND PricePerKm >= 0 AND PricePerMinute >= 0 AND MinimumFare >= 0)
);
GO

/* ---------- Пътници ---------- */
CREATE TABLE dbo.Riders (
    RiderID          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Riders PRIMARY KEY,
    FirstName        NVARCHAR(50)      NOT NULL,
    LastName         NVARCHAR(50)      NOT NULL,
    Email            NVARCHAR(150)     NOT NULL CONSTRAINT UQ_Riders_Email UNIQUE,
    Phone            NVARCHAR(20)      NOT NULL,
    DateOfBirth      DATE              NULL,
    RegistrationDate DATE              NOT NULL CONSTRAINT DF_Riders_RegDate DEFAULT (CAST(SYSDATETIME() AS DATE)),
    HomeCityID       INT               NOT NULL CONSTRAINT FK_Riders_Cities REFERENCES dbo.Cities (CityID),
    AverageRating    DECIMAL(3,2)      NULL,      -- поддържа се от тригер trg_Ratings_UpdateAverages
    CONSTRAINT CK_Riders_Rating CHECK (AverageRating BETWEEN 1.00 AND 5.00)
);
GO

/* ---------- Шофьори ---------- */
CREATE TABLE dbo.Drivers (
    DriverID      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Drivers PRIMARY KEY,
    FirstName     NVARCHAR(50)      NOT NULL,
    LastName      NVARCHAR(50)      NOT NULL,
    Email         NVARCHAR(150)     NOT NULL CONSTRAINT UQ_Drivers_Email UNIQUE,
    Phone         NVARCHAR(20)      NOT NULL,
    LicenseNumber NVARCHAR(20)      NOT NULL CONSTRAINT UQ_Drivers_License UNIQUE,
    HireDate      DATE              NOT NULL,
    CityID        INT               NOT NULL CONSTRAINT FK_Drivers_Cities REFERENCES dbo.Cities (CityID),
    AverageRating DECIMAL(3,2)      NULL,         -- поддържа се от тригер trg_Ratings_UpdateAverages
    IsActive      BIT               NOT NULL CONSTRAINT DF_Drivers_IsActive DEFAULT (1),
    CONSTRAINT CK_Drivers_Rating CHECK (AverageRating BETWEEN 1.00 AND 5.00)
);
GO

/* ---------- Автомобили (един шофьор може да има няколко) ---------- */
CREATE TABLE dbo.Vehicles (
    VehicleID      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Vehicles PRIMARY KEY,
    DriverID       INT               NOT NULL CONSTRAINT FK_Vehicles_Drivers REFERENCES dbo.Drivers (DriverID),
    VehicleTypeID  INT               NOT NULL CONSTRAINT FK_Vehicles_VehicleTypes REFERENCES dbo.VehicleTypes (VehicleTypeID),
    Make           NVARCHAR(50)      NOT NULL,
    Model          NVARCHAR(50)      NOT NULL,
    ProductionYear SMALLINT          NOT NULL,
    PlateNumber    NVARCHAR(15)      NOT NULL CONSTRAINT UQ_Vehicles_Plate UNIQUE,
    Color          NVARCHAR(30)      NOT NULL,
    IsActive       BIT               NOT NULL CONSTRAINT DF_Vehicles_IsActive DEFAULT (1),
    CONSTRAINT CK_Vehicles_Year CHECK (ProductionYear >= 2010)
);
GO

/* ---------- Начини на плащане ---------- */
CREATE TABLE dbo.PaymentMethods (
    PaymentMethodID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PaymentMethods PRIMARY KEY,
    Name            NVARCHAR(50)      NOT NULL CONSTRAINT UQ_PaymentMethods_Name UNIQUE,
    IsCashless      BIT               NOT NULL
);
GO

/* ---------- Промо кодове ---------- */
CREATE TABLE dbo.PromoCodes (
    PromoCodeID     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PromoCodes PRIMARY KEY,
    Code            NVARCHAR(30)      NOT NULL CONSTRAINT UQ_PromoCodes_Code UNIQUE,
    Description     NVARCHAR(200)     NULL,
    DiscountPercent TINYINT           NOT NULL,
    MaxDiscount     DECIMAL(6,2)      NOT NULL,
    ValidFrom       DATE              NOT NULL,
    ValidTo         DATE              NOT NULL,
    CONSTRAINT CK_PromoCodes_Percent CHECK (DiscountPercent BETWEEN 1 AND 100),
    CONSTRAINT CK_PromoCodes_Dates   CHECK (ValidTo >= ValidFrom)
);
GO

/* ---------- Връзка МНОГО КЪМ МНОГО: Пътници <-> Промо кодове ---------- */
CREATE TABLE dbo.RiderPromoCodes (
    RiderID     INT          NOT NULL CONSTRAINT FK_RiderPromoCodes_Riders     REFERENCES dbo.Riders (RiderID),
    PromoCodeID INT          NOT NULL CONSTRAINT FK_RiderPromoCodes_PromoCodes REFERENCES dbo.PromoCodes (PromoCodeID),
    AssignedAt  DATETIME2(0) NOT NULL CONSTRAINT DF_RiderPromoCodes_AssignedAt DEFAULT (SYSDATETIME()),
    IsUsed      BIT          NOT NULL CONSTRAINT DF_RiderPromoCodes_IsUsed DEFAULT (0),
    UsedAt      DATETIME2(0) NULL,
    CONSTRAINT PK_RiderPromoCodes PRIMARY KEY (RiderID, PromoCodeID),
    CONSTRAINT CK_RiderPromoCodes_Used CHECK ((IsUsed = 0 AND UsedAt IS NULL) OR (IsUsed = 1 AND UsedAt IS NOT NULL))
);
GO

/* ---------- Курсове ---------- */
CREATE TABLE dbo.Trips (
    TripID                 INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Trips PRIMARY KEY,
    RiderID                INT               NOT NULL CONSTRAINT FK_Trips_Riders       REFERENCES dbo.Riders (RiderID),
    DriverID               INT               NULL     CONSTRAINT FK_Trips_Drivers      REFERENCES dbo.Drivers (DriverID),
    VehicleID              INT               NULL     CONSTRAINT FK_Trips_Vehicles     REFERENCES dbo.Vehicles (VehicleID),
    CityID                 INT               NOT NULL CONSTRAINT FK_Trips_Cities       REFERENCES dbo.Cities (CityID),
    RequestedVehicleTypeID INT               NOT NULL CONSTRAINT FK_Trips_VehicleTypes REFERENCES dbo.VehicleTypes (VehicleTypeID),
    PromoCodeID            INT               NULL     CONSTRAINT FK_Trips_PromoCodes   REFERENCES dbo.PromoCodes (PromoCodeID),
    PickupAddress          NVARCHAR(200)     NOT NULL,
    DropoffAddress         NVARCHAR(200)     NOT NULL,
    RequestedAt            DATETIME2(0)      NOT NULL CONSTRAINT DF_Trips_RequestedAt DEFAULT (SYSDATETIME()),
    StartedAt              DATETIME2(0)      NULL,
    EndedAt                DATETIME2(0)      NULL,
    DistanceKm             DECIMAL(6,2)      NULL,
    DurationMin            DECIMAL(6,2)      NULL,
    SurgeMultiplier        DECIMAL(3,2)      NOT NULL CONSTRAINT DF_Trips_Surge DEFAULT (1.00),
    Fare                   DECIMAL(10,2)     NULL,
    DiscountAmount         DECIMAL(10,2)     NOT NULL CONSTRAINT DF_Trips_Discount DEFAULT (0),
    Status                 NVARCHAR(20)      NOT NULL CONSTRAINT DF_Trips_Status DEFAULT (N'Requested'),
    CancelledBy            NVARCHAR(10)      NULL,
    -- промо кодът трябва да е присвоен на същия пътник (съставен FK към M:N таблицата)
    CONSTRAINT FK_Trips_RiderPromoCodes FOREIGN KEY (RiderID, PromoCodeID) REFERENCES dbo.RiderPromoCodes (RiderID, PromoCodeID),
    CONSTRAINT CK_Trips_Status      CHECK (Status IN (N'Requested', N'Accepted', N'InProgress', N'Completed', N'Cancelled')),
    CONSTRAINT CK_Trips_CancelledBy CHECK (CancelledBy IS NULL OR CancelledBy IN (N'Rider', N'Driver', N'System')),
    CONSTRAINT CK_Trips_Cancel      CHECK ((Status = N'Cancelled') OR CancelledBy IS NULL),
    CONSTRAINT CK_Trips_Times       CHECK (StartedAt IS NULL OR StartedAt >= RequestedAt),
    CONSTRAINT CK_Trips_EndTime     CHECK (EndedAt IS NULL OR EndedAt >= StartedAt),
    CONSTRAINT CK_Trips_Values      CHECK (DistanceKm >= 0 AND DurationMin >= 0 AND Fare >= 0 AND DiscountAmount >= 0)
);
GO

CREATE INDEX IX_Trips_RiderID        ON dbo.Trips (RiderID);
CREATE INDEX IX_Trips_DriverID       ON dbo.Trips (DriverID) INCLUDE (Status);
CREATE INDEX IX_Trips_City_Requested ON dbo.Trips (CityID, RequestedAt);
CREATE INDEX IX_Trips_Status         ON dbo.Trips (Status);
GO

/* ---------- Плащания (едно плащане за един приключил курс) ---------- */
CREATE TABLE dbo.Payments (
    PaymentID       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Payments PRIMARY KEY,
    TripID          INT               NOT NULL CONSTRAINT FK_Payments_Trips          REFERENCES dbo.Trips (TripID)
                                               CONSTRAINT UQ_Payments_Trip UNIQUE,
    PaymentMethodID INT               NOT NULL CONSTRAINT FK_Payments_PaymentMethods REFERENCES dbo.PaymentMethods (PaymentMethodID),
    Amount          DECIMAL(10,2)     NOT NULL,
    TipAmount       DECIMAL(10,2)     NOT NULL CONSTRAINT DF_Payments_Tip DEFAULT (0),
    Currency        CHAR(3)           NOT NULL CONSTRAINT DF_Payments_Currency DEFAULT ('EUR'),
    PaidAt          DATETIME2(0)      NOT NULL CONSTRAINT DF_Payments_PaidAt DEFAULT (SYSDATETIME()),
    Status          NVARCHAR(20)      NOT NULL CONSTRAINT DF_Payments_Status DEFAULT (N'Paid'),
    CONSTRAINT CK_Payments_Amounts CHECK (Amount >= 0 AND TipAmount >= 0),
    CONSTRAINT CK_Payments_Status  CHECK (Status IN (N'Paid', N'Refunded', N'Failed'))
);
GO

/* ---------- Оценки: пътникът оценява шофьора и обратно ---------- */
CREATE TABLE dbo.Ratings (
    RatingID    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Ratings PRIMARY KEY,
    TripID      INT               NOT NULL CONSTRAINT FK_Ratings_Trips REFERENCES dbo.Trips (TripID)
                                           CONSTRAINT UQ_Ratings_Trip UNIQUE,
    DriverScore TINYINT           NULL,   -- оценка, дадена от пътника за шофьора
    RiderScore  TINYINT           NULL,   -- оценка, дадена от шофьора за пътника
    Comment     NVARCHAR(500)     NULL,
    CreatedAt   DATETIME2(0)      NOT NULL CONSTRAINT DF_Ratings_CreatedAt DEFAULT (SYSDATETIME()),
    CONSTRAINT CK_Ratings_DriverScore CHECK (DriverScore BETWEEN 1 AND 5),
    CONSTRAINT CK_Ratings_RiderScore  CHECK (RiderScore  BETWEEN 1 AND 5),
    CONSTRAINT CK_Ratings_AnyScore    CHECK (DriverScore IS NOT NULL OR RiderScore IS NOT NULL)
);
GO

/* ---------- Одит на статусите на курсовете (попълва се от тригер) ---------- */
CREATE TABLE dbo.TripStatusLog (
    LogID     BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TripStatusLog PRIMARY KEY,
    TripID    INT                  NOT NULL CONSTRAINT FK_TripStatusLog_Trips REFERENCES dbo.Trips (TripID),
    OldStatus NVARCHAR(20)         NULL,
    NewStatus NVARCHAR(20)         NOT NULL,
    ChangedAt DATETIME2(0)         NOT NULL CONSTRAINT DF_TripStatusLog_ChangedAt DEFAULT (SYSDATETIME()),
    ChangedBy SYSNAME              NOT NULL CONSTRAINT DF_TripStatusLog_ChangedBy DEFAULT (SUSER_SNAME())
);
GO

PRINT N'UberDB: таблиците са създадени.';
GO
