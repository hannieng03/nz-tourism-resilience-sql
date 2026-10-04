/* =========================================================
   DISABLE FOREIGN KEYS WHILE REBUILDING TABLES
   ========================================================= */

PRAGMA foreign_keys = OFF;

DROP TABLE IF EXISTS Visitor_Count_Clean;
DROP TABLE IF EXISTS ADP_Nights_Clean;
DROP TABLE IF EXISTS Spend_Clean;
DROP TABLE IF EXISTS RTO_Areas_Mapping_Clean;

PRAGMA foreign_keys = ON;


/* =========================================================
   1. RTO DIMENSION TABLE
   Must be created before the fact tables.
   ========================================================= */

CREATE TABLE RTO_Areas_Mapping_Clean (
    RTO_Code                   INTEGER PRIMARY KEY,
    RTO2025_V1_00_NAME         TEXT NOT NULL UNIQUE,
    RTO2025_V1_00_NAME_ASCII   TEXT,
    RTO_Label_2025             TEXT,
    RTO_Label_2025_ASCII       TEXT UNIQUE
);


/* Insert cleaned RTO mapping data */

INSERT INTO RTO_Areas_Mapping_Clean (
    RTO_Code,
    RTO2025_V1_00_NAME,
    RTO2025_V1_00_NAME_ASCII,
    RTO_Label_2025,
    RTO_Label_2025_ASCII
)
SELECT
    CAST(RTO2025_V1_00 AS INTEGER),

    TRIM(RTO2025_V1_00_NAME),

    NULLIF(
        TRIM(RTO2025_V1_00_NAME_ASCII),
        'null'
    ),

    NULLIF(
        TRIM(RTO_Label_2025),
        'null'
    ),

    NULLIF(
        TRIM(RTO_Label_2025_ASCII),
        'null'
    )

FROM "Raw-RTO Areas Mapping";


/* =========================================================
   2. VISITOR COUNTS FACT TABLE
   ========================================================= */

CREATE TABLE Visitor_Count_Clean (
    Visitor_Count_ID INTEGER PRIMARY KEY,

    RTO_Code INTEGER NOT NULL,

    Destination TEXT NOT NULL,

    Visitor_type TEXT NOT NULL
        CHECK (
            Visitor_type IN (
                'Domestic',
                'International'
            )
        ),

    Month TEXT NOT NULL,

    Visitor_count INTEGER NOT NULL
        CHECK (Visitor_count >= 0),

    FOREIGN KEY (RTO_Code)
        REFERENCES RTO_Areas_Mapping_Clean(RTO_Code),

    UNIQUE (
        RTO_Code,
        Visitor_type,
        Month
    )
);


/* Insert cleaned visitor-count data */

INSERT INTO Visitor_Count_Clean (
    RTO_Code,
    Destination,
    Visitor_type,
    Month,
    Visitor_count
)
SELECT
    CAST(
        SUBSTR(
            TRIM(Destination_code),
            -2
        ) AS INTEGER
    ) AS RTO_Code,

    TRIM(
        REPLACE(
            Destination,
            ' RTO',
            ''
        )
    ) AS Destination,

    CASE
        WHEN TRIM(Population_segment) =
             'Domestic visitor'
            THEN 'Domestic'

        WHEN TRIM(Population_segment) =
             'Total international visitor'
            THEN 'International'
    END AS Visitor_type,

    /* Supports DD/MM/YYYY and YYYY-MM-DD */
    CASE
        WHEN INSTR(TRIM(Date), '/') > 0
        THEN DATE(
            SUBSTR(TRIM(Date), -4)
            || '-'
            || PRINTF(
                '%02d',
                CAST(
                    SUBSTR(
                        TRIM(Date),
                        INSTR(TRIM(Date), '/') + 1,
                        INSTR(
                            SUBSTR(
                                TRIM(Date),
                                INSTR(TRIM(Date), '/') + 1
                            ),
                            '/'
                        ) - 1
                    ) AS INTEGER
                )
            )
            || '-01'
        )

        ELSE DATE(Date, 'start of month')
    END AS Month,

    CAST(
        Monthly_unique_counts
        AS INTEGER
    ) AS Visitor_count

