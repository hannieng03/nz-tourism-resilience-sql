/* ============================================================
   NZ TOURISM DATA WAREHOUSE
   FINAL STAR SCHEMA BUILD

   Fact grain:
   One row per:
       Month + RTO + Visitor Type

   Dimensions:
       DimDate
       DimLocation
       DimVisitorType

   Fact:
       FactTourismMonthly
   ============================================================ */


PRAGMA foreign_keys = ON;


/* ============================================================
   0. DROP EXISTING STAR SCHEMA TABLES
   ============================================================ */

DROP TABLE IF EXISTS FactTourismMonthly;
DROP TABLE IF EXISTS DimVisitorType;
DROP TABLE IF EXISTS DimLocation;
DROP TABLE IF EXISTS DimDate;



/* ============================================================
   1. DATE DIMENSION
   ============================================================

   Hierarchies:
       Year -> Quarter -> Month
       Year -> Season -> Month

   Important:
   The date dimension is generated as a continuous monthly
   calendar from the earliest source month to the latest source
   month.

   It is NOT populated only from dates that appear in source
   records. This allows missing months to be identified.
   ============================================================ */


CREATE TABLE DimDate (

    DateKey INTEGER PRIMARY KEY,

    MonthStartDate TEXT NOT NULL UNIQUE,

    MonthNumber INTEGER NOT NULL
        CHECK (
            MonthNumber BETWEEN 1 AND 12
        ),

    MonthName TEXT NOT NULL,

    Quarter TEXT NOT NULL
        CHECK (
            Quarter IN (
                'Q1',
                'Q2',
                'Q3',
                'Q4'
            )
        ),

    Year INTEGER NOT NULL,

    Season TEXT NOT NULL
        CHECK (
            Season IN (
                'Summer',
                'Autumn',
                'Winter',
                'Spring'
            )
        )
);



/* ------------------------------------------------------------
   Generate the continuous monthly series.

   DateBounds finds the earliest and latest month across all
   three cleaned datasets.

   MonthSeries then recursively creates every month between
   these two dates.
   ------------------------------------------------------------ */


WITH RECURSIVE

DateBounds AS (

    SELECT
        MIN(Month) AS MinMonth,
        MAX(Month) AS MaxMonth

    FROM (

        SELECT Month
        FROM Spend_Clean

        UNION ALL

        SELECT Month
        FROM ADP_Nights_Clean

        UNION ALL

        SELECT Month
        FROM Visitor_Count_Clean

    )
),


MonthSeries(MonthStartDate) AS (

    /* First calendar month */
    SELECT MinMonth
    FROM DateBounds


    UNION ALL


    /* Add one month until the maximum date is reached */
    SELECT
        date(
            MonthStartDate,
            '+1 month'
        )

    FROM
        MonthSeries,
        DateBounds

    WHERE
        MonthStartDate < MaxMonth
)


INSERT INTO DimDate (

    DateKey,
    MonthStartDate,
    MonthNumber,
    MonthName,
    Quarter,
    Year,
    Season

)

SELECT

    /* Example:
       January 2025 -> 202501
    */
    CAST(
        strftime(
            '%Y',
            MonthStartDate
        ) AS INTEGER
    ) * 100

    +

    CAST(
        strftime(
            '%m',
            MonthStartDate
        ) AS INTEGER
    )

    AS DateKey,


    MonthStartDate,


    CAST(
        strftime(
            '%m',
            MonthStartDate
        ) AS INTEGER
    )

    AS MonthNumber,


    CASE strftime('%m', MonthStartDate)

        WHEN '01' THEN 'January'
        WHEN '02' THEN 'February'
        WHEN '03' THEN 'March'
        WHEN '04' THEN 'April'
        WHEN '05' THEN 'May'
        WHEN '06' THEN 'June'
        WHEN '07' THEN 'July'
        WHEN '08' THEN 'August'
        WHEN '09' THEN 'September'
        WHEN '10' THEN 'October'
        WHEN '11' THEN 'November'
        WHEN '12' THEN 'December'

    END AS MonthName,


    CASE

        WHEN CAST(
            strftime('%m', MonthStartDate)
            AS INTEGER
        ) BETWEEN 1 AND 3
            THEN 'Q1'

        WHEN CAST(
            strftime('%m', MonthStartDate)
            AS INTEGER
        ) BETWEEN 4 AND 6
            THEN 'Q2'

        WHEN CAST(
            strftime('%m', MonthStartDate)
            AS INTEGER
        ) BETWEEN 7 AND 9
            THEN 'Q3'

        ELSE 'Q4'

    END AS Quarter,


    CAST(
        strftime(
            '%Y',
            MonthStartDate
        ) AS INTEGER
    )

    AS Year,


    /* NZ seasons */
    CASE

        WHEN strftime(
            '%m',
            MonthStartDate
        ) IN (
            '12',
            '01',
            '02'
        )
            THEN 'Summer'


        WHEN strftime(
            '%m',
            MonthStartDate
        ) IN (
            '03',
            '04',
            '05'
        )
            THEN 'Autumn'


        WHEN strftime(
            '%m',
            MonthStartDate
        ) IN (
            '06',
            '07',
            '08'
        )
            THEN 'Winter'


        ELSE 'Spring'

    END AS Season


