# DB Paginator
Written as a POC, mostly to help performance when querying a large number of rows retrned from a date range condition and sorted by that date. This was born from a hypothetical requirement where a client may need to have the ability to view top n transaction data sorted by date from a large amount of data.  In this case, sorting would be the pain point as the number of rows returned for a given date range would be very large (millions). This procedure breaks down the date range into smaller chunks to process and returns the results in a cursor.  It keeps track of where it leaves off to support stateless applications and to mimic pagination. Subsequent calls will return the next rows. 

## Paremeters:

1. t_reportname varchar2: 
    -- this can be a table name or a view
2. t_collist VARCHAR2: -- list of columns in the table or view that you want returned
3. t_reportconditions varchar2: -- additional conditions to pass besides the date condition in t_datecolname, t_dtfrom and t_dtto below
4. t_pkcolname varchar2: -- name of the primary key column
5. t_datecolname varchar2: -- name of the date column that you are passing a condition on and are sorting by
6. t_sessionid IN VARCHAR2: -- identifier for the session executing the procedure
7. t_numrows IN NUMBER: -- number of rows to return
8. t_dtfrom IN DATE: -- from date to pass as a condition on t_datecolname
9. t_dtto IN DATE: -- to date to pass as a condition on t_datecolname
10. t_pageno_in IN NUMBER: -- OPTIONAL: if NULL runs for the next page to be generated.  If you pass a value, it will look for a previously generated page in report_scroll and return those results.
11. t_sort IN VARCHAR2: -- ASC or DESC
12. t_hasmore OUT CHAR: -- return to the application 'Y' or 'N' as an indicator if there are more records
13. t_rec_output OUT SYS_REFCURSOR: -- the return results


## Tables:

1. report_settings:
    this can be used to give a hint for the time interval to use for a give table/view query.  
    In the procedure, a very simplistic method is used to determine what interval to use.  If you have an optimal interval to use, set it in the dayinterval column for the "reportname". Make sure to set "forcesetting" to 'Y'.

2. report_instance:
    This is used to log the instance of someone running  the report.

3. report_scroll:
    An entry exists for each page generated for a given report_instance.       

### Sample Call from SQL Developer:

```sql
DECLARE
  T_REPORTNAME VARCHAR2(200);
  T_COLLIST VARCHAR2(200);
  T_REPORTCONDITIONS VARCHAR2(200);
  T_PKCOLNAME VARCHAR2(200);
  T_DATECOLNAME VARCHAR2(200);
  T_SESSIONID VARCHAR2(200);
  T_NUMROWS NUMBER;
  T_DTFROM DATE;
  T_DTTO DATE;
  T_PAGENO_IN NUMBER;
  T_SORT VARCHAR2(200);
  T_HASMORE CHAR(200);
  T_REC_OUTPUT SYS_REFCURSOR;
BEGIN
  T_REPORTNAME := 'BIG_TRANSACTION_VIEW';
  T_COLLIST := 'COLUMN_1, COLUMN_2, COLUMN_3, COLUMN_4';
  T_REPORTCONDITIONS := 'ACC_ID =1934863';
  T_PKCOLNAME := 'PRIMARYKEY_ID';
  T_DATECOLNAME := 'DATECOLUMN';
  T_SESSIONID := '3';
  T_NUMROWS := 15;
  T_DTFROM := to_date('2021-07-12','yyyy-MM-dd');
  T_DTTO := to_date('2021-10-12','yyyy-MM-dd');
  T_PAGENO_IN := NULL;
  T_SORT := 'DESC';

  ACCT15M.REPORT_PAGINATOR(
    T_REPORTNAME => T_REPORTNAME,
    T_COLLIST => T_COLLIST,
    T_REPORTCONDITIONS => T_REPORTCONDITIONS,
    T_PKCOLNAME => T_PKCOLNAME,
    T_DATECOLNAME => T_DATECOLNAME,
    T_SESSIONID => T_SESSIONID,
    T_NUMROWS => T_NUMROWS,
    T_DTFROM => T_DTFROM,
    T_DTTO => T_DTTO,
    T_PAGENO_IN => T_PAGENO_IN,
    T_SORT => T_SORT,
    T_HASMORE => T_HASMORE,
    T_REC_OUTPUT => T_REC_OUTPUT
  );
  /* Legacy output: 
DBMS_OUTPUT.PUT_LINE('T_HASMORE = ' || T_HASMORE);
*/ 
  :T_HASMORE := T_HASMORE;
  /* Legacy output: 
DBMS_OUTPUT.PUT_LINE('T_REC_OUTPUT = ' || T_REC_OUTPUT);
*/ 
  :T_REC_OUTPUT := T_REC_OUTPUT; --<-- Cursor
--rollback; 
END;
```