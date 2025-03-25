SET TERM OFF
SET DEFINE ON
SET ECHO OFF
SET FEEDBACK OFF
SET HEAD OFF
SET LINES 200 
SET PAGES 0
SET TIME   OFF
SET TIMING OFF
SET TRIMSPO ON 
SET VERIFY OFF

-- columns
COL NAME  FORMAT A30
COL VALUE FORMAT A30

-- Set PDB name
column pdb_name for a12 noprint new_value pdb_name
select PDB pdb_name from v$services where PDB not like '%ROOT%';
alter session set container=&pdb_name;

-- date output format
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY/MM/DD HH24:MI:SS';

-- END
SET TERM ON 
