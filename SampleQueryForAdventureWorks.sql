--- I am interested in the sales of the AdventureWorks company. Specifically, does having a discount have an influence? Does the territory matter where it is sold?
--- Do certain items sell better in different territories, time of year, etc.

-- Below I will create a series of tables, CTEs, etc. to get finally summary data from a procedure at the end.

-- Create Sales Information table

CREATE TABLE uSalesInfo
(
SalesOrderID INT,
OrderDate DATE,
TimeOfYear VARCHAR(50),
SalesOrderDetailID INT,
OrderQty INT,
ProductID INT,
SpecialOfferID INT,
SpecialOfferDescription VARCHAR(200),
UnitPrice MONEY,
UnitPriceDiscount FLOAT,
DiscountFlag TINYINT,
LineTotal MONEY,
SaleSubtotal MONEY,
SaleTaxAmt MONEY,
SaleFreight MONEY,
SaleTotalDue MONEY,
TerritoryID INT,
TerritoryName VARCHAR(255)
)

-- Create Product Information table

CREATE TABLE uProductInfo
(
ProductID INT,
ProductName VARCHAR(200),
StandardCost MONEY,
ProductWeight FLOAT,
ProductWeightUnit VARCHAR(50),
ProductCategoryName VARCHAR(200),
ProductSubCategoryName VARCHAR(500),
ProductSubcategoryID INT,
ProductCategoryID INT
)
GO

--- Create a function to get the time of year (season).
CREATE FUNCTION dbo.ufnSeasonOfYear(@Date DATE)

RETURNS VARCHAR(10)

AS

BEGIN
	RETURN
		(CASE
			WHEN MONTH(@Date) IN (12, 1, 2) THEN 'Winter'
			WHEN MONTH(@Date) < 6 THEN 'Spring'
			WHEN MONTH(@Date) < 9 THEN 'Summer'
			ELSE 'Autumn'
		END)
END

GO

CREATE PROCEDURE dbo.PopulateTable(@TableName VARCHAR(100))

AS

BEGIN

IF @TableName = 'uSalesInfo'

	BEGIN
		TRUNCATE TABLE uSalesInfo -- Remove contents
		INSERT INTO uSalesInfo
		(
		SalesOrderID,
		OrderDate,
		TimeOfYear,
		SalesOrderDetailID,
		OrderQty,
		ProductID,
		SpecialOfferID,
		SpecialOfferDescription,
		UnitPrice,
		UnitPriceDiscount,
		DiscountFlag,
		LineTotal,
		SaleSubtotal,
		SaleTaxAmt,
		SaleFreight,
		SaleTotalDue,
		TerritoryID,
		TerritoryName
		)

		SELECT
			A.SalesOrderID
		   ,A.OrderDate
		   ,dbo.ufnSeasonOfYear(A.OrderDate)
		   ,B.SalesOrderDetailID
		   ,B.OrderQty
		   ,B.ProductID
		   ,B.SpecialOfferID
		   ,NULL
		   ,B.UnitPrice
		   ,B.UnitPriceDiscount
		   ,CASE
				WHEN B.UnitPriceDiscount = 0 THEN 0
				ELSE 1
			END
		   ,B.LineTotal
		   ,A.SubTotal
		   ,A.TaxAmt
		   ,A.Freight
		   ,A.TotalDue
		   ,A.TerritoryID
		   ,NULL
		FROM Sales.SalesOrderHeader A
			LEFT JOIN Sales.SalesOrderDetail B
				ON A.SalesOrderID = B.SalesOrderID

		UPDATE uSalesInfo
		SET
			TerritoryName = B.[Name]
		FROM uSalesInfo A
			JOIN Sales.SalesTerritory B
				ON A.TerritoryID = B.TerritoryID

		UPDATE uSalesInfo
		SET
			SpecialOfferDescription = B.[Description]
		FROM uSalesInfo A
			JOIN Sales.SpecialOffer B
				ON A.SpecialOfferID = B.SpecialOfferID
 
	END

IF @TableName = 'uProductInfo'

	BEGIN
		TRUNCATE TABLE uProductInfo
		INSERT INTO uProductInfo
		(
		ProductID,
		ProductName,
		StandardCost,
		ProductWeight,
		ProductWeightUnit,
		ProductCategoryID,
		ProductCategoryName,
		ProductSubcategoryID,
		ProductSubCategoryName
		)

		SELECT
			ProductID
		   ,REPLACE([Name], ',', '--') AS ProductName -- Messes up exporting data as CSV
		   ,StandardCost
		   ,[Weight]
		   ,WeightUnitMeasureCode
		   ,NULL
		   ,NULL
		   , ProductSubcategoryID
		   ,NULL
		FROM Production.Product
		WHERE Product.StandardCost > 0 -- If standard cost is zero, then this will not be useful (also seems not possible)

		UPDATE uProductInfo
		SET
			ProductSubCategoryName = B.Name,
			ProductCategoryID = B.ProductCategoryID
		FROM
			uProductInfo A
				JOIN Production.ProductSubcategory B
					ON A.ProductSubcategoryID = B.ProductSubcategoryID

		UPDATE uProductInfo
		SET
			ProductCategoryName = B.[Name]
		FROM uProductInfo A
			JOIN Production.ProductCategory B
				ON A.ProductCategoryID = B.ProductCategoryID

	END

