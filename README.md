# db_paginator
Written as a POC mostly to help performance when querying millions of rows with a large date range condition and sorted by that date. This procedure breaks down the date range into smaller chunks to process and returns the results in a cursor.