FROM MonthSeries

ORDER BY MonthStartDate;



/* ============================================================
   2. LOCATION DIMENSION
   ============================================================

   Attribute hierarchy:
       Island -> RTO
   ============================================================ */


CREATE TABLE DimLocation (

    LocationKey INTEGER PRIMARY KEY,

    RTOCode INTEGER NOT NULL UNIQUE,

    RTOName TEXT NOT NULL,

    RTOLabel TEXT,

    Island TEXT NOT NULL
        CHECK (
            Island IN (
                'North Island',
                'South Island',
                'Other'
            )
        )
);



/* ------------------------------------------------------------
   Populate from the cleaned RTO mapping table.

   Codes 1-23:
       North Island

   Codes 24-40:
       South Island

   Code 99:
       Area Outside RTO -> Other
   ------------------------------------------------------------ */


INSERT INTO DimLocation (

    LocationKey,
    RTOCode,
    RTOName,
    RTOLabel,
    Island

)

SELECT

    RTO_Code
        AS LocationKey,

    RTO_Code
        AS RTOCode,

    RTO2025_V1_00_NAME
        AS RTOName,

    RTO_Label_2025
        AS RTOLabel,


    CASE

        WHEN RTO_Code
             BETWEEN 1 AND 23

            THEN 'North Island'


        WHEN RTO_Code
             BETWEEN 24 AND 40

            THEN 'South Island'


        ELSE 'Other'

    END AS Island


FROM RTO_Areas_Mapping_Clean

ORDER BY RTO_Code;



/* ============================================================
   3. VISITOR TYPE DIMENSION
   ============================================================ */


CREATE TABLE DimVisitorType (

    VisitorTypeKey INTEGER PRIMARY KEY,

    VisitorType TEXT NOT NULL UNIQUE

        CHECK (
            VisitorType IN (
                'Domestic',
                'International'
            )
        )
);



INSERT INTO DimVisitorType (

    VisitorTypeKey,
    VisitorType

)

VALUES

    (1, 'Domestic'),

    (2, 'International');



/* ============================================================
   4. MONTHLY TOURISM FACT TABLE
   ============================================================

   Grain:
       One row per
       Month + RTO + Visitor Type

   Measures:
       SpendMillion
       GuestNights
       VisitorCount

   NULL is preserved where one source does not provide data.
   Missing values are not automatically converted to zero.
   ============================================================ */


CREATE TABLE FactTourismMonthly (

    FactID INTEGER
        PRIMARY KEY AUTOINCREMENT,


    DateKey INTEGER NOT NULL,


    LocationKey INTEGER NOT NULL,


    VisitorTypeKey INTEGER NOT NULL,


    SpendMillion REAL,


    GuestNights INTEGER,


    VisitorCount INTEGER,


    FOREIGN KEY (
        DateKey
    )
        REFERENCES DimDate(
            DateKey
        ),


    FOREIGN KEY (
        LocationKey
    )
        REFERENCES DimLocation(
            LocationKey
        ),


    FOREIGN KEY (
        VisitorTypeKey
    )
        REFERENCES DimVisitorType(
            VisitorTypeKey
        ),


    UNIQUE (
        DateKey,
        LocationKey,
        VisitorTypeKey
    )

);



/* ============================================================
   5. POPULATE FACT TABLE
   ============================================================ */