END

GO

EXEC dbo.PopulateTable 'uSalesInfo'
EXEC dbo.PopulateTable 'uProductInfo'

GO

-- As we can see from the uProductInfo, there are many null values. I want to explore the ProductWeight and ProductWeightUnit columns first.

-- Check the ProductWeightUnit column
SELECT DISTINCT ProductWeightUnit
FROM uProductInfo


-- Standardize the Product Weight and make all units 'LB' (Only 'G' and 'LB' used).
-- I am assuming if the ProductWeight is null then it is not important to the Freight (shipping) costs.
BEGIN TRAN

UPDATE uProductInfo
SET
	ProductWeight =
		CASE
			WHEN ProductWeight IS NULL THEN 0
			WHEN ProductWeightUnit = 'G' THEN ProductWeight / 454 
			WHEN ProductWeightUnit = 'LB' THEN ProductWeight
		END,
	ProductWeightUnit = 'LB'

SELECT ProductWeight, ProductWeightUnit
FROM uProductInfo

ROLLBACK TRAN



-- I now want to explore the ProductCategory and ProductSubcategory info.

SELECT *
FROM uProductInfo
WHERE ProductCategoryName IS NULL
	OR ProductSubCategoryName IS NULL


-- As we can see, the only NULL info here is from the ProductIDs 514-522

SELECT *
FROM Production.Product
WHERE ProductID > 513 AND ProductID < 523

-- They all have NULL end dates, meaning they potentially could be sold.
-- The name gives a description of a bicycle seat. Let's see if any other seats are in the Product table

SELECT *
FROM uProductInfo
WHERE ProductName LIKE '%Seat%'

-- This shows that all the other seats have ProductSubcategoryID = 15 and ProductCategoryID = 2, so it makes sense to put those in as well.

BEGIN TRAN
UPDATE uProductInfo
SET
	ProductCategoryID = 2,
	ProductSubcategoryID = 15,
	ProductCategoryName = 'Components',
	ProductSubcategoryName = 'Saddles'
WHERE ProductSubcategoryName IS NULL
	AND ProductName LIKE '%Seat%'

SELECT *
FROM uProductInfo

ROLLBACK TRAN

GO
-- Create a procedure for updating the uProductInfo table
CREATE PROCEDURE dbo.UpdateProductInfo

AS

BEGIN

UPDATE uProductInfo
SET
	ProductWeight =
		CASE
			WHEN ProductWeight IS NULL THEN 0
			WHEN ProductWeightUnit = 'G' THEN ProductWeight / 454 
			WHEN ProductWeightUnit = 'LB' THEN ProductWeight
		END,
	ProductWeightUnit = 'LB'

UPDATE uProductInfo
SET
	ProductCategoryID = 2,
	ProductSubcategoryID = 15,
	ProductCategoryName = 'Components',
	ProductSubcategoryName = 'Saddles'
WHERE ProductSubcategoryName IS NULL
	AND ProductName LIKE '%Seat%'

END

GO

EXEC dbo.UpdateProductInfo

GO

-- Look into SalesInfo now.

SELECT *
FROM uSalesInfo

-- Validate LineTotal is the UnitPrice * OrderQty * (1-UnitPriceDiscount)

SELECT DISTINCT ROUND(LineTotal - OrderQty * UnitPrice * (1 - UnitPriceDiscount), 0)
FROM uSalesInfo

-- All round to zero, so this is good. I will now look into the SpecialOffer info. Specifically,
-- Does the special offer description match up with the quantity when the special offer id in (2, 3, 4, 5, 6)
SELECT *
FROM Sales.SpecialOffer

-- The special order table shows us 1 means no discount and 2-6 are discounts based on volume
-- The other special deals are on specific items for specific dates.

-- First check that the volume discounts are correct.

SELECT
	*
FROM uSalesInfo
WHERE SpecialOfferID IN (2, 3, 4, 5, 6)
ORDER BY OrderQty

-- As we can see, there are a lot of items tagged with SpecialOfferId = 2 (Vol Discount 11-14) with order qty = 1
-- See if any of them were given a discount anyway.

SELECT
	DISTINCT(UnitPriceDiscount)
FROM uSalesInfo
WHERE SpecialOfferID = 2
	AND OrderQty < 11

-- They all have discount zero

SELECT
	*
FROM Sales.SalesOrderDetail
WHERE SpecialOfferID = 2
	AND OrderQty < 11

-- This lines up with the sales order detail, so I will update this in the Sales.SalesOrderDetail
BEGIN TRAN

SELECT
	*
FROM Sales.SalesOrderDetail
WHERE SpecialOfferID = 2
	AND OrderQty < 11

UPDATE Sales.SalesOrderDetail
SET
	SpecialOfferID =
		CASE
			WHEN SpecialOfferID = 2 AND OrderQty < 11 THEN 1
		END
	WHERE SpecialOfferID = 2
		AND OrderQty < 11
	
