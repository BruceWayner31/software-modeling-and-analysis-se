/* =====================================================================
   Uber – курсова работа
   04. Data Warehouse (UberDW) – звездна схема
       Таблици измерения (9): DimDate, DimTime, DimCity, DimRider, DimDriver,
                              DimVehicle, DimPaymentMethod, DimPromoCode, DimTripStatus
       Таблици факти     (3): FactTrips, FactPayments, FactRatings
   ===================================================================== */
USE master;
GO

IF DB_ID(N'UberDW') IS NOT NULL
BEGIN
    ALTER DATABASE UberDW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE UberDW;
END
GO

CREATE DATABASE UberDW;
GO

USE UberDW;
GO

/* =========================== ИЗМЕРЕНИЯ =========================== */

CREATE TABLE dbo.DimDate (
    DateKey      INT          NOT NULL CONSTRAINT PK_DimDate PRIMARY KEY,   -- yyyymmdd
    FullDate     DATE         NOT NULL CONSTRAINT UQ_DimDate_FullDate UNIQUE,
    DayOfMonth   TINYINT      NOT NULL,
    DayOfWeek    TINYINT      NOT NULL,      -- 1 = понеделник ... 7 = неделя
    DayName      NVARCHAR(10) NOT NULL,
    DayNameBG    NVARCHAR(10) NOT NULL,
    IsWeekend    BIT          NOT NULL,
    WeekOfYear   TINYINT      NOT NULL,      -- ISO седмица
    MonthNumber  TINYINT      NOT NULL,
    MonthName    NVARCHAR(10) NOT NULL,
    MonthNameBG  NVARCHAR(10) NOT NULL,
    YearMonth    CHAR(7)      NOT NULL,      -- '2026-03'
    Quarter      TINYINT      NOT NULL,
    Year         SMALLINT     NOT NULL
);

CREATE TABLE dbo.DimTime (
    TimeKey     TINYINT      NOT NULL CONSTRAINT PK_DimTime PRIMARY KEY,    -- час 0..23
    HourLabel   CHAR(5)      NOT NULL,       -- '08:00'
    PartOfDay   NVARCHAR(15) NOT NULL,
    PartOfDayBG NVARCHAR(15) NOT NULL,
    IsPeakHour  BIT          NOT NULL
);

CREATE TABLE dbo.DimCity (
    CityKey   INT               NOT NULL CONSTRAINT PK_DimCity PRIMARY KEY,
    CityID    INT               NOT NULL,   -- бизнес ключ от UberDB
    CityName  NVARCHAR(100)     NOT NULL,
    Country   NVARCHAR(100)     NOT NULL,
    Currency  CHAR(3)           NOT NULL
);

CREATE TABLE dbo.DimRider (
    RiderKey         INT               NOT NULL CONSTRAINT PK_DimRider PRIMARY KEY,
    RiderID          INT               NOT NULL,
    FullName         NVARCHAR(101)     NOT NULL,
    Email            NVARCHAR(150)     NOT NULL,
    HomeCity         NVARCHAR(100)     NOT NULL,
    AgeGroup         NVARCHAR(10)      NOT NULL,
    RegistrationDate DATE              NULL,
    RegistrationYear SMALLINT          NULL,
    AverageRating    DECIMAL(3,2)      NULL
);

CREATE TABLE dbo.DimDriver (
    DriverKey       INT               NOT NULL CONSTRAINT PK_DimDriver PRIMARY KEY,
    DriverID        INT               NOT NULL,
    FullName        NVARCHAR(101)     NOT NULL,
    City            NVARCHAR(100)     NOT NULL,
    HireDate        DATE              NULL,
    ExperienceYears TINYINT           NULL,
    AverageRating   DECIMAL(3,2)      NULL,
    RatingBand      NVARCHAR(15)      NOT NULL,
    IsActive        BIT               NOT NULL
);

CREATE TABLE dbo.DimVehicle (
    VehicleKey     INT               NOT NULL CONSTRAINT PK_DimVehicle PRIMARY KEY,
    VehicleID      INT               NOT NULL,
    Make           NVARCHAR(50)      NOT NULL,
    Model          NVARCHAR(50)      NOT NULL,
    ProductionYear SMALLINT          NULL,
    Color          NVARCHAR(30)      NOT NULL,
    PlateNumber    NVARCHAR(15)      NOT NULL,
    VehicleType    NVARCHAR(50)      NOT NULL,   -- денормализиран тип превоз
    Capacity       TINYINT           NULL
);

CREATE TABLE dbo.DimPaymentMethod (
    PaymentMethodKey INT               NOT NULL CONSTRAINT PK_DimPaymentMethod PRIMARY KEY,
    PaymentMethodID  INT               NOT NULL,
    MethodName       NVARCHAR(50)      NOT NULL,
    Category         NVARCHAR(20)      NOT NULL,  -- Card / Cash / Wallet
    IsCashless       BIT               NOT NULL
);

CREATE TABLE dbo.DimPromoCode (
    PromoCodeKey    INT               NOT NULL CONSTRAINT PK_DimPromoCode PRIMARY KEY,
    PromoCodeID     INT               NOT NULL,
    Code            NVARCHAR(30)      NOT NULL,
    Description     NVARCHAR(200)     NULL,
    DiscountPercent TINYINT           NOT NULL,
    MaxDiscount     DECIMAL(6,2)      NOT NULL,
    ValidFrom       DATE              NULL,
    ValidTo         DATE              NULL
);

