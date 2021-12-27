# db_paginator
Written as a POC mostly to help performance when querying millions of rows with a large date range condition and sorted by that date. This procedure breaks down the date range into smaller chunks to process and returns the results in a cursor.

## Paremeters:

  *t_reportname varchar2: 
    -- this can be a table name or a view
  *t_collist VARCHAR2:  
    -- list of columns in the table or view that you want returned
*t_reportconditions varchar2: 
    -- conditions to pass
*t_pkcolname varchar2:  
    -- name of the primary key column
*t_datecolname varchar2:  
    -- name of the date column that you are passing a condition on and are sorting by
*t_sessionid IN VARCHAR2:  
    -- identifier for the session executing the procedure
*t_numrows IN NUMBER: 
    -- number of rows to return
*t_dtfrom IN DATE: 
    -- from date to pass as a condition on t_datecolname
*t_dtto IN DATE: 
    -- to date to pass as a condition on t_datecolname
*t_pageno_in IN NUMBER: 
    -- OPTIONAL: if NULL runs for the next page to be generated.  If you pass a value, it will look for a previously generated page in report_scroll and return those results.
*t_sort IN VARCHAR2:  
    -- ASC or DESC
*t_hasmore OUT CHAR:  
    -- return to the applicaiton 'Y' or 'N' as an indicator if there are more records
*t_rec_output OUT SYS_REFCURSOR:
     -- the return resuls


Tables:

report_settings:
    this can be used to give a hint for the time interval to use for a give table/view query.  
    In the procedure, a very simplistic method is used to determine what interval to use.  If you have a good interval to use, set it in the dayinterval column for the "reportname". Make sure to set "forcesetting" to 'Y'.

report_instance:
    This is used to log the instance of someone running  the report.

report_scroll:
    An entry exists for each page generated for a given report_instance.       

Sample Call from SQL Developer:


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
  T_REPORTNAME := 'acct_trans_vw1';
  T_COLLIST := 'ACC_ID, ACC_NUMBER, ACC_NAME, BANK_ID, TX_CODE, BOOK_DATE, TX_ID';
  T_REPORTCONDITIONS := 'ACC_ID =1934863';
  T_PKCOLNAME := 'TX_ID';
  T_DATECOLNAME := 'BOOK_DATE';
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