SELECT
	*
FROM Sales.SalesOrderDetail

ROLLBACK TRAN

-- Update the SalesOrderDetail table

UPDATE Sales.SalesOrderDetail
SET
	SpecialOfferID =
		CASE
			WHEN SpecialOfferID = 2 AND OrderQty < 11 THEN 1
		END
	WHERE SpecialOfferID = 2
		AND OrderQty < 11

-- Re-execute the PopulateTable for uSalesInfo
-- Since this runs from the underlying SalesOrderDetail, it will be corrected.

EXEC dbo.PopulateTable 'uSalesInfo'

SELECT DISTINCT
	OrderQty
   ,SpecialOfferID
   ,SpecialOfferDescription
   ,UnitPriceDiscount
FROM uSalesInfo
ORDER BY SpecialOfferID, OrderQty

GO

WITH CTE1 AS (
SELECT 
	A.SalesOrderID
   ,A.OrderDate
   ,A.TimeOfYear
   ,SaleWeekDay = DATENAME(weekday, A.OrderDate)
   ,A.ProductID
   ,A.UnitPriceDiscount
   ,A.specialOfferID
   ,A.SpecialOfferDescription
   ,A.OrderQty
   ,A.DiscountFlag
   ,A.LineTotal
   ,TotalCost = B.StandardCost  * A.OrderQty
   ,A.TerritoryName
   ,B.ProductName
   ,B.ProductCategoryName
   ,B.ProductSubCategoryName
   ,AmountOfFreight = 
		CASE
			WHEN SUM(B.ProductWeight) OVER(PARTITION BY SalesOrderID) = 0 THEN 0
			ELSE CAST(B.ProductWeight*A.OrderQty / (SUM(B.ProductWeight*A.OrderQty) OVER(PARTITION BY SalesOrderID)) * A.SaleFreight AS MONEY)
		END
   ,AmountOfSalesTax = A.LineTotal / A.SaleSubtotal * A.SaleTaxAmt -- Line total takes into account the OrderQty
FROM uSalesInfo A
	JOIN uProductInfo B
		ON A.ProductID = B.ProductID)


SELECT
	*
   ,TotalSale = LineTotal + AmountOfFreight + AmountOfSalesTax
   ,TotalProfit = LineTotal + AmountOfFreight + AmountOfSalesTax - TotalCost
FROM CTE1
WHERE SalesOrderID = 46688
ORDER BY SalesOrderID 


GO

ALTER VIEW dbo.vProductSalesInfo

AS

WITH CTE1 AS (
SELECT 
	A.SalesOrderID
   ,A.OrderDate
   ,A.TimeOfYear
   ,SaleWeekDay = DATENAME(weekday, A.OrderDate)
   ,A.ProductID
   ,A.UnitPriceDiscount
   ,A.SpecialOfferID
   ,A.SpecialOfferDescription
   ,A.OrderQty
   ,A.DiscountFlag
   ,A.LineTotal
   ,TotalCost = B.StandardCost  * A.OrderQty
   ,A.TerritoryName
   ,B.ProductName
   ,B.ProductCategoryName
   ,B.ProductSubCategoryName
   ,AmountOfFreight = 
		CASE
			WHEN SUM(B.ProductWeight) OVER(PARTITION BY SalesOrderID) = 0 THEN 0
			ELSE CAST(B.ProductWeight*A.OrderQty / (SUM(B.ProductWeight*A.OrderQty) OVER(PARTITION BY SalesOrderID)) * A.SaleFreight AS MONEY)
		END
   ,AmountOfSalesTax = A.LineTotal / A.SaleSubtotal * A.SaleTaxAmt -- Line total takes into account the OrderQty
FROM uSalesInfo A
	JOIN uProductInfo B
		ON A.ProductID = B.ProductID)


SELECT
	*
   ,TotalSale = LineTotal + AmountOfFreight + AmountOfSalesTax
   ,TotalProfit = LineTotal + AmountOfFreight + AmountOfSalesTax - TotalCost
FROM CTE1

GO

-- Create a View that gives the ListPrice and the dates of them. I noticed the Production.ProductListPriceHistory
-- Had consecutive rows/dates with the same price, so the below view consolidates the data into one.

CREATE VIEW vListPriceInfo AS
WITH ProductPricesWithRank AS
(
SELECT
	ProductID
   ,StartDate
   ,EndDate
   ,ListPrice
   ,DENSE_RANK() OVER(PARTITION BY ProductID ORDER BY ListPrice) AS ProductPriceRank
FROM Production.ProductListPriceHistory
)

SELECT DISTINCT
	ProductID
   ,ListPrice
   ,ListPriceStartDate = CAST(MIN(StartDate) OVER(PARTITION BY ProductPriceRank, ProductID) AS DATE)
   ,ListPriceEndDate = CAST(MAX(EndDate) OVER(PARTITION BY ProductPriceRank, ProductID) AS DATE)
FROM ProductPricesWithRank