/* ------------------------------------------------------------
   Step A:
   Create all Month + RTO + Visitor Type combinations
   appearing in at least one source.

   UNION is intentional.

   This prevents us from losing a valid RTO/month just because
   one of the three datasets does not report that RTO.
   ------------------------------------------------------------ */


WITH

FactKeys AS (

    SELECT
        RTO_Code,
        Month,
        Visitor_type

    FROM Spend_Clean


    UNION


    SELECT
        RTO_Code,
        Month,
        Visitor_type

    FROM ADP_Nights_Clean


    UNION


    SELECT
        RTO_Code,
        Month,
        Visitor_type

    FROM Visitor_Count_Clean

),



/* ------------------------------------------------------------
   Step B:
   Aggregate tourism spending to the common fact grain.

   Product and Origin are deliberately removed here because
   the analytical fact table is at:
       RTO + Month + Visitor Type

   Monthly_Spend_Million is used rather than annual spending.
   ------------------------------------------------------------ */


SpendAgg AS (

    SELECT

        RTO_Code,

        Month,

        Visitor_type,

        SUM(
            Monthly_Spend_Million
        ) AS SpendMillion


    FROM Spend_Clean


    GROUP BY

        RTO_Code,

        Month,

        Visitor_type

),



/* ------------------------------------------------------------
   Step C:
   Aggregate guest nights across accommodation property types.
   ------------------------------------------------------------ */


NightsAgg AS (

    SELECT

        RTO_Code,

        Month,

        Visitor_type,

        SUM(
            Total_stay_nights
        ) AS GuestNights


    FROM ADP_Nights_Clean


    GROUP BY

        RTO_Code,

        Month,

        Visitor_type

),



/* ------------------------------------------------------------
   Step D:
   Standardise visitor counts to the same grain.
   SUM() is used defensively even though the cleaned table
   already has a uniqueness rule for RTO + visitor type + month.
   ------------------------------------------------------------ */


VisitorsAgg AS (

    SELECT

        RTO_Code,

        Month,

        Visitor_type,

        SUM(
            Visitor_count
        ) AS VisitorCount


    FROM Visitor_Count_Clean


    GROUP BY

        RTO_Code,

        Month,

        Visitor_type

)



/* ------------------------------------------------------------
   Step E:
   Load all measures into the fact table.
   ------------------------------------------------------------ */


INSERT INTO FactTourismMonthly (

    DateKey,

    LocationKey,

    VisitorTypeKey,

    SpendMillion,

    GuestNights,

    VisitorCount

)


SELECT

    d.DateKey,

    l.LocationKey,

    v.VisitorTypeKey,

    s.SpendMillion,

    n.GuestNights,

    vc.VisitorCount


FROM FactKeys fk


JOIN DimDate d

    ON d.MonthStartDate
       = fk.Month


JOIN DimLocation l

    ON l.RTOCode
       = fk.RTO_Code


JOIN DimVisitorType v

    ON v.VisitorType
       = fk.Visitor_type


LEFT JOIN SpendAgg s

    ON s.RTO_Code
       = fk.RTO_Code

   AND s.Month
       = fk.Month

   AND s.Visitor_type
       = fk.Visitor_type


LEFT JOIN NightsAgg n

    ON n.RTO_Code
       = fk.RTO_Code

   AND n.Month
       = fk.Month

   AND n.Visitor_type
       = fk.Visitor_type


LEFT JOIN VisitorsAgg vc

    ON vc.RTO_Code
       = fk.RTO_Code

   AND vc.Month
       = fk.Month

   AND vc.Visitor_type
       = fk.Visitor_type;
   
   

/* ============================================================
   6. INDEXES
   ============================================================ */


CREATE INDEX idx_fact_date

ON FactTourismMonthly(
    DateKey
);


CREATE INDEX idx_fact_location

ON FactTourismMonthly(
    LocationKey
);


CREATE INDEX idx_fact_visitor_type

ON FactTourismMonthly(
    VisitorTypeKey
);


CREATE INDEX idx_fact_location_date

ON FactTourismMonthly(
    LocationKey,
    DateKey
);



/* ============================================================
   7. BASIC STAR SCHEMA VALIDATION
   ============================================================ */


/* Check date dimension */
SELECT *
FROM DimDate
ORDER BY DateKey;


/* Check location and island mapping */
SELECT
    RTOCode,
    RTOName,
    RTOLabel,
    Island