FROM Visitor_Count_Raw

WHERE TRIM(Geographic_level_destination) = 'RTO'

  AND TRIM(Population_segment) IN (
      'Domestic visitor',
      'Total international visitor'
  );


/* =========================================================
   3. ACCOMMODATION NIGHTS FACT TABLE
   ========================================================= */

CREATE TABLE ADP_Nights_Clean (
    ADP_Nights_ID INTEGER PRIMARY KEY,

    RTO_Code INTEGER NOT NULL,

    Month TEXT NOT NULL,

    Property TEXT NOT NULL,

    Visitor_type TEXT NOT NULL
        CHECK (
            Visitor_type IN (
                'Domestic',
                'International'
            )
        ),

    Total_stay_nights INTEGER NOT NULL
        CHECK (Total_stay_nights >= 0),

    FOREIGN KEY (RTO_Code)
        REFERENCES RTO_Areas_Mapping_Clean(RTO_Code),

    UNIQUE (
        RTO_Code,
        Month,
        Property,
        Visitor_type
    )
);


/* Insert cleaned accommodation data */

INSERT INTO ADP_Nights_Clean (
    RTO_Code,
    Month,
    Property,
    Visitor_type,
    Total_stay_nights
)

WITH ADP_Standardised AS (
    SELECT
        /* Convert DD/MM/YYYY into YYYY-MM-01 */
        CASE
            WHEN INSTR(TRIM(Month), '/') > 0
            THEN DATE(
                SUBSTR(TRIM(Month), -4)
                || '-'
                || PRINTF(
                    '%02d',
                    CAST(
                        SUBSTR(
                            TRIM(Month),
                            INSTR(TRIM(Month), '/') + 1,
                            INSTR(
                                SUBSTR(
                                    TRIM(Month),
                                    INSTR(TRIM(Month), '/') + 1
                                ),
                                '/'
                            ) - 1
                        ) AS INTEGER
                    )
                )
                || '-01'
            )

            ELSE DATE(Month, 'start of month')
        END AS Clean_Month,

        TRIM(
            CASE
                WHEN TRIM(Area) LIKE '% RTO'
                    THEN SUBSTR(
                        TRIM(Area),
                        1,
                        LENGTH(TRIM(Area)) - 4
                    )
                ELSE TRIM(Area)
            END
        ) AS Clean_Area,

        TRIM(Property) AS Property,

        CASE
            WHEN TRIM(Measure) =
                 'Domestic guest nights'
                THEN 'Domestic'

            WHEN TRIM(Measure) =
                 'International guest nights'
                THEN 'International'
        END AS Visitor_type,

        CAST(Value AS INTEGER)
            AS Total_stay_nights

    FROM "Raw-ADP(nights)"

    WHERE TRIM("Area type") = 'RTO'

      AND TRIM(Area) <> 'Total New Zealand'

      AND TRIM(Property) <> 'Total'

      AND TRIM(Measure) IN (
          'Domestic guest nights',
          'International guest nights'
      )

      AND COALESCE(
          TRIM(Flag),
          ''
      ) <> 'c'
)

SELECT
    r.RTO_Code,
    a.Clean_Month,
    a.Property,
    a.Visitor_type,
    a.Total_stay_nights

FROM ADP_Standardised AS a

INNER JOIN RTO_Areas_Mapping_Clean AS r
    ON a.Clean_Area = r.RTO2025_V1_00_NAME

WHERE a.Clean_Month
      BETWEEN '2024-01-01' AND '2026-06-01';


/* =========================================================
   4. TOURISM SPENDING FACT TABLE
   ========================================================= */

