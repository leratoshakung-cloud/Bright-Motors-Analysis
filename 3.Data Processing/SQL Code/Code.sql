-- Set legacy time parser for compatibility
SET spark.sql.legacy.timeParserPolicy=LEGACY;

-- Create temp view from CSV file in Unity Catalog volume
-- Filter out 26 misaligned rows (0.005% of data)
CREATE OR REPLACE TEMP VIEW Bright_motors AS
SELECT 
  CAST(year AS INT) AS year,
  make,
  model,
  trim,
  body,
  transmission,
  vin,
  state,
  CAST(condition AS INT) AS condition,
  CAST(odometer AS INT) AS odometer,
  color,
  interior,
  seller,
  CAST(mmr AS INT) AS mmr,
  CAST(sellingprice AS INT) AS sellingprice,
  TRY_TO_TIMESTAMP(saledate, 'EEE MMM dd yyyy HH:mm:ss') AS saledate
FROM read_files(
  '/Volumes/workspace/default/data_files/car_sales_dataset.csv',
  format => 'csv',
  header => true,
  inferSchema => true,
  delimiter => ';',
  multiLine => true,
  escape => '"',
  quote => '"',
  mode => 'PERMISSIVE'
)
WHERE saledate RLIKE '^[A-Za-z]';  -- Only keep rows with valid dates

--checking start and end date
SELECT MIN(saledate) AS start_date,
       MAX(saledate) AS last_date
FROM Bright_motors
WHERE saledate IS NOT NULL

--counting total records
SELECT
COUNT(*) AS total_records
FROM Bright_motors;

-- Count rows by make
SELECT 
  make,
  COUNT(*) as vehicle_count
FROM SELECT vin, COUNT(*) AS duplicate_count
FROM `workspace`.`default`.`Bright_motors` 
GROUP BY vin
HAVING COUNT(*) > 1;
GROUP BY make
ORDER BY vehicle_count DESC;

--Check duplicates Using VIN 
SELECT vin, COUNT(*) AS duplicate_count
FROM Bright_motors 
GROUP BY vin
HAVING COUNT(*) > 1;

-- Top 10 Most Resold Vehicles
WITH duplicate_vins AS (
  SELECT vin, COUNT(*) as resale_count
  FROM Bright_motors
  GROUP BY vin
  HAVING COUNT(*) > 1
)
SELECT 
  d.vin,
  d.resale_count,
  b.make,
  b.model,
  b.year,
  b.body,
  b.color,
  MIN(b.sellingprice) as lowest_sale_price,
  MAX(b.sellingprice) as highest_sale_price,
  MAX(b.sellingprice) - MIN(b.sellingprice) as price_difference,
  MIN(b.saledate) as first_sale_date,
  MAX(b.saledate) as last_sale_date
FROM duplicate_vins d
JOIN Bright_motors b ON d.vin = b.vin
GROUP BY d.vin, d.resale_count, b.make, b.model, b.year, b.body, b.color
ORDER BY d.resale_count DESC, price_difference DESC
LIMIT 10;

--Date functions
SELECT 
DAY(saledate) AS sale_day,
MONTHNAME(saledate) AS sale_month,
YEAR(saledate) AS sale_year
FROM Bright_motors;

--checking Mileage band using case statement
SELECT *,
CASE
    WHEN odometer BETWEEN 0 AND 25000 THEN '1.Low (0-25K mi)'
    WHEN odometer BETWEEN 25001 AND 75000 THEN '2.Standard (25K-75K mi)'
    WHEN odometer BETWEEN 75001 AND 150000 THEN '3.High (75K-150K mi)'
    ELSE '4.Elevated (150K+ mi)'
END AS Mileage_Band
FROM Bright_motors;


--condition rating using case statement
SELECT *,
 CASE
        WHEN condition BETWEEN 37 AND 49 THEN '1.Excellent (>37)'
        WHEN condition BETWEEN 25 AND 36 THEN '2.Good(25-36)'
        WHEN condition BETWEEN 12 AND 24 THEN '3.Fair(12-24)'
        ELSE '4.Poor(<11)'
    END AS Condition_Rating
    FROM Bright_motors;

--creating price tier using case statement
SELECT *,
CASE
    WHEN sellingprice >= 50000 THEN '1.Luxury'
    WHEN sellingprice BETWEEN 30000 AND 49999 THEN '2.Premium'
    WHEN sellingprice BETWEEN 15000 AND 29999 THEN '3.Mid-Range'
    WHEN sellingprice BETWEEN 5000 AND 14999 THEN '4.Budget'
    ELSE '5.Under Value'
