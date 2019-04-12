USE AdventureWorksTest

IF Object_Id('tempdb..#WhatHasHappened') IS NOT NULL drop TABLE #WhatHasHappened
CREATE TABLE #WhatHasHappened (object sysname, action VARCHAR(20));

--DROP existing tables
DROP TABLE dbo.DatabaseLog;
INSERT INTO #WhatHasHappened (object, action) SELECT 'DatabaseLog', 'deleted';

DROP TABLE dbo.AWBuildVersion;
INSERT INTO #WhatHasHappened (object, action) SELECT N'AWBuildVersion',
'deleted';
--ADD  tables 
CREATE TABLE dbo.Deleteme (theKey INT IDENTITY PRIMARY KEY);
INSERT INTO #WhatHasHappened (object, action) SELECT N'dbo.Deleteme', 'Added';
--Add a Procedure
GO
CREATE PROCEDURE dbo.LittleStoredProcedure
AS
  BEGIN
    SET NOCOUNT ON;
    SELECT Count(*) FROM sys.indexes AS I;
  END;
GO
INSERT INTO #WhatHasHappened (object, action)
  SELECT N'dbo.LittleStoredProcedure', 'Added';
--create a procedure with an output variable
GO
CREATE PROCEDURE dbo.MySampleProcedure @param1 INT = 0, @param2 INT OUTPUT
AS
SELECT @param2 = @param2 + @param1;
RETURN 0;
go
INSERT INTO #WhatHasHappened (object, action) SELECT N'dbo.MySampleProcedure',
'Added';
GO
--create a schema
CREATE SCHEMA MySchema;
GO
--create a table type
CREATE TYPE MySchema.MyTableType AS TABLE (Id INT, Name VARCHAR(128));
--create a datatype
CREATE TYPE MySchema.MyDataType FROM VARCHAR(11) NOT NULL;
GO
--create a trigger
CREATE TRIGGER MyTriggerName
ON HumanResources.Department
FOR DELETE, INSERT, UPDATE
AS
  BEGIN
    SET NOCOUNT ON;
  END;
GO
INSERT INTO #WhatHasHappened (object, action)
VALUES
  (N'Department.MyTriggerName', 'Added'),
  (N'HumanResources.Department', 'modified');
--create a synonym
CREATE SYNONYM dbo.SynonymName
FOR dbo.LittleStoredProcedure;
INSERT INTO #WhatHasHappened (object, action) SELECT 'dbo.SynonymName','Added'
--create multiStatement TVF
GO
CREATE FUNCTION dbo.FunctionName (@param1 INT, @param2 CHAR(5))
RETURNS @returntable TABLE (c1 INT, c2 CHAR(5))
AS
  BEGIN
    INSERT @returntable SELECT @param1, @param2;
    RETURN;
  END;
GO
INSERT INTO #WhatHasHappened (object, action) SELECT N'dbo.FunctionName',
'Added';
GO
CREATE FUNCTION dbo.MyInlineTableFunction (@param1 INT, @param2 CHAR(5))
RETURNS TABLE
AS
RETURN (SELECT @param1 AS c1, @param2 AS c2);
--add a scalar function
GO
INSERT INTO #WhatHasHappened (object, action)
  SELECT N'dbo.MyInlineTableFunction', 'Added';
GO
CREATE FUNCTION dbo.LeftTrim (@String VARCHAR(MAX))
RETURNS VARCHAR(MAX)
AS
  BEGIN
    RETURN Stuff(
                  ' ' + @String,
                  1,
                  PatIndex(
                            '%[^' + Char(0) + '- ' + Char(160) + ']%',
                            ' ' + @String
                            + '!' COLLATE SQL_Latin1_General_CP850_BIN
                          ) - 1,
                  ''
                );
  END;
GO
INSERT INTO #WhatHasHappened (object, action) SELECT N'dbo.LeftTrim', 'Added';

--drop child objects
--drop a primary key constraint
ALTER TABLE Production.TransactionHistoryArchive
DROP CONSTRAINT PK_TransactionHistoryArchive_TransactionID;
INSERT INTO #WhatHasHappened (object, action)
VALUES
  (N'TransactionHistoryArchive.PK_TransactionHistoryArchive_TransactionID',
'deleted'),
  (N'Production.TransactionHistoryArchive', 'modified');

--drop a default constraint
ALTER TABLE HumanResources.Department DROP CONSTRAINT DF_Department_ModifiedDate;
INSERT INTO #WhatHasHappened (object, action)
  SELECT N'Department.DF_Department_ModifiedDate', 'deleted';