FROM DimLocation

ORDER BY RTOCode;


/* Check visitor dimension */
SELECT *
FROM DimVisitorType;


/* Check resulting fact rows */
SELECT

    d.MonthStartDate,

    l.RTOName,

    l.Island,

    v.VisitorType,

    f.SpendMillion,

    f.GuestNights,

    f.VisitorCount


FROM FactTourismMonthly f


JOIN DimDate d
    ON f.DateKey
       = d.DateKey


JOIN DimLocation l
    ON f.LocationKey
       = l.LocationKey


JOIN DimVisitorType v
    ON f.VisitorTypeKey
       = v.VisitorTypeKey


ORDER BY

    d.MonthStartDate,

    l.RTOName,

    v.VisitorType


LIMIT 50;


/* Check for missing measures */
SELECT
    COUNT(*) AS TotalFactRows,

    SUM(
        CASE
            WHEN SpendMillion IS NULL THEN 1
            ELSE 0
        END
    ) AS MissingSpendRows,

    SUM(
        CASE
            WHEN GuestNights IS NULL THEN 1
            ELSE 0
        END
    ) AS MissingGuestNightRows,

    SUM(
        CASE
            WHEN VisitorCount IS NULL THEN 1
            ELSE 0
        END
    ) AS MissingVisitorCountRows

FROM FactTourismMonthly;


/* Check coverage by RTO */
SELECT
    l.RTOName,
    l.Island,

    COUNT(*) AS FactRows,

    SUM(
        CASE
            WHEN f.SpendMillion IS NOT NULL THEN 1
            ELSE 0
        END
    ) AS SpendObservations,

    SUM(
        CASE
            WHEN f.GuestNights IS NOT NULL THEN 1
            ELSE 0
        END
    ) AS GuestNightObservations,

    SUM(
        CASE
            WHEN f.VisitorCount IS NOT NULL THEN 1
            ELSE 0
        END
    ) AS VisitorCountObservations

FROM FactTourismMonthly f

JOIN DimLocation l
    ON f.LocationKey = l.LocationKey

GROUP BY
    l.LocationKey,
    l.RTOName,
    l.Island

ORDER BY
    l.Island,
    l.RTOName;



/* ============================================================
   8. MONTH-LEVEL DATA COMPLETENESS CHECK
   ============================================================ */


SELECT

    d.MonthStartDate,

    d.MonthName,

    d.Year,


    CASE

        WHEN s.Month IS NOT NULL
            THEN 'Available'

        ELSE 'Missing'

    END AS SpendData,


    CASE

        WHEN n.Month IS NOT NULL
            THEN 'Available'

        ELSE 'Missing'

    END AS GuestNightData,


    CASE

        WHEN v.Month IS NOT NULL
            THEN 'Available'

        ELSE 'Missing'

    END AS VisitorCountData


FROM DimDate d


LEFT JOIN (

    SELECT DISTINCT Month

    FROM Spend_Clean

) s

    ON d.MonthStartDate
       = s.Month


LEFT JOIN (

    SELECT DISTINCT Month

    FROM ADP_Nights_Clean

) n

    ON d.MonthStartDate
       = n.Month


LEFT JOIN (

    SELECT DISTINCT Month

    FROM Visitor_Count_Clean

) v

    ON d.MonthStartDate
       = v.Month


ORDER BY d.MonthStartDate;



/* ============================================================
   9. RTO-MONTH SPENDING COVERAGE CHECK

   Creates the expected combination of every RTO and every
   month, then identifies combinations absent from Spend_Clean.
   ============================================================ */


SELECT

    l.RTOName,

    l.Island,

    d.MonthStartDate


FROM DimLocation l


CROSS JOIN DimDate d


LEFT JOIN (

    SELECT DISTINCT

        RTO_Code,

        Month

    FROM Spend_Clean

) s

    ON s.RTO_Code
       = l.RTOCode

   AND s.Month
       = d.MonthStartDate


WHERE

    l.Island IN (
        'North Island',
        'South Island'
    )

    AND s.RTO_Code IS NULL


ORDER BY

    l.RTOName,

    d.MonthStartDate;

 
 
 /* ============================================================
   RESEARCH QUESTION 1

   How does tourism spending seasonality vary across RTOs
   and between the North and South Islands?

   Analysis period: 2024-2025 complete calendar years

   Seasonality Index:
       100 = average monthly spending
       >100 = above average
       <100 = below average
   ============================================================ */