END AS price_tier
FROM Bright_motors;

--checking vehicle groups using case statement for body
SELECT *,
CASE
    WHEN body IN ('SUV', 'Wagon') THEN 'SUV/Wagon'
    WHEN body IN ('Sedan', 'Coupe') THEN 'Sedan/Coupe'
    WHEN body IN ('Truck', 'SuperCrew', 'Pickup') THEN 'Truck'
    WHEN body IN ('Convertible') THEN 'Convertible'
    WHEN body IN ('Van', 'Minivan') THEN 'Van'
    ELSE 'Other'
END AS vehicle_type
FROM Bright_motors;

--Checking color groups
SELECT *,
CASE
    WHEN LOWER(color) IN ('black', 'gray', 'grey', 'silver') THEN 'Neutral Dark'
    WHEN LOWER(color) IN ('white', 'beige', 'tan') THEN 'Neutral Light'
    WHEN LOWER(color) IN ('red', 'blue', 'green') THEN 'Primary Colors'
    WHEN LOWER(color) IN ('brown', 'gold', 'orange', 'yellow') THEN 'Warm Colors'
    ELSE 'Other'
END AS color_group
FROM Bright_motors;

--Checking state regions
SELECT *,
CASE
    WHEN state IN ('ca', 'or', 'wa', 'nv', 'az') THEN 'West Coast'
    WHEN state IN ('tx', 'ok', 'nm', 'la', 'ar') THEN 'Southwest'
    WHEN state IN ('ny', 'nj', 'pa', 'ma', 'ct') THEN 'Northeast'
    WHEN state IN ('il', 'oh', 'mi', 'in', 'wi') THEN 'Midwest'
    ELSE 'Other'
END AS region
FROM Bright_motors;

--creating transmission types bucket
SELECT *,
CASE
    WHEN LOWER(transmission) LIKE '%automatic%' THEN 'Automatic'
    WHEN LOWER(transmission) LIKE '%manual%' THEN 'Manual'
    ELSE 'Other/Unknown'
END AS transmission_type
FROM Bright_motors;

-- mmr (Manheim Market Report) - Market Value Categories
SELECT *,
CASE
    WHEN mmr >= 40000 THEN 'High Value'
    WHEN mmr BETWEEN 20000 AND 39999 THEN 'Mid Value'
    ELSE 'Low Value'
END AS market_value_category
FROM Bright_motors;

--Profit Calculation (sellingprice - mmr)
SELECT *,
CASE
    WHEN (sellingprice - mmr) > 5000 THEN 'High Profit'
    WHEN (sellingprice - mmr) BETWEEN 0 AND 5000 THEN 'Moderate Profit'
    WHEN (sellingprice - mmr) BETWEEN -2000 AND -1 THEN 'Small Loss'
    ELSE 'Significant Loss'
END AS profit_category
FROM Bright_motors;

--calculating profit or loss
SELECT *,
(sellingprice-mmr)AS Profit_or_Loss
FROM Bright_motors;

--calculating totals 
SELECT 
 SUM(sellingprice)AS Total_Revenue,
 SUM(mmr)AS Total_Cost,
 SUM(sellingprice)-SUM(mmr)AS Total_Profit,
 SUM(sellingprice)-SUM(mmr)AS Total_Profit,
 SUM(sellingprice)-SUM(mmr)/sum(sellingprice)AS profit_margin
 FROM Bright_motors;

--counting units solds
SELECT
COUNT(model) AS Quantity_Sold
FROM Bright_motors;

--calculating  revenue
SELECT
    AVG(sellingprice) AS Average_revenue
FROM Bright_motors;

-- Combined Query (Cells 22-24 Combined)
--Original columns (Cell 22)
SELECT 
    SUM(sellingprice) AS Total_Revenue,
    SUM(mmr) AS Total_Cost,
    SUM(sellingprice) - SUM(mmr) AS Total_Profit,
    (SUM(sellingprice) - SUM(mmr)) / SUM(sellingprice) AS Profit_Margin,
    
    -- Quantity (Cell 23)
    COUNT(model) AS Quantity_Sold,
    
    -- Averages (Cell 24)
    AVG(sellingprice) AS Average_Revenue,
    AVG(mmr) AS Average_Cost,
    AVG(sellingprice - mmr) AS Average_Profit
    
FROM Bright_motors;