CREATE TABLE Spend_Clean (
    Spend_ID INTEGER PRIMARY KEY,

    RTO_Code INTEGER NOT NULL,

    Month TEXT NOT NULL,

    Product TEXT NOT NULL,

    Visitor_type TEXT NOT NULL
        CHECK (
            Visitor_type IN (
                'Domestic',
                'International'
            )
        ),

    Origin TEXT NOT NULL,

    Annual_Spend_Million REAL,

    Monthly_Spend_Million REAL,

    FOREIGN KEY (RTO_Code)
        REFERENCES RTO_Areas_Mapping_Clean(RTO_Code),

    UNIQUE (
        RTO_Code,
        Month,
        Product,
        Visitor_type,
        Origin
    )
);


/* Insert cleaned tourism-spending data */

INSERT INTO Spend_Clean (
    RTO_Code,
    Month,
    Product,
    Visitor_type,
    Origin,
    Annual_Spend_Million,
    Monthly_Spend_Million
)

WITH Spend_Standardised AS (
    SELECT
        /* Convert DD/MM/YYYY into YYYY-MM-01 */
        CASE
            WHEN INSTR(TRIM(Date), '/') > 0
            THEN DATE(
                SUBSTR(TRIM(Date), -4)
                || '-'
                || PRINTF(
                    '%02d',
                    CAST(
                        SUBSTR(
                            TRIM(Date),
                            INSTR(TRIM(Date), '/') + 1,
                            INSTR(
                                SUBSTR(
                                    TRIM(Date),
                                    INSTR(TRIM(Date), '/') + 1
                                ),
                                '/'
                            ) - 1
                        ) AS INTEGER
                    )
                )
                || '-01'
            )

            ELSE DATE(Date, 'start of month')
        END AS Clean_Month,

        TRIM(RTO) AS Clean_RTO,

        TRIM(Product) AS Product,

        CASE
            WHEN TRIM("Visitor Type") =
                 'New Zealand'
                THEN 'Domestic'

            WHEN TRIM("Visitor Type") =
                 'International'
                THEN 'International'
        END AS Visitor_type,

        TRIM(Origin) AS Origin,

        CAST(
            TRIM("Annual Spend")
            AS REAL
        ) AS Annual_Spend_Million,

        CAST(
            TRIM("Monthly Spend")
            AS REAL
        ) AS Monthly_Spend_Million

    FROM Raw_Spend

    WHERE TRIM(RTO) NOT IN (
        'Area Outside RTO',
        'non-RTO - Horowhenua',
        'non-RTO - Kawerau',
        'non-RTO - Otorohanga',
        'non-RTO - Rangitikei',
        'non-RTO - South Waikato',
        'non-RTO - Tararua',
        'non-RTO - Waimate',
        'non-RTO - Waitomo',
        'non-RTO - Whakatane'
    )

      AND TRIM("Visitor Type") IN (
          'New Zealand',
          'International'
      )
)

SELECT
    r.RTO_Code,
    s.Clean_Month,
    s.Product,
    s.Visitor_type,
    s.Origin,
    s.Annual_Spend_Million,
    s.Monthly_Spend_Million

FROM Spend_Standardised AS s

INNER JOIN RTO_Areas_Mapping_Clean AS r
    ON s.Clean_RTO = r.RTO_Label_2025_ASCII

WHERE s.Clean_Month
      BETWEEN '2024-01-01' AND '2026-06-01';

/*
CODE FOR DELETING OLD TABLE
DROP TABLE IF EXISTS Visitor_Count_Raw;
DROP TABLE IF EXISTS [Raw-ADP(nights)];
DROP TABLE IF EXISTS Raw_Spend;
DROP TABLE IF EXISTS Raw-RTO Areas Mapping;
*/ 

DROP TABLE IF EXISTS Visitor_Count_Raw;
DROP TABLE IF EXISTS [Raw-ADP(nights)];
DROP TABLE IF EXISTS Raw_Spend;
DROP TABLE IF EXISTS [Raw-RTO Areas Mapping];

