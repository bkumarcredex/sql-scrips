SET NOCOUNT ON;

DECLARE 
    @TableName NVARCHAR(255),
    @SQL NVARCHAR(MAX);

-- Step 1: Create a temporary table to store fragmentation info
IF OBJECT_ID('tempdb..#FragList') IS NOT NULL DROP TABLE #FragList;

SELECT 
    OBJECT_NAME(ps.object_id) AS TableName,
    i.name AS IndexName,
    ps.index_id,
    ps.avg_fragmentation_in_percent,
    ps.page_count
INTO #FragList
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
JOIN sys.indexes i ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE ps.page_count > 100 -- ignore small indexes
ORDER BY ps.avg_fragmentation_in_percent DESC;

-- Step 2: Loop through and fix fragmentation
DECLARE FragCursor CURSOR FOR
SELECT DISTINCT TableName FROM #FragList;

OPEN FragCursor;
FETCH NEXT FROM FragCursor INTO @TableName;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT 'Processing table: ' + @TableName;

    -- REORGANIZE indexes with fragmentation between 5% and 30%
    SET @SQL = (
        SELECT STRING_AGG('ALTER INDEX [' + IndexName + '] ON [' + @TableName + '] REORGANIZE;', CHAR(13))
        FROM #FragList
        WHERE TableName = @TableName AND avg_fragmentation_in_percent BETWEEN 5 AND 20
    );

    IF @SQL IS NOT NULL
    BEGIN
        PRINT '  Reorganizing indexes...';
        EXEC sp_executesql @SQL;
    END

    -- REBUILD indexes with fragmentation > 30%
    SET @SQL = (
        SELECT STRING_AGG('ALTER INDEX [' + IndexName + '] ON [' + @TableName + '] REBUILD WITH (ONLINE = OFF);', CHAR(13))
        FROM #FragList
        WHERE TableName = @TableName AND avg_fragmentation_in_percent > 20
    );

    IF @SQL IS NOT NULL
    BEGIN
        PRINT '  Rebuilding indexes...';
        EXEC sp_executesql @SQL;
    END

    FETCH NEXT FROM FragCursor INTO @TableName;
END

CLOSE FragCursor;
DEALLOCATE FragCursor;

-- Step 3: Update statistics
PRINT 'Updating statistics...';
EXEC sp_updatestats;

PRINT '✅ Index defragmentation completed successfully.';