-- Comprehensive Query: All Derived Columns Combined
SELECT 
    -- Original columns
    year,
    make,
    model,
    trim,
    body,
    transmission,
    vin,
    state,
    condition,
    odometer,
    color,
    interior,
    seller,
    mmr,
    sellingprice,
    saledate,
    
    -- Date components (Cell 11)
    DAY(saledate) AS sale_day,
    MONTHNAME(saledate) AS sale_month,
    YEAR(saledate) AS sale_year,
    
    -- Mileage Band (Cell 12)
    CASE
        WHEN odometer BETWEEN 0 AND 25000 THEN '1.Low (0-25K mi)'
        WHEN odometer BETWEEN 25001 AND 75000 THEN '2.Standard (25K-75K mi)'
        WHEN odometer BETWEEN 75001 AND 150000 THEN '3.High (75K-150K mi)'
        ELSE '4.Elevated (150K+ mi)'
    END AS Mileage_Band,
    
    -- Condition Rating (Cell 13)
    CASE
        WHEN condition BETWEEN 37 AND 49 THEN '1.Excellent (>37)'
        WHEN condition BETWEEN 25 AND 36 THEN '2.Good(25-36)'
        WHEN condition BETWEEN 12 AND 24 THEN '3.Fair(12-24)'
        ELSE '4.Poor(<11)'
    END AS Condition_Rating,
    
    -- Price Tier (Cell 14)
    CASE
        WHEN sellingprice >= 50000 THEN '1.Luxury'
        WHEN sellingprice BETWEEN 30000 AND 49999 THEN '2.Premium'
        WHEN sellingprice BETWEEN 15000 AND 29999 THEN '3.Mid-Range'
        WHEN sellingprice BETWEEN 5000 AND 14999 THEN '4.Budget'
        ELSE '5.Under Value'
    END AS price_tier,
    
    -- Vehicle Type (Cell 15)
    CASE
        WHEN body IN ('SUV', 'Wagon') THEN 'SUV/Wagon'
        WHEN body IN ('Sedan', 'Coupe') THEN 'Sedan/Coupe'
        WHEN body IN ('Truck', 'SuperCrew', 'Pickup') THEN 'Truck'
        WHEN body IN ('Convertible') THEN 'Convertible'
        WHEN body IN ('Van', 'Minivan') THEN 'Van'
        ELSE 'Other'
    END AS vehicle_type,
    
    -- Color Group (Cell 16)
    CASE
        WHEN LOWER(color) IN ('black', 'gray', 'grey', 'silver') THEN 'Neutral Dark'
        WHEN LOWER(color) IN ('white', 'beige', 'tan') THEN 'Neutral Light'
        WHEN LOWER(color) IN ('red', 'blue', 'green') THEN 'Primary Colors'
        WHEN LOWER(color) IN ('brown', 'gold', 'orange', 'yellow') THEN 'Warm Colors'
        ELSE 'Other'
    END AS color_group,
    
    -- Region (Cell 17)
    CASE
        WHEN state IN ('ca', 'or', 'wa', 'nv', 'az') THEN 'West Coast'
        WHEN state IN ('tx', 'ok', 'nm', 'la', 'ar') THEN 'Southwest'
        WHEN state IN ('ny', 'nj', 'pa', 'ma', 'ct') THEN 'Northeast'
        WHEN state IN ('il', 'oh', 'mi', 'in', 'wi') THEN 'Midwest'
        ELSE 'Other'
    END AS region,
    
    -- Transmission Type (Cell 18)
    CASE
        WHEN LOWER(transmission) LIKE '%automatic%' THEN 'Automatic'
        WHEN LOWER(transmission) LIKE '%manual%' THEN 'Manual'
        ELSE 'Other/Unknown'
    END AS transmission_type,
    
    -- Market Value Category (Cell 19)
    CASE
        WHEN mmr >= 40000 THEN 'High Value'
        WHEN mmr BETWEEN 20000 AND 39999 THEN 'Mid Value'
        ELSE 'Low Value'
    END AS market_value_category,
    
    -- Profit or Loss (Cell 21)
    (sellingprice - mmr) AS Profit_or_Loss,
    
    -- Profit Category (Cell 20)
    CASE
        WHEN (sellingprice - mmr) > 5000 THEN 'High Profit'
        WHEN (sellingprice - mmr) BETWEEN 0 AND 5000 THEN 'Moderate Profit'
        WHEN (sellingprice - mmr) BETWEEN -2000 AND -1 THEN 'Small Loss'
        ELSE 'Significant Loss'
    END AS profit_category
    
FROM Bright_motors;