WITH MonthlySpend AS (

    /* Total spending for each RTO in each calendar month */
    SELECT
        d.Year,
        d.MonthNumber,
        d.MonthName,
        l.Island,
        l.RTOName,

        SUM(f.SpendMillion) AS TotalSpendMillion

    FROM FactTourismMonthly f

    JOIN DimDate d
        ON f.DateKey = d.DateKey

    JOIN DimLocation l
        ON f.LocationKey = l.LocationKey

    WHERE
        f.SpendMillion IS NOT NULL
        AND l.Island IN ('North Island', 'South Island')
        AND d.Year IN (2024, 2025)

    GROUP BY
        d.Year,
        d.MonthNumber,
        d.MonthName,
        l.Island,
        l.RTOName
),


/* Average spending for each calendar month across 2024-2025 */
RTOMonthAverage AS (

    SELECT
        'RTO' AS AnalysisLevel,
        Island,
        RTOName AS Area,
        MonthNumber,
        MonthName,

        AVG(TotalSpendMillion)
            AS AvgMonthlySpendMillion

    FROM MonthlySpend

    GROUP BY
        Island,
        RTOName,
        MonthNumber,
        MonthName
),


/* Aggregate RTO spending to island level */
IslandYearMonth AS (

    SELECT
        Year,
        MonthNumber,
        MonthName,
        Island,

        SUM(TotalSpendMillion)
            AS TotalSpendMillion

    FROM MonthlySpend

    GROUP BY
        Year,
        MonthNumber,
        MonthName,
        Island
),


IslandMonthAverage AS (

    SELECT
        'Island' AS AnalysisLevel,
        Island,
        Island AS Area,
        MonthNumber,
        MonthName,

        AVG(TotalSpendMillion)
            AS AvgMonthlySpendMillion

    FROM IslandYearMonth

    GROUP BY
        Island,
        MonthNumber,
        MonthName
),


Combined AS (

    SELECT *
    FROM RTOMonthAverage

    UNION ALL

    SELECT *
    FROM IslandMonthAverage
),


/* Calculate average monthly baseline for each RTO / island */
WithBaseline AS (

    SELECT
        *,

        AVG(AvgMonthlySpendMillion)
        OVER (
            PARTITION BY AnalysisLevel, Area
        ) AS AreaAverageMonthlySpend

    FROM Combined
)


SELECT
    AnalysisLevel,
    Island,
    Area AS RTO_or_Island,
    MonthNumber,
    MonthName,

    ROUND(
        AvgMonthlySpendMillion,
        2
    ) AS AvgMonthlySpendMillion,

    ROUND(
        100.0
        * AvgMonthlySpendMillion
        / AreaAverageMonthlySpend,
        1
    ) AS SeasonalityIndex

FROM WithBaseline

ORDER BY
    CASE AnalysisLevel
        WHEN 'Island' THEN 1
        ELSE 2
    END,
    Island,
    RTO_or_Island,
    MonthNumber;
 
 
/* ============================================================
Report-ready explanation for QUESTION 1:

The first analysis examines how tourism spending varies throughout the year between the North and South Islands. 
To make the two islands comparable despite their different overall spending levels, a seasonality index was calculated, where a value of 100 represents the average monthly spending level for that island. 
Values above 100 indicate months with above-average tourism expenditure, while values below 100 indicate weaker-than-average months.

The results show that both islands experience clear seasonal patterns, with stronger spending during the summer period and lower spending during the middle of the year. 
However, the South Island displays noticeably greater seasonal variation. 
South Island spending rises to approximately 126% of its average monthly level in December and around 122% in January, before falling to about 73% in June. 
In comparison, the North Island also reaches a summer peak, but its decline during the lower-demand months is less pronounced.

This suggests that South Island tourism activity is more strongly concentrated around peak travel periods. 
As a result, South Island RTOs may be more exposed to changes in seasonal demand because a larger share of their annual tourism expenditure is generated during a relatively small number of high-demand months.

Business relevance:

For regional tourism organisations, stronger seasonality can create challenges such as fluctuating employment demand, pressure on infrastructure during peak periods, and under-utilisation of tourism capacity during quieter months. 
Destinations with highly seasonal demand may therefore benefit from strategies aimed at encouraging off-peak visitation.
============================================================ */
    
    
    
