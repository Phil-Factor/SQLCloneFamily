
IF Object_Id('dbo.DatabaseChanges') IS NOT NULL
   DROP FUNCTION [dbo].[DatabaseChanges]

IF EXISTS (SELECT * FROM sys.types WHERE name LIKE 'DatabaseUserObjects')
DROP TYPE [dbo].[DatabaseUserObjects]
CREATE TYPE [dbo].[DatabaseUserObjects] AS TABLE
(
   [name] NVARCHAR(4000), object_id int, modify_date Datetime, parent_object_id int
)

go
CREATE FUNCTION [dbo].[DatabaseChanges]
(
    @Original DatabaseUserObjects READONLY ,
    @Comparison DatabaseUserObjects READONLY 
)
RETURNS TABLE AS RETURN
(
SELECT Cloned.name, 'Added' AS action --all added base objects
  FROM @Comparison AS Cloned  --get the modified
    LEFT OUTER JOIN @Original AS Original-- check if they are in the original
      ON Cloned.object_id = Original.object_id
  WHERE Original.object_id IS NULL AND cloned.parent_Object_id =0
  --if they are base objects and they aren't in the original
UNION ALL --OK but what if just child objects were added ...
SELECT Clonedchildren.name, 'Added' -- to existing objects?
  FROM @Original  AS Original-- check if they are in both the original
    INNER join @Comparison AS Cloned -- and also they are in the clone
      ON Cloned.name = Original.name --not renamed
	    AND Cloned.object_id = Original.object_id
		--for ALL surviving objects
	inner JOIN @Comparison AS Clonedchildren--get all the chil objects
	ON Clonedchildren.parent_object_id =cloned.object_id
	LEFT OUTER JOIN -- and compare what child objects there were
    @Original OriginalChildren 
	ON Originalchildren.object_id=ClonedChildren.object_id
	WHERE OriginalChildren.object_id IS NULL 
UNION ALL
--all deleted objects but not their children
SELECT Original.name, 'deleted'
  FROM @Original AS Original --all the objects in the original
    LEFT OUTER JOIN @Comparison AS Cloned --all the objects in the clone
      ON Cloned.name = Original.name 
	    AND Cloned.object_id = Original.object_id
  WHERE Cloned.object_id IS NULL AND original.parent_Object_id =0
  --the original base objects that aren't in the clone 
UNION ALL
--all child objects that were deleted where parents survive
SELECT children.name, 'deleted'
  FROM @Original AS Original
    INNER join @Comparison AS Cloned
      ON Cloned.name = Original.name 
	    AND Cloned.object_id = Original.object_id
		--for ALL surviving objects
	inner JOIN @Original AS children
	ON children.parent_object_id =original.object_id
	LEFT OUTER JOIN
    @Comparison AS ClonedChildren ON children.object_id=ClonedChildren.object_id
	WHERE ClonedChildren.object_id IS NULL 
UNION ALL
SELECT Original.name,
  CASE WHEN Cloned.name <> Original.name THEN 'renamed'
    WHEN Cloned.modify_date <> Original.modify_date THEN 'modified' ELSE '' END
  FROM @Original AS Original
    INNER JOIN @Comparison AS Cloned
      ON Cloned.object_id = Original.object_id
  WHERE Cloned.modify_date <> Original.modify_date
     OR Cloned.name <> Original.name
  )
GO

DECLARE @original AS DatabaseUserObjects
DECLARE @Changed AS DatabaseUserObjects

INSERT INTO @Changed
SELECT --the data you need from the test database's system views
      Coalesce(--if it is a parent, then add the schema name
        CASE WHEN parent_object_id=0 
		THEN Object_Schema_Name(object_id,Db_Id('AdventureWorksTest'))+'.' 
		ELSE Object_Schema_Name(parent_object_id,Db_Id('AdventureWorksTest'))+'.'+
		    Object_Name(parent_Object_id,Db_Id('AdventureWorksTest'))+'.' END
		+ name,'!'+name+'!' --otherwise add the parent object name
		) AS [name], object_id, modify_date, parent_object_id
      FROM AdventureWorksTest.sys.objects
      WHERE is_ms_shipped = 0

INSERT INTO @Original
  SELECT [name], object_id, modify_date, parent_object_id
  --the data you need from the original database's system views
      FROM OpenJson((
		SELECT TOP 1 theJSON FROM DatabaseObjectReadings
		WHERE DatabaseName='AdventureWorks2016' ORDER BY TheDateAndTime desc
		))
         WITH(name NVARCHAR(4000),[object_id] int, modify_date DATETIME, [parent_object_id] int) AS original

SELECT * FROM DatabaseChanges(@Original,@Changed) ORDER BY name

