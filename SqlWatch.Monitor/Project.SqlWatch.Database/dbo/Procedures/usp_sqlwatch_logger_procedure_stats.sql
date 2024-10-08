﻿CREATE PROCEDURE [dbo].[usp_sqlwatch_logger_procedure_stats]
as

begin

	set nocount on;
	set xact_abort on;

	declare @snapshot_type_id smallint = 27,
			@snapshot_time datetime2(0),
			@date_snapshot_previous datetime2(0),
			@sql_instance varchar(32) = [dbo].[ufn_sqlwatch_get_servername]()

	select @date_snapshot_previous = max([snapshot_time])
	from [dbo].[sqlwatch_logger_snapshot_header] (nolock) --so we dont get blocked by central repository. this is safe at this point.
	where snapshot_type_id = @snapshot_type_id
	and sql_instance = @sql_instance
	option (keep plan);

	select 
		  sql_instance
		, sqlwatch_database_id
		, [sqlwatch_procedure_id]
		, total_worker_time
		, total_physical_reads
		, total_logical_writes
		, total_logical_reads
		, total_elapsed_time
		, cached_time
		, last_execution_time
		, execution_count
	into #t
	from [dbo].[sqlwatch_logger_perf_procedure_stats]
	where sql_instance = @sql_instance
	and snapshot_type_id = @snapshot_type_id
	and snapshot_time = @date_snapshot_previous
	option (keep plan);
	
	create unique clustered index icx_tmp_t1 on #t (sql_instance,sqlwatch_database_id,[sqlwatch_procedure_id], cached_time)

	exec [dbo].[usp_sqlwatch_internal_insert_header] 
		@snapshot_time_new = @snapshot_time OUTPUT,
		@snapshot_type_id = @snapshot_type_id	

	insert into [dbo].[sqlwatch_logger_perf_procedure_stats] (
			[cached_time] ,
			[last_execution_time] ,

			[execution_count] ,
			[total_worker_time] ,
			[last_worker_time] ,
			[min_worker_time] ,
			[max_worker_time] ,
			[total_physical_reads] ,
			[last_physical_reads] ,
			[min_physical_reads] ,
			[max_physical_reads] ,
			[total_logical_writes] ,
			[last_logical_writes] ,
			[min_logical_writes] ,
			[max_logical_writes] ,
			[total_logical_reads],
			[last_logical_reads] ,
			[min_logical_reads] ,
			[max_logical_reads] ,
			[total_elapsed_time],
			[last_elapsed_time] ,
			[min_elapsed_time] ,
			[max_elapsed_time]

			,delta_worker_time
			,delta_physical_reads
			,delta_logical_writes
			,delta_logical_reads
			,delta_elapsed_time
			,delta_execution_count

			,[sql_instance]
			,[sqlwatch_database_id]
			,[sqlwatch_procedure_id]
			,[snapshot_time] 
			,[snapshot_type_id] 

	)

	--get procedure stats:
	select 
		  ps.cached_time	
		, PS.last_execution_time

		, execution_count=convert(real,ps.execution_count)
		, total_worker_time=convert(real,ps.total_worker_time)
		, last_worker_time=convert(real,last_worker_time)
		, min_worker_time=convert(real,min_worker_time)
		, max_worker_time=convert(real,max_worker_time)	
		, total_physical_reads=convert(real,ps.total_physical_reads)	
		, last_physical_reads=convert(real,last_physical_reads)	
		, min_physical_reads=convert(real,min_physical_reads)	
		, max_physical_reads=convert(real,max_physical_reads)	
		, total_logical_writes=convert(real,ps.total_logical_writes)	
		, last_logical_writes=convert(real,last_logical_writes)	
		, min_logical_writes=convert(real,min_logical_writes)	
		, max_logical_writes=convert(real,max_logical_writes)	
		, total_logical_reads=convert(real,ps.total_logical_reads)	
		, last_logical_reads=convert(real,last_logical_reads)	
		, min_logical_reads=convert(real,min_logical_reads)	
		, max_logical_reads=convert(real,max_logical_reads)	
		, total_elapsed_time=convert(real,ps.total_elapsed_time)	
		, last_elapsed_time=convert(real,last_elapsed_time)	
		, min_elapsed_time=convert(real,min_elapsed_time)	
		, max_elapsed_time=convert(real,max_elapsed_time)

		, delta_worker_time=convert(real,case when ps.total_worker_time > isnull(prev.total_worker_time,0) then ps.total_worker_time - isnull(prev.total_worker_time,0) else 0 end)
		, delta_physical_reads=convert(real,case when ps.total_physical_reads > isnull(prev.total_physical_reads,0) then ps.total_physical_reads - isnull(prev.total_physical_reads,0) else 0 end)
		, delta_logical_writes=convert(real,case when ps.total_logical_writes > isnull(prev.total_logical_writes,0) then ps.total_logical_writes - isnull(prev.total_logical_writes,0) else 0 end)
		, delta_logical_reads=convert(real,case when ps.total_logical_reads > isnull(prev.total_logical_reads,0) then ps.total_logical_reads - isnull(prev.total_logical_reads,0) else 0 end)
		, delta_elapsed_time=convert(real,case when ps.total_elapsed_time > isnull(prev.total_elapsed_time,0) then ps.total_elapsed_time - isnull(prev.total_elapsed_time,0) else 0 end)
		, delta_execution_count=convert(real,case when ps.execution_count> isnull(prev.execution_count,0) then ps.execution_count - isnull(prev.execution_count,0) else 0 end)

		, @sql_instance
		, sd.sqlwatch_database_id
		, p.sqlwatch_procedure_id
		, @snapshot_time
		, @snapshot_type_id

	from sys.dm_exec_procedure_stats ps (nolock)

	inner join dbo.vw_sqlwatch_sys_databases d
		on d.database_id = ps.database_id
	
	inner join dbo.sqlwatch_meta_database sd
		on sd.database_name = d.name collate database_default
		and sd.database_create_date = d.create_date
		and sd.sql_instance = d.sql_instance

	inner join dbo.sqlwatch_meta_procedure p
		on p.procedure_name = object_schema_name(ps.object_id, ps.database_id) + '.' + object_name(ps.object_id, ps.database_id)
		and p.sql_instance = @sql_instance
		and p.sqlwatch_database_id = sd.sqlwatch_database_id

	left join [dbo].[sqlwatch_config_exclude_procedure] ex
		on sd.database_name like ex.database_name_pattern
		and p.procedure_name like ex.procedure_name_pattern
		and ex.snapshot_type_id = @snapshot_type_id

	left join #t prev
		on prev.sql_instance = sd.sql_instance
		and prev.sqlwatch_database_id = sd.sqlwatch_database_id
		and prev.[sqlwatch_procedure_id] = p.[sqlwatch_procedure_id]
		and prev.cached_time = ps.cached_time

	where ps.type = 'P'
	and ex.snapshot_type_id is null
	and (
		ps.last_execution_time > prev.last_execution_time
		or prev.last_execution_time is null
	)

	option (keep plan);


end