/* ============================================================
   RESEARCH QUESTION 2

   During months of lower international visitor demand,
   how do domestic visitor numbers, spending and guest nights
   change across RTOs?

   Low international demand =
   international visitor count below that RTO's own
   2024-2025 monthly average.
   ============================================================ */


WITH InternationalDemand AS (

    SELECT
        f.LocationKey,
        f.DateKey,

        f.VisitorCount
            AS InternationalVisitorCount

    FROM FactTourismMonthly f

    JOIN DimDate d
        ON f.DateKey = d.DateKey

    JOIN DimVisitorType v
        ON f.VisitorTypeKey = v.VisitorTypeKey

    WHERE
        v.VisitorType = 'International'
        AND f.VisitorCount IS NOT NULL
        AND d.Year IN (2024, 2025)
),


/* Average international demand for each RTO */
InternationalAverage AS (

    SELECT
        LocationKey,

        AVG(InternationalVisitorCount)
            AS AvgInternationalVisitors

    FROM InternationalDemand

    GROUP BY LocationKey
),


/* Classify each RTO-month */
DemandClassification AS (

    SELECT
        i.LocationKey,
        i.DateKey,

        CASE
            WHEN i.InternationalVisitorCount
                 < a.AvgInternationalVisitors
            THEN 'Low international demand'

            ELSE 'Other months'
        END AS DemandPeriod

    FROM InternationalDemand i

    JOIN InternationalAverage a
        ON i.LocationKey = a.LocationKey
),


/* Domestic measures from the fact table */
DomesticActivity AS (

    SELECT
        f.LocationKey,
        f.DateKey,

        f.VisitorCount
            AS DomesticVisitors,

        f.SpendMillion
            AS DomesticSpendMillion,

        f.GuestNights
            AS DomesticGuestNights

    FROM FactTourismMonthly f

    JOIN DimVisitorType v
        ON f.VisitorTypeKey = v.VisitorTypeKey

    JOIN DimDate d
        ON f.DateKey = d.DateKey

    WHERE
        v.VisitorType = 'Domestic'
        AND d.Year IN (2024, 2025)
),


/* Calculate averages for low-demand and other months */
Comparison AS (

    SELECT
        l.RTOName,
        l.Island,
        dc.DemandPeriod,

        COUNT(*) AS NumberOfMonths,

        AVG(da.DomesticVisitors)
            AS AvgDomesticVisitors,

        AVG(da.DomesticSpendMillion)
            AS AvgDomesticSpendMillion,

        AVG(da.DomesticGuestNights)
            AS AvgDomesticGuestNights

    FROM DemandClassification dc

    JOIN DomesticActivity da
        ON da.LocationKey = dc.LocationKey
       AND da.DateKey = dc.DateKey

    JOIN DimLocation l
        ON l.LocationKey = dc.LocationKey

    WHERE
        l.Island IN ('North Island', 'South Island')

    GROUP BY
        l.RTOName,
        l.Island,
        dc.DemandPeriod
),


/* Put low-demand and other-month values into the same row */
Pivoted AS (

    SELECT
        RTOName,
        Island,

        MAX(
            CASE
                WHEN DemandPeriod = 'Low international demand'
                THEN NumberOfMonths
            END
        ) AS LowDemandMonths,


        MAX(
            CASE
                WHEN DemandPeriod = 'Low international demand'
                THEN AvgDomesticVisitors
            END
        ) AS LowVisitors,

        MAX(
            CASE
                WHEN DemandPeriod = 'Other months'
                THEN AvgDomesticVisitors
            END
        ) AS OtherVisitors,


        MAX(
            CASE
                WHEN DemandPeriod = 'Low international demand'
                THEN AvgDomesticSpendMillion
            END
        ) AS LowSpend,

        MAX(
            CASE
                WHEN DemandPeriod = 'Other months'
                THEN AvgDomesticSpendMillion
            END
        ) AS OtherSpend,


        MAX(
            CASE
                WHEN DemandPeriod = 'Low international demand'
                THEN AvgDomesticGuestNights
            END
        ) AS LowNights,

        MAX(
            CASE
                WHEN DemandPeriod = 'Other months'
                THEN AvgDomesticGuestNights
            END
        ) AS OtherNights

    FROM Comparison

    GROUP BY
        RTOName,
        Island
)