--drop a foreign key constraint
ALTER TABLE HumanResources.EmployeePayHistory
DROP CONSTRAINT FK_EmployeePayHistory_Employee_BusinessEntityID;
INSERT INTO #WhatHasHappened (object, action)
Values
  (N'EmployeePayHistory.FK_EmployeePayHistory_Employee_BusinessEntityID',
'deleted'),-- When a FK constraint is changed, both ends are modified
  (N'HumanResources.Employee', 'modified');

ALTER TABLE HumanResources.EmployeePayHistory
DROP CONSTRAINT PK_EmployeePayHistory_BusinessEntityID_RateChangeDate;
INSERT INTO #WhatHasHappened (object, action)
VALUES
  (N'EmployeePayHistory.PK_EmployeePayHistory_BusinessEntityID_RateChangeDate',
'deleted'),
  (N'HumanResources.EmployeePayHistory', 'modified');
--drop a  check constraint
ALTER TABLE Person.Person DROP CONSTRAINT CK_Person_EmailPromotion;
INSERT INTO #WhatHasHappened (object, action)
VALUES
  (N'Person.CK_Person_EmailPromotion', 'deleted'),
  (N'Person.Person', 'modified');
--drop a trigger
--IF OBJECT_ID ('sales.uSalesOrderHeader', 'TR') IS NOT NULL  
DROP TRIGGER Sales.uSalesOrderHeader;
INSERT INTO #WhatHasHappened (object, action)
VALUES
  (N'Sales.SalesOrderHeader', 'modified'),
  (N'SalesOrderHeader.uSalesOrderHeader', 'deleted');
--drop a unique constraint
ALTER TABLE Production.Document DROP CONSTRAINT UQ__Document__F73921F744672977;
INSERT INTO #WhatHasHappened (object, action)
VALUES
  (N'Document.UQ__Document__F73921F744672977', 'deleted'),
  (N'Production.Document', 'modified');
--add a default constraint
ALTER TABLE Person.EmailAddress ADD CONSTRAINT NoAddress DEFAULT '--' FOR EmailAddress;
INSERT INTO #WhatHasHappened (object, action)
VALUES
  (N'EmailAddress.NoAddress', 'Added'),
  (N'Person.EmailAddress', 'modified');
--add a default constraint
ALTER TABLE Person.CountryRegion WITH NOCHECK ADD CONSTRAINT NoName CHECK (Len(
Name
) > 1
);
INSERT INTO #WhatHasHappened (object, action)
VALUES
  (N'Person.CountryRegion', 'modified'),
  (N'CountryRegion.NoName', 'Added');



SELECT NAME, Object_ID, Modify_Date, Parent_Opject_ID
  FROM  OpenJson(@json)
  WITH 
   (NAME sysname, Object_ID INT, Modify_Date DATETIME, 
    Parent_Object_ID INT) AS original;

CREATE TABLE DatabaseObjectReadings(
	Reading_id int IDENTITY,
	DatabaseName sysname NOT NULL,
	TheDateAndTime datetime NULL default GETDATE(),
	TheJSON NVARCHAR(MAX))

TRUNCATE TABLE DatabaseObjectReadings

INSERT INTO DatabaseObjectReadings (DatabaseName, TheJSON)
SELECT 'Adventureworks2016' AS DatabaseName,
(SELECT --the data you need from the test database's system views
      Coalesce(--if it is a parent, then add the schema name
        CASE WHEN parent_object_id=0 
		THEN Object_Schema_Name(object_id,Db_Id('AdventureWorks2016'))+'.' 
		ELSE Object_Schema_Name(parent_object_id,Db_Id('AdventureWorks2016'))+'.'+
		    Object_Name(parent_Object_id,Db_Id('AdventureWorks2016'))+'.' END
		+ name,'!'+name+'!' --otherwise add the parent object name
		) AS [name], object_id, modify_date, parent_object_id
      FROM AdventureWorks2016.sys.objects
      WHERE is_ms_shipped = 0
	  FOR JSON AUTO) AS TheJSON


SELECT Count(*)
  FROM   AdventureWorkstest.sys.objects new
         LEFT OUTER JOIN OPENJSON((
		SELECT TOP 1 theJSON FROM DatabaseObjectReadings
		WHERE DatabaseName='AdventureWorks2016' ORDER BY TheDateAndTime desc
		))
         WITH([object_id] int, modify_date datetime) AS original
             ON original.Object_ID = new.object_id
                 AND original.Modify_Date = new.modify_date
  WHERE  new.is_ms_shipped = 0
      AND original.Object_ID IS NULL;





