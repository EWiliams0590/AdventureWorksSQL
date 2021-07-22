--- I am interested in the sales of the AdventureWorks company. Specifically, does having a discount have an influence? Does the territory matter where it is sold?
--- Do certain items sell better in different territories, time of year, etc.

-- Below I will create a series of tables, CTEs, etc. to get finally summary data from a procedure at the end.

-- Create Sales Information temp table

CREATE TABLE uSalesInfo
(
SalesOrderID INT,
OrderDate DATE,
TimeOfYear VARCHAR(50),
SalesOrderDetailID INT,
OrderQty INT,
ProductID INT,
SpecialOfferID INT,
UnitPrice MONEY,
UnitPriceDiscount FLOAT,
DiscountFlag TINYINT,
LineTotal MONEY,
TerritoryID INT,
TerritoryName VARCHAR(255)
)

-- Create Product Information temp table

CREATE TABLE uProductInfo
(
ProductID INT,
ProductName VARCHAR(200),
StandardCost MONEY,
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
		UnitPrice,
		UnitPriceDiscount,
		DiscountFlag,
		LineTotal,
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
		   ,B.UnitPrice
		   ,B.UnitPriceDiscount
		   ,CASE
				WHEN B.UnitPriceDiscount = 0 THEN 0
				ELSE 1
			END
		   ,B.LineTotal
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
 
	END

IF @TableName = 'uProductInfo'

	BEGIN
		TRUNCATE TABLE uProductInfo
		INSERT INTO uProductInfo
		(
		ProductID,
		ProductName,
		StandardCost ,
		ProductCategoryID,
		ProductCategoryName,
		ProductSubcategoryID,
		ProductSubCategoryName
		)

		SELECT
			ProductID
		   ,REPLACE([Name], ',', '--') AS ProductName
		   ,StandardCost
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

SELECT *
FROM uSalesInfo

SELECT *
FROM uProductInfo

GO

CREATE VIEW dbo.vProductSalesInfo

AS

SELECT 
	A.*
   ,SaleWeekDay = DATENAME(weekday, A.OrderDate)
   ,B.ProductName
   ,B.ProductCategoryName
   ,B.ProductSubCategoryName
   ,B.StandardCost
   ,TotalCost = A.OrderQty * B.StandardCost
   ,Profit = A.LineTotal - A.OrderQty*B.StandardCost
FROM uSalesInfo A
	JOIN uProductInfo B
		ON A.ProductID = B.ProductID

GO

SELECT *
FROM dbo.vProductSalesInfo

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
