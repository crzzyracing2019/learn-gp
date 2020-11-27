公平交易
价格代表性
成本

--查询sp代码
select * from pg_proc where proname like '%sp_name%';


--查询视图
select * from pg_views where definition like '%test%';


--递归查询视图的血缘关系
with RECURSIVE w_view1 as (
	select 1 as xh,schemaname ||'.'||viewname as parent_name, cast('dwb.dwb' as varchar) as child_name, 'create or replace view '|| schemaname || '.' || viewname || ' as ' || definition as def
      from pg_views
     where definition like '%dwb.dwb%'
       and definition not like '%dwb.dwb_scd%'
       and definition not like '%dwb.dwb_inc%'
      union
	select xh+1 as xh,schemaname ||'.'||viewname as parent_name, cast('dwb.dwb' as varchar) as child_name, 'create or replace view '|| schemaname || '.' || viewname || ' as ' || definition as def
      from pg_views
      inner join w_view1 w2
        on pv.definition like '%' || w2.parent_name || '%'
       and pv.definition not like
       and definition not like '%dwb.dwb_scd%'
       and definition not like '%dwb.dwb_inc%'

),
w_view2 as (
	select * from w_view2
	  union all
	select xh * -1 as xh ,parent_name,child_name,'drop view ' || parent_name || ' ;  ' as def from w_view1
)
select * from w_view2 order by xh;


--视图注释
select definition from pg_views where viewname = 'dwb+'
 union all
 select 'comment on view '|| left('dwb_v_pty_client',3) || '.' || 'dwb_v_pty_client' || '.' || b.attname || ' is '''
  from pg_catalog.pg_description a
  where objoid = 'dwb.dwb_v_pty_client'::regclass
   and objsubid = 0
 union all
 select *
 from pg_description a,pg_attribute b
 where objoid = 'dwb_v_pty_client'::regclass
 and a.objoid = b.attrelid
 and a.objsubid = b.attname;


 --查询owner
 select * from pg_attribute where oid = '31220';


 --查询namespace
 select * from pg_namespace where oid = '';

 --查询每个表在所有segments上的分布情况
 select gp_segments_id,count(1) from dwb.dwb_v_pty_client group by 1 order by 1;



 --查询是否是分区表
 select * from pg_partition where parrelid = 'public.表名'::regclass;