SELECT
    RTOName,
    Island,
    LowDemandMonths,


    ROUND(
        LowVisitors,
        0
    ) AS AvgDomesticVisitors_LowDemand,

    ROUND(
        100.0
        * (LowVisitors - OtherVisitors)
        / NULLIF(OtherVisitors, 0),
        1
    ) AS VisitorDiffPct,


    ROUND(
        LowSpend,
        2
    ) AS AvgDomesticSpendMillion_LowDemand,

    ROUND(
        100.0
        * (LowSpend - OtherSpend)
        / NULLIF(OtherSpend, 0),
        1
    ) AS SpendDiffPct,


    ROUND(
        LowNights,
        0
    ) AS AvgDomesticGuestNights_LowDemand,

    ROUND(
        100.0
        * (LowNights - OtherNights)
        / NULLIF(OtherNights, 0),
        1
    ) AS GuestNightsDiffPct


FROM Pivoted

WHERE LowDemandMonths IS NOT NULL

ORDER BY
    SpendDiffPct DESC;
    
    
/* ============================================================
Report-ready explanation for QUESTION 2:

The second analysis investigates whether domestic tourism activity changes during months when international visitor demand is relatively low. 
For each RTO, a low international-demand month was defined as a month in which the international visitor count fell below that RTO’s average
monthly international visitor count during 2024–2025. 
Domestic visitor numbers, tourism spending and guest nights during these months were then compared with the remaining months.

The results show that domestic tourism does not respond uniformly across RTOs. 
In many regions, domestic visitor counts and guest nights are lower during periods of weak international demand. 
However, domestic spending does not always decline at the same time. 
Several RTOs record higher domestic expenditure even when domestic visitor numbers are lower.

Ruapehu provides the most notable example. 
During low international-demand months, domestic visitor numbers fall by approximately 17.6%, while domestic spending increases by around 110.7%. 
Queenstown also shows a contrasting pattern, with domestic visitor numbers decreasing by about 23.6% while domestic spending increases by approximately 10.9%.

These findings indicate that visitor numbers alone do not fully explain the economic contribution of domestic tourism. 
A smaller number of visitors may still generate relatively high levels of expenditure, meaning that domestic tourism can potentially provide some economic support during periods of weaker international demand.

Important interpretation note:

The data show the relationship between lower international demand and domestic tourism outcomes, but they do not directly explain why these patterns occur. 
For example, higher domestic spending in Ruapehu may be associated with a high-value seasonal market, but the datasets used in this project do not contain trip-purpose information, so this cannot be confirmed from the warehouse alone.

Business relevance:

This analysis is useful for RTOs because it highlights the potential role of domestic tourism as a source of resilience. 
Regions where domestic spending remains strong during periods of weak international demand may be better positioned to absorb temporary declines in international tourism.
============================================================ */
    
    
    
 /* ============================================================
   RESEARCH QUESTION 3

   Which RTOs appear most dependent on peak-season or
   international demand, and therefore potentially more
   vulnerable to tourism shocks?

   Analysis period: 2024-2025

   Indicators:
   1. International spending share
   2. Share of spending concentrated in the RTO's top
      three spending months
   3. Composite vulnerability score
   ============================================================ */


WITH MonthlyTypeSpend AS (

    SELECT
        l.LocationKey,
        l.RTOName,
        l.Island,

        d.Year,
        d.MonthNumber,
        d.MonthName,

        v.VisitorType,

        SUM(f.SpendMillion)
            AS SpendMillion

    FROM FactTourismMonthly f

    JOIN DimDate d
        ON f.DateKey = d.DateKey

    JOIN DimLocation l
        ON f.LocationKey = l.LocationKey

    JOIN DimVisitorType v
        ON f.VisitorTypeKey = v.VisitorTypeKey

    WHERE
        f.SpendMillion IS NOT NULL
        AND l.Island IN ('North Island', 'South Island')
        AND d.Year IN (2024, 2025)

    GROUP BY
        l.LocationKey,
        l.RTOName,
        l.Island,
        d.Year,
        d.MonthNumber,
        d.MonthName,
        v.VisitorType
),


