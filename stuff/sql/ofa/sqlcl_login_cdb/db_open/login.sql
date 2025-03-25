SET TERM OFF
SET DEFINE ON
SET VERIFY ON
SET ECHO ON
SET LINES 200 
SET PAGES 10000
SET FEEDBACK ON 
SET FEEDBACK 1
SET TRIMSPO ON 
SET VERIFY ON
SET TIMING ON 
SET SQLBLANKLINES ON 
-- prompt
column db for a12 noprint new_value db
select instance_name db from v$instance;

column con_name for a12 noprint new_value con_name
SELECT replace(SYS_CONTEXT('USERENV', 'CON_NAME'),'$ROOT') con_name from dual;

column user for a30 noprint new_value user;
select user from dual;
set sqlp "&user@&db:&con_name> "

alter session set nls_date_format = 'YYYY/MM/DD HH24:MI:SS';

-- columns
COL COLUMN_NAME    FORMAT A30
COL DB_LINK        FORMAT A15
COL DIRECTORY_PATH FORMAT A30
COL FILE_NAME      FORMAT A50
COL HOST           FORMAT A20
COL HOSTNAME       FORMAT A20
COL INDEX_NAME     FORMAT A30
COL MEMBER         FORMAT A50
COL OBJECT_NAME    FORMAT A35
COL OWNER          FORMAT A15
COL TABLE_NAME     FORMAT A30
COL USERNAME       FORMAT A15
SET TIME ON
-- END
SET TERM ON 