DECLARE  @Differences TABLE (object sysname, action VARCHAR(20));
WITH 
  Cloned
AS (SELECT --the data you need from the test database's system views
      Coalesce(--if it is a parent, then add the schema name
        CASE WHEN parent_object_id=0 THEN Object_Schema_Name(object_id)+'.' 
		ELSE Object_Name(parent_Object_id)+'.' END
		+ name,name --otherwise add the parent object name
		) AS [name], object_id, modify_date, parent_object_id
      FROM AdventureWorksTest.sys.objects
      WHERE is_ms_shipped = 0),
  Original 
AS (SELECT --the data you need from the original database's system views
      Coalesce(--if it is a parent, then add the schema name
	    CASE WHEN parent_object_id=0 THEN Object_Schema_Name(object_id)+'.' 
	    ELSE Object_Name(parent_Object_id)+'.' END
	    + name,name --otherwise add the parent object name
	    ) AS [name], object_id, modify_date, parent_object_id
      FROM AdventureWorks2016.sys.objects
      WHERE is_ms_shipped = 0)

INSERT INTO @Differences (object,action) 
SELECT Cloned.name, 'Added' AS action --all added base objects
  FROM Cloned --get the modified
    LEFT OUTER JOIN Original-- check if they are in the original
      ON Cloned.object_id = Original.object_id
  WHERE Original.object_id IS NULL AND cloned.parent_Object_id =0
  --if they are base objects and they aren't in the original
UNION ALL --OK but what if just child objects were added ...
SELECT Clonedchildren.name, 'Added' -- to existing objects?
  FROM Original-- check if they are in both the original
    INNER join Cloned -- and also they are in the clone
      ON Cloned.name = Original.name --not renamed
	    AND Cloned.object_id = Original.object_id
		--for ALL surviving objects
	inner JOIN cloned Clonedchildren--get all the chil objects
	ON Clonedchildren.parent_object_id =cloned.object_id
	LEFT OUTER JOIN -- and compare what child objects there were
    Original OriginalChildren 
	ON Originalchildren.object_id=ClonedChildren.object_id
	WHERE OriginalChildren.object_id IS NULL 
UNION ALL
--all deleted objects but not their children
SELECT Original.name, 'deleted'
  FROM Original --all the objects in the original
    LEFT OUTER JOIN Cloned --all the objects in the clone
      ON Cloned.name = Original.name 
	    AND Cloned.object_id = Original.object_id
  WHERE Cloned.object_id IS NULL AND original.parent_Object_id =0
  --the original base objects that aren't in the clone 
UNION ALL
--all child objects that were deleted where parents survive
SELECT children.name, 'deleted'
  FROM Original
    INNER join Cloned
      ON Cloned.name = Original.name 
	    AND Cloned.object_id = Original.object_id
		--for ALL surviving objects
	inner JOIN Original children
	ON children.parent_object_id =original.object_id
	LEFT OUTER JOIN
    cloned ClonedChildren ON children.object_id=ClonedChildren.object_id
	WHERE ClonedChildren.object_id IS NULL 
UNION ALL
SELECT Original.name,
  CASE WHEN Cloned.name <> Original.name THEN 'renamed'
    WHEN Cloned.modify_date <> Original.modify_date THEN 'modified' ELSE '' END
  FROM Original
    INNER JOIN Cloned
      ON Cloned.object_id = Original.object_id
  WHERE Cloned.modify_date <> Original.modify_date
     OR Cloned.name <> Original.name
  ORDER BY name;
  SELECT * FROM @differences
  
  --CHECK the differences BETWEEN the two tables. It should be none
  SELECT object COLLATE DATABASE_DEFAULT, action  COLLATE DATABASE_DEFAULT 
  AS 'changes that were reported but not announced' 
  FROM @differences 
  EXCEPT 
  SELECT object COLLATE DATABASE_DEFAULT, action  COLLATE DATABASE_DEFAULT 
    FROM #WhatHasHappened

  SELECT object COLLATE DATABASE_DEFAULT, action  COLLATE DATABASE_DEFAULT 
  AS 'changes that were announced but not reported' 
  FROM #WhatHasHappened
  EXCEPT 
  SELECT object COLLATE DATABASE_DEFAULT, action  COLLATE DATABASE_DEFAULT 
  FROM @differences