CREATE TABLE dbo.DimTripStatus (
    StatusKey    INT          NOT NULL CONSTRAINT PK_DimTripStatus PRIMARY KEY,
    StatusName   NVARCHAR(20) NOT NULL,
    StatusNameBG NVARCHAR(30) NOT NULL,
    CancelledBy  NVARCHAR(10) NOT NULL,   -- 'N/A' за неотказани
    IsSuccessful BIT          NOT NULL
);
GO

/* ============================= ФАКТИ ============================= */

-- зърно: един ред = един курс (вкл. отказаните)
CREATE TABLE dbo.FactTrips (
    TripKey         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FactTrips PRIMARY KEY,
    TripID          INT           NOT NULL,     -- дегенерирано измерение
    DateKey         INT           NOT NULL CONSTRAINT FK_FactTrips_Date    REFERENCES dbo.DimDate (DateKey),
    TimeKey         TINYINT       NOT NULL CONSTRAINT FK_FactTrips_Time    REFERENCES dbo.DimTime (TimeKey),
    CityKey         INT           NOT NULL CONSTRAINT FK_FactTrips_City    REFERENCES dbo.DimCity (CityKey),
    RiderKey        INT           NOT NULL CONSTRAINT FK_FactTrips_Rider   REFERENCES dbo.DimRider (RiderKey),
    DriverKey       INT           NOT NULL CONSTRAINT FK_FactTrips_Driver  REFERENCES dbo.DimDriver (DriverKey),
    VehicleKey      INT           NOT NULL CONSTRAINT FK_FactTrips_Vehicle REFERENCES dbo.DimVehicle (VehicleKey),
    PromoCodeKey    INT           NOT NULL CONSTRAINT FK_FactTrips_Promo   REFERENCES dbo.DimPromoCode (PromoCodeKey),
    StatusKey       INT           NOT NULL CONSTRAINT FK_FactTrips_Status  REFERENCES dbo.DimTripStatus (StatusKey),
    DistanceKm      DECIMAL(6,2)  NULL,
    DurationMin     DECIMAL(6,2)  NULL,
    WaitTimeMin     DECIMAL(6,2)  NULL,
    SurgeMultiplier DECIMAL(3,2)  NOT NULL,
    Fare            DECIMAL(10,2) NULL,
    DiscountAmount  DECIMAL(10,2) NOT NULL,
    TripCount       TINYINT       NOT NULL,
    IsCompleted     BIT           NOT NULL,
    IsCancelled     BIT           NOT NULL
);

-- зърно: един ред = едно плащане
CREATE TABLE dbo.FactPayments (
    PaymentKey       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FactPayments PRIMARY KEY,
    PaymentID        INT           NOT NULL,
    TripID           INT           NOT NULL,
    DateKey          INT           NOT NULL CONSTRAINT FK_FactPayments_Date   REFERENCES dbo.DimDate (DateKey),
    TimeKey          TINYINT       NOT NULL CONSTRAINT FK_FactPayments_Time   REFERENCES dbo.DimTime (TimeKey),
    CityKey          INT           NOT NULL CONSTRAINT FK_FactPayments_City   REFERENCES dbo.DimCity (CityKey),
    RiderKey         INT           NOT NULL CONSTRAINT FK_FactPayments_Rider  REFERENCES dbo.DimRider (RiderKey),
    DriverKey        INT           NOT NULL CONSTRAINT FK_FactPayments_Driver REFERENCES dbo.DimDriver (DriverKey),
    PaymentMethodKey INT           NOT NULL CONSTRAINT FK_FactPayments_Method REFERENCES dbo.DimPaymentMethod (PaymentMethodKey),
    PromoCodeKey     INT           NOT NULL CONSTRAINT FK_FactPayments_Promo  REFERENCES dbo.DimPromoCode (PromoCodeKey),
    FareAmount       DECIMAL(10,2) NOT NULL,
    TipAmount        DECIMAL(10,2) NOT NULL,
    TotalAmount      DECIMAL(10,2) NOT NULL,
    PlatformFee      DECIMAL(10,2) NOT NULL,   -- 25% от цената
    DriverEarnings   DECIMAL(10,2) NOT NULL,   -- 75% от цената + бакшиш
    IsRefunded       BIT           NOT NULL
);

-- зърно: един ред = една оценка на курс
CREATE TABLE dbo.FactRatings (
    RatingKey   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FactRatings PRIMARY KEY,
    RatingID    INT     NOT NULL,
    TripID      INT     NOT NULL,
    DateKey     INT     NOT NULL CONSTRAINT FK_FactRatings_Date    REFERENCES dbo.DimDate (DateKey),
    CityKey     INT     NOT NULL CONSTRAINT FK_FactRatings_City    REFERENCES dbo.DimCity (CityKey),
    RiderKey    INT     NOT NULL CONSTRAINT FK_FactRatings_Rider   REFERENCES dbo.DimRider (RiderKey),
    DriverKey   INT     NOT NULL CONSTRAINT FK_FactRatings_Driver  REFERENCES dbo.DimDriver (DriverKey),
    VehicleKey  INT     NOT NULL CONSTRAINT FK_FactRatings_Vehicle REFERENCES dbo.DimVehicle (VehicleKey),
    DriverScore TINYINT NULL,
    RiderScore  TINYINT NULL,
    HasComment  BIT     NOT NULL
);
GO

CREATE INDEX IX_FactTrips_Date    ON dbo.FactTrips (DateKey);
CREATE INDEX IX_FactTrips_City    ON dbo.FactTrips (CityKey);
CREATE INDEX IX_FactPayments_Date ON dbo.FactPayments (DateKey);
CREATE INDEX IX_FactRatings_Drv   ON dbo.FactRatings (DriverKey);
GO

PRINT N'UberDW: звездната схема е създадена.';
GO