/* Average each calendar month across the two years */
MonthAverages AS (

    SELECT
        LocationKey,
        RTOName,
        Island,
        MonthNumber,
        MonthName,

        AVG(
            CASE
                WHEN VisitorType = 'Domestic'
                THEN SpendMillion
            END
        ) AS AvgDomesticSpend,

        AVG(
            CASE
                WHEN VisitorType = 'International'
                THEN SpendMillion
            END
        ) AS AvgInternationalSpend

    FROM MonthlyTypeSpend

    GROUP BY
        LocationKey,
        RTOName,
        Island,
        MonthNumber,
        MonthName
),


MonthTotals AS (

    SELECT
        *,

        COALESCE(AvgDomesticSpend, 0)
        +
        COALESCE(AvgInternationalSpend, 0)
            AS AvgTotalSpend

    FROM MonthAverages
),


/* Rank each RTO's months from highest to lowest spending */
RankedMonths AS (

    SELECT
        *,

        ROW_NUMBER()
        OVER (
            PARTITION BY LocationKey
            ORDER BY AvgTotalSpend DESC
        ) AS PeakRank

    FROM MonthTotals
),


Dependency AS (

    SELECT
        LocationKey,
        RTOName,
        Island,


        /* International dependence */
        100.0
        * SUM(
            COALESCE(AvgInternationalSpend, 0)
          )
        / NULLIF(
            SUM(AvgTotalSpend),
            0
          )
        AS InternationalSpendSharePct,


        /* Concentration in top three months */
        100.0
        * SUM(
            CASE
                WHEN PeakRank <= 3
                THEN AvgTotalSpend
                ELSE 0
            END
          )
        / NULLIF(
            SUM(AvgTotalSpend),
            0
          )
        AS Peak3MonthSpendSharePct,


        /* Identify the peak months themselves */
        GROUP_CONCAT(
            CASE
                WHEN PeakRank <= 3
                THEN MonthName
            END,
            ', '
        ) AS PeakMonths

    FROM RankedMonths

    GROUP BY
        LocationKey,
        RTOName,
        Island
)


SELECT
    RTOName,
    Island,

    ROUND(
        InternationalSpendSharePct,
        1
    ) AS InternationalSpendSharePct,

    ROUND(
        Peak3MonthSpendSharePct,
        1
    ) AS Peak3MonthSpendSharePct,

    ROUND(
        (
            InternationalSpendSharePct
            +
            Peak3MonthSpendSharePct
        ) / 2.0,
        1
    ) AS VulnerabilityScore,

    PeakMonths

FROM Dependency

ORDER BY
    VulnerabilityScore DESC;
    
    
/* ============================================================
Report-ready explanation for Question 3:

The third analysis identifies RTOs that appear most dependent on international tourism or concentrated peak-season demand. 
Two indicators were calculated for each RTO. 
The first measures the proportion of total tourism spending generated by international visitors. 
The second measures the proportion of spending concentrated in the RTO’s three highest-spending calendar months. 
These two measures were combined using equal weighting to create an exploratory vulnerability score. 

The results indicate that Fiordland has the highest overall vulnerability score, followed by Mackenzie and Queenstown. 
Fiordland records an international spending share of approximately 67%, while around 36% of its spending is concentrated in its three strongest months. 
Mackenzie and Queenstown also show particularly high international dependence, with international visitor spending accounting for more than 60% of total tourism expenditure.

Other RTOs show a different type of exposure. 
Nelson Tasman, for example, has a lower international spending share than the highest-ranked destinations, but a relatively large proportion of spending is concentrated in its peak months.
This means that tourism vulnerability can arise in different ways: some destinations are more exposed to international travel disruptions, while others are more dependent on a narrow seasonal window.

The ranking therefore suggests that tourism resilience should not be assessed using only one indicator. 
A destination can be vulnerable because of international dependence, seasonal concentration, or a combination of both.

Important interpretation note:

The vulnerability score is a project-defined analytical measure rather than an official MBIE indicator. 
(!!!OUR OWN ASSUMPTION for the weight allocation!!!)
The two components are weighted equally for comparison purposes, so the ranking should be interpreted as an exploratory tool rather than a definitive measure of regional economic risk.

Business relevance:

RTOs with high international dependence may benefit from greater domestic market diversification, while destinations with strong peak-season concentration may benefit from developing off-season products, events or campaigns. 
The results can therefore support more targeted tourism resilience strategies.
============================================================ */